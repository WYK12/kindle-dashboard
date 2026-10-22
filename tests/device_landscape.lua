-- Native layout, software rotation and raw touch mapping; no live UI/settings writes.
assert(os.getenv('MYDASH_RENDER_OFFSCREEN')=='1')
local U=require('util');local load=U.load
-- Old queued events are discarded; the next fresh gesture remains readable.
require('setupkoenv');require('ffi/posix_h');local ffi=require('ffi')
ffi.cdef[[int pipe(int[2]);]]
local pipe=ffi.new('int[2]');assert(ffi.C.pipe(pipe)==0)
assert(ffi.C.fcntl(pipe[0],ffi.C.F_SETFL,ffi.cast('int',ffi.C.O_NONBLOCK))==0)
assert(require('bit').band(ffi.C.fcntl(pipe[0],ffi.C.F_GETFL),ffi.C.O_NONBLOCK)~=0)
local event=ffi.new('char[16]');assert(ffi.C.write(pipe[1],string.rep('x',32),32)==32)
U.discard_input(pipe[0],event,16);assert(ffi.C.read(pipe[0],event,16)==-1)
assert(ffi.C.write(pipe[1],string.rep('y',16),16)==16 and ffi.C.read(pipe[0],event,16)==16 and event[0]==121)
ffi.C.close(pipe[0]);ffi.C.close(pipe[1])
local cfg=U.config();cfg.dashboard_landscape=true
cfg.feeds={};for i=1,12 do cfg.feeds[i]={name='测试订阅名称 '..i,url='https://example.com/news/long-address-for-layout'}end
local writes,saves={},{}
U.config=function()return cfg end
U.write=function(path,data)writes[path]=data;return true end
U.save=function(path,data)saves[path]=data;return true end
U.exec=function()return true end;os.execute=function()return 0 end;os.remove=function()return true end
local items={
 {title=string.rep('这是横屏下较长的热点标题',4),source='虎嗅热文',board='huxiu',rank=1,content_kind='summary',link='https://example.com/first'},
 {title='第二条短热点',source='澎湃热榜',board='thepaper',rank=2,content_kind='summary',link='https://example.com/second'},
}
local watch={watchlist={{symbol='SGE_AU9999',name='国内黄金'},{symbol='XAU',name='国际黄金'},{symbol='XAG',name='国际白银'},{symbol='sh000001',name='上证指数'},{symbol='sh000300',name='沪深300'},{symbol='usIXIC',name='纳斯达克综合'}},interval=5}
local quotes={};for i,item in ipairs(watch.watchlist)do quotes[item.symbol]={price=i==2 and 123456.78 or 9876.54,percent=i==3 and -100 or 12.34,quote_at=os.time(),fetched_at=os.time(),quote_date=i==1 and '2026-10-22' or nil,unit=i>=4 and '点' or nil}end
U.load=function(path,default)
 if path==U.root..'/markets_config.json' then return watch end
 if path==U.root..'/cache/hotspots.json' then return {items=items,time=os.time()}end
 if path==U.root..'/cache/markets.json' then return {quotes=quotes,time=os.time()}end
 return load(path,default)
end
local R=require('render');local finish,text=R.finish,R.text;local draw,main
local originalXpcall=xpcall;xpcall=function(fn,...)main=fn;return originalXpcall(fn,...)end
R.text=function(s,x,y,size,w,h,...)
 assert(x>=0 and y>=0 and x+w<=R.width and y+h<=R.height,'Text outside orientation bounds: '..tostring(s))
 return text(s,x,y,size,w,h,...)
end
R.finish=function(...)
 if not draw then draw=debug.getinfo(2,'f').func end
 for _,button in ipairs(R.buttons)do assert(button.x>=0 and button.y>=0 and button.x+button.w<=R.width and button.y+button.h<=R.height,'Touch target outside orientation bounds')end
 return finish(...)
end
local function state(key,value,set)
 for i=1,100 do local name,old=debug.getupvalue(draw,i);if not name then break end;if name==key then if set then debug.setupvalue(draw,i,value)end;return old end end
 error('Missing state '..key)
end
local function hit(x,y)return R.hit(1071-y,x)end
arg={'--render-test'};dofile(assert(os.getenv('MYDASH_HOME_FILE')));xpcall=originalXpcall
assert(R.landscape and R.width==1448 and R.height==1072)
assert(R.last_physical_area.width==1072 and R.last_physical_area.height==1448)
for _,button in ipairs(R.buttons)do assert(button.x>=0 and button.y>=0 and button.x+button.w<=1448 and button.y+button.h<=1072)end
assert(hit(120,1005)=='bookstore' and hit(1328,1005)=='settings')
assert(type(hit(100,50))=='function' and hit(800,220)=='weather' and hit(400,600)=='markets')
R.snapshot('/var/tmp/mydash-landscape-before.png')
-- Simulate the actual framebuffer's padded stride with the same rotated blit path.
local canvas
for i=1,20 do local key,value=debug.getupvalue(R.snapshot,i);if key=='buffer'then canvas=value;break end end
assert(canvas)
local BB=require('ffi/blitbuffer');local target=BB.new(1072,1448,BB.TYPE_BB8,nil,1088)
target:setRotation(1);target:blitFrom(canvas,0,0,0,0,1448,1072)
target:writePNG('/var/tmp/mydash-landscape-stride.png');target:free()
local rss=state('rss');local N=require('news');assert(not N.advance(rss,1000) and N.advance(rss,1180))
local count=#R.buttons;local handler=hit(1100,650)
R.drawHotspot(true);assert(#R.buttons==count and hit(1100,650)==handler)
local physical=R.last_physical_area
assert(physical.left==188 and physical.top==976 and physical.width==512 and physical.height==424)
assert(writes['/var/tmp/mydash-v2-perf.txt']:find('flash=false',1,true))
R.snapshot('/var/tmp/mydash-landscape-after.png')
-- All custom pages retain landscape, while settings can switch both directions.
hit(100,50)();draw();assert(R.landscape)
hit(1300,50)();draw();assert(R.landscape)
state('page','settings',true);draw();assert(R.landscape)
hit(1100,460)();draw();assert(cfg.dashboard_landscape==false and not R.landscape and saves[U.root..'/config.json'])
R.hit(800,1120)();draw();assert(cfg.dashboard_landscape==true and R.landscape)
hit(1300,50)();draw();assert(R.landscape)
handler=hit(1100,650);assert(type(handler)=='function');handler()
local requested;for path,value in pairs(saves)do if path:find('article-request.',1,true)then requested=value end end
assert(requested and requested.link==items[2].link,'Landscape headline tap must open the displayed article')
-- Full lists, pending/error states and six-row calendar in both orientations.
local tasks={};for i=1,14 do tasks[i]={text='横屏待办文字检查 '..i,done=i%2==0}end
local cities={};for i=1,6 do cities[i]={name='测试城市'..i,admin1='省份',country='中国',latitude=32,longitude=118}end
local stocks={};for i=1,12 do stocks[i]={symbol='sh'..tostring(600000+i),name='测试股票名称'..i}end
for i=7,12 do watch.watchlist[i]={symbol='sh'..tostring(600000+i),name='测试品种'..i}end
local news={};for i=1,12 do news[i]={title=string.rep('较长的热点标题',6),source='虎嗅热文',board='huxiu',rank=i,link='https://example.com/'..i}end
state('todos',tasks,true);state('cityresults',cities,true);state('stockresults',stocks,true);state('rss',{items=news,time=os.time(),home_index=1},true)
state('selected',{title='横屏热点详情标题'..string.rep('排版检查',5),body=string.rep('摘要文字，检查分栏可读性。',40),source='虎嗅',rank=1},true)
local pages={'home','calendar','weather','weatherdays','weatherhours','rss','hotdetail','preparearticle','todos','addtodo','settings','cities','cityresults','feeds','keyboard','markets','marketlist','marketadd','stockresults'}
local C=require('calendar');C.year=2026;C.month=8
for _,landscape in ipairs({true,false})do
 cfg.dashboard_landscape=landscape
 for _,page in ipairs(pages)do
  state('page',page,true);state('listpage',1,true);state('marketpage',1,true);state('stockresultpage',1,true)
  draw();assert(R.landscape==landscape,page..' orientation')
  if landscape then R.snapshot('/var/tmp/mydash-wide-'..page..'.png')end
  if page~='home' then
   local back=landscape and hit(1300,50) or R.hit(920,50)
   assert(type(back)=='function',page..' missing back');back();draw();assert(R.landscape==landscape,page..' back orientation')
  end
 end
end
cfg.dashboard_landscape=true
-- Same-size pagination preserves saved hotlist pages and market move callbacks.
for _,page in ipairs({'rss','markets','marketlist','todos','stockresults'})do
 state('page',page,true);state('listpage',1,true);state('marketpage',1,true);state('stockresultpage',1,true);draw()
 local next=hit(450,page=='marketlist' and 860 or page=='todos' and 940 or page=='stockresults' and 950 or 960)
 -- First/second footer columns share a 392px start except stock search results (508px).
 if page=='stockresults'then next=hit(600,950)end
 assert(type(next)=='function',page..' next');next();draw()
 local key=page=='markets'and 'marketpage'or page=='stockresults'and 'stockresultpage'or 'listpage'
 assert(state(key)==2,page..' second page')
end
state('page','marketlist',true);state('listpage',1,true);draw()
local first=watch.watchlist[1];hit(1120,200)();assert(watch.watchlist[2]==first);draw();R.snapshot('/var/tmp/mydash-wide-marketlist.png')
-- Exercise the actual partial keyboard path with native fonts and hit handlers.
local drawInput
for i=1,100 do local key,fn=debug.getupvalue(main,i);if not key then break end;if key=='drawInput'then drawInput=fn;break end end
assert(drawInput)
state('page','keyboard',true);state('inputkind','market',true);state('draft','nan',true);state('keyboardPinyin',true,true);draw()
R.snapshot('/var/tmp/mydash-wide-keyboard.png')
local buttons=#R.buttons;local before=state('draft');hit(70,480)();drawInput()
assert(state('draft')==before..'1'and #R.buttons==buttons)
assert(writes['/var/tmp/mydash-v2-perf.txt']:find('flash=false',1,true)and writes['/var/tmp/mydash-v2-perf.txt']:find('region=1352x280',1,true))
hit(80,950)();drawInput();assert(#R.buttons==buttons)
R.snapshot('/var/tmp/mydash-wide-keyboard-partial.png')
state('page','preparearticle',true);state('articleError','测试网络超时，请重试',true);draw();assert(type(hit(600,720))=='function');R.snapshot('/var/tmp/mydash-wide-article-error.png')
state('stockerror','测试搜索错误',true);state('stockresults',{},true);state('page','stockresults',true);draw()
-- Empty/offline states remain usable in either orientation.
state('marketcfg',{watchlist={},interval=5},true);state('rss',{items={}},true);state('weather',{},true);state('todos',{},true);state('cityresults',{},true);cfg.feeds={}
for _,landscape in ipairs({true,false})do
 cfg.dashboard_landscape=landscape
 for _,page in ipairs(pages)do state('page',page,true);draw()end
end
-- A short text box must not expose a clipped second line (36px font, 38px line).
R.setLandscape(true);R.partial();R.rect(48,200,500,75,false);R.text(string.rep('字号',20),48,200,36,500,75)
for y=238,274 do for x=48,547 do assert(canvas:getPixel(x,y):getColor8().a==255,'Clipped last line must remain blank')end end
cfg.dashboard_landscape=true;state('page','home',true);draw();assert(hit(120,1005)=='bookstore' and hit(1100,650)=='rss')
R.snapshot('/var/tmp/mydash-landscape-empty.png')
print('PASS: native populated/empty pages in both orientations, all text/touch bounds, saved direction, page returns, six-row calendar, pagination, self-selected order, current article, padded stride, whole text lines and partial keyboard/hotspots')
