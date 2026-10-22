-- Use native fonts/blitbuffers without drawing to the live screen or launching jobs.
assert(os.getenv('MYDASH_RENDER_OFFSCREEN')=='1')
local U=require('util');local load=U.load
local cfg=U.config();cfg.dashboard_landscape=false;U.config=function()return cfg end
local writes,saves={},{ }
local items={
 {title=string.rep('用于检查两行热点文字清除的较长标题',4),source='虎嗅热文',board='huxiu',rank=1,content_kind='summary',link='https://example.com/first'},
 {title='第二条短热点',source='澎湃热榜',board='thepaper',rank=2,content_kind='summary',link='https://example.com/second'},
}
U.load=function(path,default)
 if path==U.root..'/cache/hotspots.json' then return {items=items,time=os.time()} end
 return load(path,default)
end
U.write=function(path,data)writes[path]=data;return true end
U.save=function(path,data)saves[path]=data;return true end
U.exec=function()return true end;os.execute=function()return 0 end;os.remove=function()return true end
local function up(fn,key)
 for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==key then return value end end
 error('Missing upvalue '..key)
end
local R=require('render');local finish=R.finish;local draw
R.finish=function(...)if not draw then draw=debug.getinfo(2,'f').func end;return finish(...)end
arg={'--render-test'};dofile(os.getenv('MYDASH_HOME_FILE') or '/mnt/us/mydash_v2/home.lua')
local rss=up(draw,'rss');local hotDraw=R.drawHotspot;local N=require('news')
R.snapshot('/var/tmp/mydash-partial-before.png')
local handler=R.hit(100,1180);local buttons=#R.buttons;local library=R.hit(120,1380)
assert(not N.advance(rss,1000) and N.advance(rss,1180))
R.last_flash=-100000;hotDraw(true)
local perf=assert(writes['/var/tmp/mydash-v2-perf.txt'])
assert(perf:find('flash=false',1,true) and perf:find('region=976x186',1,true))
assert(#R.buttons==buttons and R.hit(100,1180)==handler and R.hit(120,1380)==library)
R.snapshot('/var/tmp/mydash-partial-after.png')
handler()
local requested
for path,data in pairs(saves)do if path:find('article-request.',1,true) then requested=data end end
assert(requested and requested.link==items[2].link,'The existing hit handler must open the new headline')
print('PASS: native partial hotspot region, no elapsed-time flash, stable hit zones and correct current-article click')
