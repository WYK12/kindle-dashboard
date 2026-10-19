"""Host checks: real Lua layout/renderer with mocked Kindle hardware, native UI lifecycle.
Run: MYDASH_KOREADER_COMMON=/path/to/koreader/common python3 tests/test_fullscreen.py.
Host previews use Noto Sans CJK; Kindle's STHeiti and hardware need device verification.
"""
from pathlib import Path
import ctypes as C
import ctypes.util
import json
import os
import subprocess
import tempfile
import shutil
import time
import signal
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'src/mydash_v2'
OUT = ROOT / 'artifacts'
OUT.mkdir(exist_ok=True)
LUA = C.CDLL(ctypes.util.find_library('lua5.3'))
LUA.luaL_newstate.restype = C.c_void_p
LUA.luaL_openlibs.argtypes = [C.c_void_p]
LUA.luaL_loadbufferx.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t, C.c_char_p, C.c_char_p]
LUA.lua_pcallk.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ssize_t, C.c_void_p]
LUA.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.c_void_p]
LUA.lua_tolstring.restype = C.c_char_p
LUA.lua_close.argtypes = [C.c_void_p]

def lua(code):
    state = LUA.luaL_newstate()
    LUA.luaL_openlibs(state)
    try:
        raw = code.encode()
        status = LUA.luaL_loadbufferx(state, raw, len(raw), b'host-test', None)
        if not status:
            status = LUA.lua_pcallk(state, 0, 0, 0, 0, None)
        assert status == 0, LUA.lua_tolstring(state, -1, None).decode()
    finally:
        LUA.lua_close(state)

# Compile every Lua file without executing any Kindle system calls.
for path in (ROOT / 'src').rglob('*.lua'):
    lua('assert(loadfile(' + json.dumps(str(path)) + '))')
for path in (ROOT / 'src').rglob('*.sh'):
    subprocess.run(['sh', '-n', str(path)], check=True)
print('PASS: Lua and shell syntax')

# Exercise actual hide, keep-awake, restore and failure/retry behavior with fake services.
with tempfile.TemporaryDirectory() as folder:
    tmp = Path(folder)
    commands = tmp / 'bin'
    commands.mkdir()
    mock = '''#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$MOCK_LOG"
[ -n "$MOCK_FAIL" ] && [ "${0##*/}" = "$MOCK_FAIL" ] && exit 1
case "${0##*/}" in
 pgrep) [ "$*" = "-x cvm" ] && exit 0; exit 1 ;;
 lipc-get-prop) cat "$MOCK_VALUE" ;;
 lipc-set-prop) [ "$2" = preventScreenSaver ] && printf '%s' "$3" > "$MOCK_VALUE" ;;
 luajit) case "$2" in disable) [ -f "$3" ] || printf 1 > "$3" ;; restore) rm -f "$3" ;; esac ;;
esac
exit 0
'''
    for name in ['killall', 'lipc-get-prop', 'lipc-set-prop', 'pgrep', 'lua', 'luajit']:
        path = commands / name
        path.write_text(mock)
        path.chmod(0o755)
    env = dict(os.environ, PATH=str(commands) + ':' + os.environ['PATH'],
               MYDASH_NATIVE_STATE=str(tmp / 'state'), MOCK_LOG=str(tmp / 'calls'),
               MOCK_VALUE=str(tmp / 'value'), MOCK_FAIL='')
    native_control = tmp / 'native_ui.sh'
    native_control.write_text((APP / 'native_ui.sh').read_text().replace('/mnt/us/koreader/luajit', str(commands / 'luajit')))
    def native(*args, fail=False):
        result = subprocess.run(['sh', str(native_control), *args], env=env)
        assert (result.returncode != 0) == fail
    for original in ['0', '1']:
        (tmp / 'value').write_text(original)
        native('hide')
        calls = (tmp / 'calls').read_text().splitlines()
        assert calls[-2].startswith('lua -e ') and 'apply_halftone(ref,0)' in calls[-2]
        assert calls[-1].startswith('luajit ') and ' disable ' in calls[-1]
        assert (tmp / 'state/native-touch').read_text() == '1'
        assert (tmp / 'state/volumd').exists()
        assert 'killall -STOP volumd' in calls
        before=calls.count('killall -STOP volumd')
        assert calls.index('killall -STOP awesome') < len(calls) - 1
        native('hide')
        assert (tmp / 'calls').read_text().splitlines().count('killall -STOP volumd')==before+1,'Hide must reassert USB protection across reader handoff'
        native('awake', '1')
        assert (tmp / 'value').read_text() == '1'
        native('awake', '1')
        native('show')
        assert not (tmp / 'state/volumd').exists()
        assert 'killall -CONT volumd' in (tmp / 'calls').read_text()
        native('hide')
        native('restore')
        assert (tmp / 'value').read_text() == original
        assert not (tmp / 'state').exists()
        native('restore')
    env['MOCK_FAIL'] = 'killall'
    native('hide', fail=True)
    assert (tmp / 'state/pillow').exists()
    env['MOCK_FAIL'] = ''
    native('restore')
    assert not (tmp / 'state').exists()
    env['MOCK_FAIL'] = 'lua'
    native('hide', fail=True)
    assert (tmp / 'state/awesome').exists()
    env['MOCK_FAIL'] = ''
    native('restore')
    assert not (tmp / 'state').exists(), 'halftone failure must allow native UI restoration'
    env['MOCK_FAIL'] = 'luajit'
    native('hide', fail=True)
    assert (tmp / 'state/awesome').exists()
    env['MOCK_FAIL'] = ''
    native('restore')
    native('hide')
    env['MOCK_FAIL'] = 'luajit'
    native('restore', fail=True)
    assert (tmp / 'state/native-touch').exists(), 'failed native input restoration must remain retryable'
    env['MOCK_FAIL'] = ''
    native('restore')
    assert not (tmp / 'state').exists()
    env['MOCK_FAIL'] = 'lipc-get-prop'
    native('awake', '1', fail=True)
    assert not (tmp / 'state/screensaver').exists()
    env['MOCK_FAIL'] = ''
    # Run the actual reader exit block: only managed, clean home exits hand off.
    wrapper = (ROOT / 'src/koreader/koreader.sh').read_text()
    volumd_cleanup = wrapper[wrapper.index('# Resume volumd, if need be'):wrapper.index('# Resume cvm (only if we stopped it)')]
    for managed,owned in [('0',False),('0',True),('1',False),('1',True)]:
        (tmp/'state').mkdir(exist_ok=True)
        marker=tmp/'state/volumd'
        if owned: marker.touch()
        elif marker.exists(): marker.unlink()
        result=subprocess.run(['sh','-c','logmsg() { echo "$*"; }; '+volumd_cleanup],env=dict(env,MYDASH_MANAGED_READER=managed,VOLUMD_STOPPED='yes'),capture_output=True,check=True)
        assert (b'Resuming volumd' in result.stdout)==(managed!='1' or not owned),'Managed reader must retain dashboard USB ownership'
    marker.unlink(missing_ok=True)
    (tmp/'state').rmdir()
    service_setup = wrapper[wrapper.index('TOGGLED_SERVICES='):wrapper.index('REEXEC_FLAGS=')]
    for managed in ['0', '1']:
        result = subprocess.run(['sh', '-c', service_setup + '\nprintf "%s" "$TOGGLED_SERVICES"'],
                                env=dict(env, MYDASH_MANAGED_READER=managed), capture_output=True, check=True)
        assert bool(result.stdout.strip()) == (managed == '0'), 'only managed launches skip service churn'
    start = wrapper.index('# MYDASH_DIRECT_HOME:')
    end = wrapper.index('if [ "${INIT_TYPE}" = "upstart" ] ||', start)
    reader_cleanup = wrapper[start:end]
    owned_runner = tmp / 'owned-run.sh'
    owned_runner.write_text('#!/bin/sh\nexit 0\n')
    owned_runner.chmod(0o755)
    reader_cleanup = reader_cleanup.replace('/mnt/us/mydash_v2/run.sh', str(owned_runner)).replace('/tmp/mydash-v2-return', str(tmp / 'return')).replace('/var/tmp/koreader-fb.dump', str(tmp / 'fb.dump')).replace('/dev/fb0', str(tmp / 'fb.out'))
    for managed, result, destination in [('1', '0', 'home'), ('1', '0', 'rss'), ('0', '0', 'home'), ('1', '1', 'home'), ('1', '0', 'native')]:
        (tmp / 'return').write_text(destination)
        (tmp / 'fb.dump').write_text('native screen')
        before = len((tmp / 'calls').read_text().splitlines())
        reader_env = dict(env, MYDASH_MANAGED_READER=managed, RETURN_VALUE=result,
                          STOP_FRAMEWORK='no', INIT_TYPE='upstart', AWESOME_STOPPED='yes',
                          PILLOW_HARD_DISABLED='yes', PILLOW_SOFT_DISABLED='no',
                          USED_WMCTRL='no', TOGGLED_SERVICES='')
        subprocess.run(['sh', '-c', 'logmsg() { :; }\n' + reader_cleanup], env=reader_env, check=True)
        new_calls = (tmp / 'calls').read_text().splitlines()[before:]
        direct = managed == '1' and result == '0' and destination in ['home', 'rss']
        assert (tmp / 'state/reader-handoff').exists() == direct
        assert any('killall -CONT awesome' == call for call in new_calls) != direct
        assert any('com.lab126.appmgrd start' in call for call in new_calls) != direct
        native('restore')
        assert not (tmp / 'state').exists()
    # Exercise the real supervisor after redirecting only hardware paths to this sandbox.
    mount = tmp / 'usb'
    app = mount / 'mydash_v2'
    kr = mount / 'koreader'
    app.mkdir(parents=True)
    kr.mkdir()
    shutil.copy2(native_control, app / 'native_ui.sh')
    runner = (APP / 'run.sh').read_text().replace('/mnt/us', str(mount)).replace('/var/tmp/mydash-v2', str(tmp / 'var')).replace('/tmp/mydash-v2', str(tmp / 'run'))
    (app / 'run.sh').write_text(runner)
    (kr / 'fbink').write_text('#!/bin/sh\necho "screenWidth=1072;screenHeight=1448;"\n')
    (kr / 'fbink').chmod(0o755)
    (commands / 'pgrep').write_text('#!/bin/sh\nexit 1\n')
    (commands / 'pgrep').chmod(0o755)
    (kr / 'luajit').write_text('''#!/bin/sh
sh "$MYDASH_ROOT/native_ui.sh" hide || exit 1
sh "$MYDASH_ROOT/native_ui.sh" awake 1 || exit 1
printf native > "$MYDASH_ROOT/next_action"
case "$MOCK_MODE" in forward|forward_rss|forward_reader|launch_fail)
 if [ ! -e "$MYDASH_ROOT/forward-once" ]; then
  touch "$MYDASH_ROOT/forward-once"
  if [ "$MOCK_MODE" = forward_rss ]; then printf readarticle > "$MYDASH_ROOT/next_action"
  elif [ "$MOCK_MODE" = forward_reader ]; then printf reader > "$MYDASH_ROOT/next_action"
  else printf bookstore > "$MYDASH_ROOT/next_action"; fi
 fi ;;
esac
if [ "$(cat "$MOCK_RESUME" 2>/dev/null)" = rss ]; then printf 'RSS_RESUMED\n' >> "$MOCK_LOG"; fi
rm -f "$MOCK_RESUME"
printf ready > "$MOCK_READY"
case "$MOCK_MODE" in signal) exec sleep 30 ;; fail) exit 7 ;; esac
''')
    (kr / 'luajit').chmod(0o755)
    env['MOCK_READY'] = str(tmp / 'ready')
    env['MOCK_RETURN'] = str(tmp / 'run-return')
    env['MOCK_RESUME'] = str(tmp / 'run-resume')
    launch = mount / 'kmc/kpm/packages/koreader/launch.sh'
    launch.parent.mkdir(parents=True)
    launch.write_text('''#!/bin/sh
[ -f "$MYDASH_NATIVE_STATE/awesome" ] && [ -f "$MYDASH_NATIVE_STATE/pillow" ] || exit 9
[ "$MYDASH_MANAGED_READER" = 1 ] && [ "$1" = --asap ] || exit 10
printf 'FORWARD_PAUSED_UI\n' >> "$MOCK_LOG"
if [ "$MOCK_MODE" = forward_reader ]; then [ "$2" = "$MOCK_BOOK" ] && [ "$MYDASH_BOOKSTORE" = 1 ] || exit 11; fi
[ "$MOCK_MODE" = launch_fail ] && exit 7
touch "$MYDASH_NATIVE_STATE/reader-handoff"
if [ "$MOCK_MODE" = forward_rss ]; then printf rss > "$MOCK_RETURN"
else printf home > "$MOCK_RETURN"; fi
''')
    rss = mount / 'RSS'
    rss.mkdir()
    (rss / ('a' * 24 + '.epub')).touch()
    (app / 'reader_id').write_text('a' * 24)
    books = mount / 'Books'
    books.mkdir()
    book = books / '测试 书.epub'
    book.touch()
    env['MOCK_BOOK'] = str(book)
    for mode in ['normal', 'handoff', 'forward', 'forward_rss', 'forward_reader', 'launch_fail', 'fail', 'signal']:
        (tmp / 'value').write_text('0')
        (tmp / 'ready').unlink(missing_ok=True)
        (app / 'forward-once').unlink(missing_ok=True)
        (app / 'reader_book').write_text(str(book))
        env['MOCK_MODE'] = mode
        (tmp / 'run-return').write_text('home')
        (tmp / 'run-resume').write_text('rss')
        if mode == 'handoff':
            (tmp / 'state').mkdir()
            for name in ['awesome', 'pillow', 'reader-handoff']:
                (tmp / 'state' / name).touch()
        before = len((tmp / 'calls').read_text().splitlines())
        proc = subprocess.Popen(['sh', str(app / 'run.sh')], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if mode == 'signal':
            deadline = time.monotonic() + 4
            while not (tmp / 'ready').exists() and proc.poll() is None and time.monotonic() < deadline:
                time.sleep(.02)
            assert (tmp / 'ready').exists(), 'supervisor failed before starting Lua'
            proc.send_signal(signal.SIGTERM)
        stdout, stderr = proc.communicate(timeout=8)
        assert proc.returncode == {'fail': 7, 'signal': 143}.get(mode, 0), (mode, stdout, stderr)
        new_calls = (tmp / 'calls').read_text().splitlines()[before:]
        home_starts = sum('com.lab126.appmgrd start app://com.lab126.booklet.home' in call for call in new_calls)
        assert home_starts == {'normal': 2, 'handoff': 1, 'forward': 2, 'forward_rss': 2, 'forward_reader': 2, 'launch_fail': 3, 'fail': 2, 'signal': 1}[mode], (mode, new_calls)
        if mode in ['forward', 'forward_rss', 'forward_reader', 'launch_fail']:
            entered = new_calls.index('FORWARD_PAUSED_UI')
            assert not any(call == 'killall -CONT awesome' for call in new_calls[:entered])
            if mode == 'forward_rss': assert 'RSS_RESUMED' in new_calls
        assert (tmp / 'value').read_text() == '0', mode
        assert not (tmp / 'state').exists(), mode
        assert not (tmp / 'run-start').exists(), mode
        assert not (tmp / 'run-resume').exists() and not (tmp / 'run-return').exists(), mode
    (OUT / 'native-lifecycle.log').write_text((tmp / 'calls').read_text())
print('PASS: hide/show, keep-awake ownership, restoration and failed-service recovery')
print('PASS: real launcher consumes direct-home requests and restores native UI/auto-sleep on normal exit, Lua failure and TERM')
print('PASS: managed reader home exit skips native desktop restoration; home supervisor adopts ownership; normal/crash exits keep native recovery')

# Actual fast_render.lua and home.lua, replacing only device libraries/services.
harness = r'''
package.path=APP..'/?.lua;'..(os.getenv('MYDASH_KOREADER_COMMON') or '/mnt/us/koreader/common')..'/?.lua;'..package.path
local U=require('util');local J=U.json;U.root=APP
local writes,calls,saves={},{},{}
writes[U.root..'/next_action']=NEXT_ACTION
U.write=function(p,s)writes[p]=s;return true end
U.save=function(p,t)saves[p]=t;return true end
U.read=function(p)return writes[p] end
U.capture=function(cmd)if cmd:find('battLevel',1,true) then return '100' elseif cmd:find('df ',1,true) then return '1.4G' else return '12' end end
U.exec=function(cmd)calls[#calls+1]=cmd;return true end
os.execute=function()return 0 end
os.exit=function(code)error("unexpected exit "..tostring(code))end
os.remove=function()return true end
local getenv=os.getenv
os.getenv=function(name)if name=='MYDASH_RENDER_OFFSCREEN' then return '1' else return getenv(name) end end
local cfg={city={name='南京',latitude=32.06,longitude=118.79},feeds={{name='少数派',url='https://sspai.com/feed'}},refresh_minutes=30}
local watch={watchlist={{symbol='SGE_AU9999',name='国内黄金'},{symbol='XAU',name='国际黄金'},{symbol='XAG',name='国际白银'},{symbol='sh000001',name='上证指数'},{symbol='sh000300',name='沪深300'},{symbol='usIXIC',name='纳斯达克综合指数'}},interval=5}
local fixtures={['config.json']=cfg,['markets_config.json']=watch}
if not EMPTY then
 fixtures['weather.json']={city='南京',time=os.time(),data={current={temperature_2m=24,weather_code=0},daily={temperature_2m_min={18},temperature_2m_max={27}}}}
 fixtures['markets.json']={quotes={}}
 for i,item in ipairs(watch.watchlist)do fixtures['markets.json'].quotes[item.symbol]={price=i==2 and 123456.78 or 9876.54,percent=i==3 and -100 or 12.34,quote_at=os.time(),fetched_at=os.time(),quote_date=i==1 and '2026-10-19' or nil,unit=i>=4 and '点' or nil} end
 fixtures['hotspots.json']={items={{title='这是一条较长的中文热点标题用于检查大字显示和两行换行是否完整保留',source='虎嗅热文',rank=1,board='huxiu',content_kind='summary',link='https://example.com'},{title='第二来源的轮播资讯',source='澎湃热榜',rank=1,board='thepaper',content_kind='summary',link='https://example.com/second'}}}
else watch.watchlist={} end
U.config=function()return cfg end
U.load=function(p,default)return fixtures[p:match('([^/]+)$')] or default end
package.loaded.pinyin={lookup=function()return {} end,choose=function(s)return s end,commit=function(s)return s end}
package.loaded.article={id=function()return string.rep('a',24)end,feed_book=function()return nil end}
package.loaded.reading={last=function()if not EMPTY then return '/mnt/us/Books/测试 书.epub','测试 书' end end,valid=function(path)return path~=nil end}
local ffi={C={getpid=function()return 1 end,clock_gettime=function(_,t)t[0].tv_sec=1;t[0].tv_nsec=0 end,close=function()end,ioctl=function()return 0 end}}
ffi.cdef=function()end;ffi.new=function()return {[0]={}}end;ffi.sizeof=function()return 16 end
package.loaded.ffi=ffi;package.loaded.setupkoenv={}
local function block(w,h)
 local b={}
 b.getWidth=function()return w end;b.getHeight=function()return h end
 b.fill=function()end;b.paintRect=function()end;b.colorblitFrom=function()end
 b.viewport=function(_,_,_,vw,vh)return block(vw,vh)end
 b.free=function()end
 return b
end
package.loaded['ffi/blitbuffer']={new=function(w,h)return block(w,h)end,TYPE_BB8=1,COLOR_WHITE=255,COLOR_BLACK=0}
package.loaded['ffi/freetype']={newFaceSize=function(_,size)
 return {getHeightAndAscender=function()return math.ceil(size*1.5),math.ceil(size*1.2)end,
 renderGlyph=function(_,code)return {ax=math.ceil(size*(code<128 and .6 or 1)),l=0,t=size,bb=block(1,size)}end}
end}
local R=require('render');local frames={};local ops={};local settings;local rssButtons;local homeDraw,homeNews
local text,rect,begin,finish=R.text,R.rect,R.begin,R.finish
R.text=function(s,x,y,size,w,h,weight)ops[#ops+1]={kind='text',s=s,x=x,y=y,size=size,w=w,h=h,weight=weight};return text(s,x,y,size,w,h,weight)end
R.rect=function(x,y,w,h,black)ops[#ops+1]={kind='rect',x=x,y=y,w=w,h=h,black=black};return rect(x,y,w,h,black)end
R.begin=function(...)ops={};return begin(...)end
R.finish=function(full,region)
 finish(full,region)
 if R.page_title=='' then
  homeDraw=debug.getinfo(2,'f').func
  for i=1,100 do local name,value=debug.getupvalue(homeDraw,i);if not name then break end;if name=='rss' then homeNews=value end end
 end
 if full or #ops>0 then frames[#frames+1]={title=R.page_title,ops=ops} end
 if R.page_title=='设置' then settings=R.buttons end
 if R.page_title=='热点榜' then rssButtons=R.buttons end
end
-- Real renderer must draw/hit at y=0, and its first refresh must span all 1448 rows.
R.begin('',nil,true);assert(R.damage.y==0 and R.damage.b==1448)
R.hitbox(0,0,100,50,'top');assert(R.hit(10,10)=='top' and R.hit(10,80)==nil)
R.finish(true);assert(writes['/var/tmp/mydash-v2-perf.txt']:find('region=1072x1448',1,true))
frames={};arg={'--render-test'};dofile(APP..'/home.lua')
local nativeShows=0
for _,command in ipairs(calls)do if command:find("'show'",1,true) then nativeShows=nativeShows+1 end end
assert(nativeShows==(NEXT_ACTION=='bookstore' and 0 or 1),'managed reader handoff must retain paused UI; ordinary exits must restore it')
assert(#frames>=17)
for _,b in ipairs(R.buttons)do assert(b.y>=0 and b.y+b.h<=1448)end
for _,b in ipairs({{144,'bookstore'},{536,'browser'},{732,'todos'},{928,'settings'}})do assert(R.hit(b[1],1380)==b[2])end
assert(R.hit(209,1380)==nil,'Button gaps must not trigger adjacent actions')
if EMPTY then local resume=R.hit(340,1380);assert(type(resume)=='function');resume();assert(writes[U.root..'/next_action']=='bookstore','No reading history must open library directly') end
local directHome=false
for _,b in ipairs(rssButtons)do if b.action=='home' then directHome=true end end
assert(directHome,'RSS list must expose a direct-home control')
local controls={}
for _,b in ipairs(settings)do if b.y==605 then controls.awake=b.action elseif b.y==972 and b.x==550 then controls.sleep=b.action end end
assert(controls.awake and controls.sleep)
controls.awake();assert(cfg.keep_awake==false)
controls.awake();assert(cfg.keep_awake==true)
controls.sleep();assert(calls[#calls]:find('powerButton 1',1,true))
assert(calls[#calls-1]:find("'show'",1,true))
assert(calls[#calls-2]:find("'awake' '0'",1,true))
local f=assert(io.open(OUTPUT,'w'));f:write(J.encode(frames));f:close()
if not EMPTY then
 local N=require('news');assert(homeNews and homeDraw)
 assert(not N.advance(homeNews,1000));assert(N.advance(homeNews,1180));homeDraw()
 local found=false
 for _,op in ipairs(ops)do if op.kind=='text' and op.s=='第二来源的轮播资讯' then found=true end end
 assert(found,'Rotation must render the next title')
 local click=R.hit(100,1180);assert(type(click)=='function');click()
 local requested
 for path,value in pairs(saves)do if path:find('article-request.',1,true) then requested=value end end
 assert(requested and requested.link=='https://example.com/second','Media article click must fetch the currently displayed article')
 for i=1,100 do local key=debug.getupvalue(homeDraw,i);if key=='page' then debug.setupvalue(homeDraw,i,'home');break end end
 homeDraw();local resume=R.hit(340,1380);assert(type(resume)=='function');resume()
 assert(writes[U.root..'/reader_book']=='/mnt/us/Books/测试 书.epub' and writes[U.root..'/next_action']=='reader','Home quick reading must pass the exact local book path')
end
'''
for empty in [False, True]:
    filename = OUT / ('layout-empty.json' if empty else 'layout-populated.json')
    lua('APP=' + json.dumps(str(APP)) + ';OUTPUT=' + json.dumps(str(filename)) +
        ';EMPTY=' + ('true' if empty else 'false') + ';NEXT_ACTION=' + json.dumps('native' if empty else 'bookstore') + '\n' + harness)
    frames = json.loads(filename.read_text())
    home = frames[0]
    assert home['title'] == ''
    texts = [o for o in home['ops'] if o['kind'] == 'text' and str(o['s']).strip()]
    assert all(o['size'] >= 32 for o in texts), texts
    assert all(o.get('weight') != 'medium' for o in texts)
    assert not any(str(o['s']).startswith('可用 ') or o['s']=='首页常显' for o in texts)
    image = Image.new('RGB', (1072, 1448), 'white')
    draw = ImageDraw.Draw(image)
    for op in home['ops']:
        if op['kind'] == 'rect':
            draw.rectangle((op['x'], op['y'], op['x']+op['w']-1, op['y']+op['h']-1),fill='black' if op['black'] else 'white')
            continue
        if not str(op['s']).strip():continue
        x,y,size=op['x'],op['y'],op['size']
        assert x>=0 and y>=0 and x+op['w']<=1072 and y+op['h']<=1448,op
        font=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',size)
        ascent,descent=font.getmetrics();lineheight=ascent+descent
        pen=0;line=0
        for char in str(op['s']):
            width=draw.textlength(char,font=font)
            if char=='\n' or (pen and pen+width>op['w']):pen=0;line+=1
            if char=='\n':continue
            bbox=font.getbbox(char,anchor='ls')
            assert line*lineheight+ascent+bbox[3]<=op['h'],(op['s'],op['h'],line*lineheight+ascent+bbox[3])
            draw.text((x+pen,y+line*lineheight+ascent),char,font=font,fill='black',anchor='ls')
            pen+=width
    image.save(OUT/('home-empty.png' if empty else 'home-populated.png'))
print('PASS: real Lua pages, fullscreen damage/hit mapping, populated/empty home, font bounds, keep-awake and manual sleep controls')
