-- Exercise real cache/render decisions, without touching live input, network or settings.
assert(os.getenv('MYDASH_RENDER_OFFSCREEN')=='1')
local U=require('util');local load,read=U.load,U.read
local function clone(v)return U.json.decode(U.json.encode(v))end
local cache={};for _,name in ipairs({'weather','hotspots','markets','status'})do cache[name..'.json']=clone(load(U.root..'/cache/'..name..'.json',{}))end
cache['status.json'].errors={};cache['refresh-state.json']={}
local busy=false;local commands={}
U.write=function()return true end;U.save=function()return true end
U.exec=function()return true end;os.execute=function(command)commands[#commands+1]=command;return 0 end;os.remove=function()return true end
U.load=function(path,default)local name=path:match('/cache/([^/]+)$');if name and cache[name]then return clone(cache[name])end;return load(path,default)end
U.read=function(path)
 if path=='/tmp/mydash-v2-refresh/pid' then return busy and '123' or nil end
 local name=path:match('/cache/([^/]+)$');if name and cache[name]then return U.json.encode(cache[name])end
 return read(path)
end
local function up(fn,key,value,set)
 for i=1,100 do local k,v=debug.getupvalue(fn,i);if not k then break end;if k==key then if set then debug.setupvalue(fn,i,value)end;return v end end
 error('Missing upvalue '..key)
end
local R=require('render');local finish=R.finish;local draw,main
R.finish=function(...)
 if not draw then draw=debug.getinfo(2,'f').func;main=debug.getinfo(3,'f').func end
 return finish(...)
end
arg={'--render-test'};dofile(assert(os.getenv('MYDASH_HOME_FILE')))
local check=up(main,'checkcache');local network=up(main,'network')
local function reset()up(draw,'redraw',false,true)end
local function dirty()return up(draw,'redraw')end
local function tick()
 cache['status.json'].time=(cache['status.json'].time or 0)+1
 check(os.time())
end
reset()
cache['weather.json'].time=(cache['weather.json'].time or 0)+1
cache['hotspots.json'].time=(cache['hotspots.json'].time or 0)+1
cache['markets.json'].time=(cache['markets.json'].time or 0)+1
for _,q in pairs(cache['markets.json'].quotes or {})do q.fetched_at=(q.fetched_at or 0)+1 end
tick();assert(not dirty(),'Fetch timestamps alone must not repaint the home')
local symbol,q=next(cache['markets.json'].quotes);assert(symbol and q,'Needs a real cached quote')
q.price=q.price+1;tick();assert(dirty(),'Changed quotes must repaint')
draw();reset()
busy=true;q.price=q.price+1;tick();assert(not dirty(),'Do not paint partial batches')
busy=false;check(os.time());assert(dirty(),'Finished batch must publish its changes')
draw();reset()
up(draw,'page','settings',true);q.price=q.price+1;tick();assert(not dirty(),'Quotes must not repaint unrelated settings')
up(draw,'page','home',true);draw();reset()
cache['hotspots.json'].items[1].title=cache['hotspots.json'].items[1].title..' 测试';tick();assert(dirty())
draw();reset()
cache['weather.json'].data.current.temperature_2m=cache['weather.json'].data.current.temperature_2m+1;tick();assert(dirty())
draw();reset()
cache['status.json'].errors={'网络暂不可用'};tick();assert(dirty())
draw();reset();tick();assert(not dirty(),'Repeated same errors must not repaint')
cache['status.json'].errors={};tick();assert(dirty(),'Recovery must clear the visible error')
draw();reset();network('weather');draw();reset();tick()
assert(dirty() and commands[#commands]:find('/refresh.sh',1,true),'Manual updates remain immediate and report completion')
print('PASS: metadata-only suppression, real quote/weather/hotspot changes, batch completion, page isolation, repeated errors and manual completion')
