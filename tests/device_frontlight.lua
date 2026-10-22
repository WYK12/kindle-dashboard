-- Real settings callbacks/fonts, with isolated power controls by default.
assert(os.getenv('MYDASH_RENDER_OFFSCREEN')=='1')
local U=require('util')
local cfg=U.config();cfg.dashboard_landscape=false;U.config=function()return cfg end
local read,execute,capture,osexecute=U.read,U.exec,U.capture,os.execute
local lightfile='/sys/class/backlight/max77696-bl/brightness'
local level,hardware=0,1
local fail,commands=nil,{}
-- Keep mocked reads effective when the dashboard uses a persistent LIPC handle.
package.loaded.liblipclua={init=function()return {
 get_int_property=function(_,service,prop)return tonumber(U.capture('lipc-get-prop '..service..' '..prop))end,
 get_string_property=function(_,service,prop)return U.capture('lipc-get-prop '..service..' '..prop)end,
 close=function()end,
}end}
U.write=function()return true end;U.save=function()return true end
os.execute=function()return 0 end;os.remove=function()return true end
U.read=function(path)if path==lightfile then return tostring(hardware)end;return read(path)end
U.capture=function(command)if command=='lipc-get-prop com.lab126.powerd flIntensity' then return tostring(level)end;return capture(command)end
U.exec=function(command)
 commands[#commands+1]=command
 local value=command:match('^lipc%-set%-prop com%.lab126%.powerd flIntensity (%d+)$')
 if value then
  if fail=='lipc' then return false end
  level=tonumber(value);hardware=level==0 and 1 or level*10;return true
 elseif command:find(lightfile,1,true) then
  if fail=='write' then return false end
  if fail~='readback' then hardware=0 end
 end
 return true
end
local R=require('render');local finish,text=R.finish,R.text
local draw,labels
R.text=function(s,...)labels=labels or {};labels[tostring(s)]=true;return text(s,...)end
R.finish=function(...)if not draw then draw=debug.getinfo(2,'f').func end;return finish(...)end
arg={'--render-test'};dofile(os.getenv('MYDASH_HOME_FILE') or '/mnt/us/mydash_v2/home.lua')
local found=false
for i=1,100 do local name=debug.getupvalue(draw,i);if not name then break end;if name=='page' then debug.setupvalue(draw,i,'settings');found=true;break end end
assert(found)
local function redraw()labels={};draw()end
local function tap(x)assert(type(R.hit(x,850))=='function');R.hit(x,850)();redraw()end
redraw();assert(labels['最低亮度'] and not labels['已关闭'])
tap(860);assert(level==0 and hardware==0 and labels['已关闭'] and labels['背光已关闭'])
assert(commands[#commands-1]=='lipc-set-prop com.lab126.powerd flIntensity 0' and commands[#commands]:find(lightfile,1,true))
tap(860);assert(hardware==0,'Repeated off must stay off')
tap(530);assert(level==2 and hardware>0 and labels['2 / 24'])
tap(180);assert(level==0 and hardware==0,'Decreasing to zero must also turn off the LEDs')
level=24;hardware=240;redraw();tap(530);assert(level==24,'Brightness must stay bounded')
for _,failure in ipairs({'lipc','write','readback'})do
 level=0;hardware=1;fail=failure;redraw();tap(860)
 assert(hardware==1 and labels['亮度设置失败，请重试'] and not labels['背光已关闭'])
end
fail=nil
for _,b in ipairs(R.buttons)do assert(b.x>=0 and b.y>=0 and b.x+b.w<=1072 and b.y+b.h<=1448)end
assert(R.hit(370,850)==nil and R.hit(704,850)==nil,'Light buttons must have independent hit zones')
print('PASS: stock-zero detection, actual-zero callback, repeat off, increase/decrease, bounds and command/readback failures')
if os.getenv('MYDASH_TEST_LIGHT_OFF')=='1' then
 os.execute=osexecute
 U.read=read;U.exec=execute;U.capture=capture
 redraw();tap(860)
 assert(tonumber(read(lightfile))==0 and tonumber(read('/sys/class/backlight/max77696-bl/actual_brightness'))==0)
 assert(labels['已关闭'] and labels['背光已关闭'])
 R.snapshot('/var/tmp/mydash-frontlight-off.png')
 print('PASS: real settings callback turns PW3 brightness and actual_brightness to zero')
end
