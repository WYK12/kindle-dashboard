-- Native font/render checks; power queries are isolated and never change settings.
assert(os.getenv('MYDASH_RENDER_OFFSCREEN')=='1')
local U=require('util');local capture=U.capture
U.write=function()return true end;U.save=function()return true end
U.exec=function()return true end;os.execute=function()return 0 end;os.remove=function()return true end
local opened,closed,reads,fallback=0,0,0,0
U.capture=function(command)
 if command=='lipc-get-prop com.lab126.powerd missing' then fallback=fallback+1;return 'fallback' end
 assert(not command:find('lipc-get-prop com.lab126.powerd',1,true),'Power reads must not spawn commands: '..command)
 return capture(command)
end
package.loaded.liblipclua={init=function(name)
 opened=opened+1;assert(name=='com.wyk12.mydash.power')
 return {
 get_string_property=function(_,service,prop)assert(service=='com.lab126.powerd' and prop=='state');reads=reads+1;return 'active'end,
 get_int_property=function(_,service,prop)
  assert(service=='com.lab126.powerd');reads=reads+1
  if prop=='battLevel' then return 94 elseif prop=='flIntensity' then return 0 end
  error('Unavailable property')
 end,
 close=function()closed=closed+1 end,
 }
end}
local function up(fn,name)
 for i=1,100 do local k,v=debug.getupvalue(fn,i);if not k then break end;if k==name then return v end end
 error('Missing upvalue '..name)
end
local R=require('render');local finish=R.finish;local checked=false
R.finish=function(...)
 if not checked then
  checked=true
  local draw=debug.getinfo(2,'f').func
  local lipc=up(up(draw,'battery'),'lipc')
  assert(lipc('state')=='active' and lipc('battLevel')=='94' and lipc('flIntensity')=='0')
  assert(lipc('missing')=='fallback' and fallback==1)
 end
 return finish(...)
end
arg={'--render-test'};dofile(os.getenv('MYDASH_HOME_FILE') or '/mnt/us/mydash_v2/home.lua')
assert(checked and opened==1 and closed==1 and reads>=4 and fallback==1)
print('PASS: one persistent LIPC connection, typed state/integer reads, zero value, command fallback and clean close')
