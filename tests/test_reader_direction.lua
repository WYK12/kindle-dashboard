-- Run with Lua/LuaJIT and dkjson on package.path; no live screen or settings writes.
local patch=assert(arg[1],'Pass 2-mydash-direction.lua')
local json=require('dkjson');local realOpen,realGetenv=io.open,os.getenv
for _,managed in ipairs({false,true})do for _,lock in ipairs({'unset',false,true})do
 for _,direction in ipairs({'missing','corrupt','default',false,true})do
  local raw=direction=='corrupt' and '{' or direction=='default' and '{}' or json.encode{dashboard_landscape=direction==true}
  io.open=function(path,mode)
   assert(path=='/mnt/us/mydash_v2/config.json' and mode=='r')
   if direction=='missing'then return nil end
   return {read=function()return raw end,close=function()end}
  end
  os.getenv=function(key)if key=='MYDASH_MANAGED_READER'then return managed and '1'or nil end;return realGetenv(key)end
  local settings={data={other=true,disabled=false,keyboard_key_compact=false}}
  if lock~='unset'then settings.data.lock_rotation=lock end
  function settings:isTrue(key)return self.data[key]==true end
  function settings:nilOrFalse(key)return self.data[key]==nil or self.data[key]==false end
  G_reader_settings=settings
  local before=json.encode(settings.data);local calls={}
  package.loaded.device={screen={DEVICE_ROTATED_UPRIGHT=0,DEVICE_ROTATED_COUNTER_CLOCKWISE=3,setRotationMode=function(_,mode)calls[#calls+1]=mode end}}
  dofile(patch)
  local applied=managed and direction~='missing' and direction~='corrupt'
  assert(#calls==(applied and 1 or 0))
  if applied then
   assert(calls[1]==(direction==true and 3 or 0))
   assert(settings:isTrue('lock_rotation')and not settings:nilOrFalse('lock_rotation'))
  else
   assert(settings:isTrue('lock_rotation')==(lock==true))
  end
  assert(settings:isTrue('other') and settings:nilOrFalse('disabled'))
  assert(settings:isTrue('keyboard_key_compact')==(applied and direction==true))
  assert(json.encode(settings.data)==before,'Applying direction must not alter saved settings')
 end
end end
io.open=realOpen;os.getenv=realGetenv
if os.getenv('MYDASH_TEST_NATIVE_ROTATION')=='1' then
 require('setupkoenv')
 local BB=require('ffi/blitbuffer');local FB=require('ffi/framebuffer')
 local buffer=BB.new(1072,1448,BB.TYPE_BB8)
 FB.setRotationMode({bb=buffer,native_rotation_mode=0,blitbuffer_rotation_mode=0},FB.DEVICE_ROTATED_COUNTER_CLOCKWISE)
 assert(buffer:getRotation()==1 and buffer:getWidth()==1448 and buffer:getHeight()==1072)
 local x,y=buffer:getPhysicalRect(0,0,1,1);assert(x==1071 and y==0,'Native top-left must match dashboard rotation1')
 buffer:free()
 print('PASS: real native framebuffer rotation matches dashboard physical direction')
end
print('PASS: managed portrait/landscape, sticky view queries, unmanaged isolation, missing/malformed config and unchanged saved preferences')
