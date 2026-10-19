-- Gate only the stock X server's touch device; raw evdev readers keep working.
local mode,state=arg[1],assert(arg[2],'Missing native touch state path')
assert(mode=='disable' or mode=='restore' or mode=='status','Invalid touch operation')
local original
local saved=io.open(state,'r')
if saved then original=tonumber(saved:read('*a'));saved:close();assert(original==0 or original==1,'Invalid native touch state') end
if mode=='restore' and original==nil then return end
local ffi=require('ffi')
ffi.cdef[[
typedef struct {int deviceid;char *name;int use;int attachment;int enabled;int num_classes;void **classes;} MyDashXIDeviceInfo;
void *XOpenDisplay(const char *);
int XCloseDisplay(void *);
unsigned long XInternAtom(void *,const char *,int);
int XSync(void *,int);
int XIQueryVersion(void *,int *,int *);
MyDashXIDeviceInfo *XIQueryDevice(void *,int,int *);
void XIFreeDeviceInfo(MyDashXIDeviceInfo *);
void XIChangeProperty(void *,int,unsigned long,unsigned long,int,int,const unsigned char *,int);
]]
local x,xi=ffi.load('X11'),ffi.load('Xi')
local display=x.XOpenDisplay(':0');assert(display~=nil,'Cannot reach native display server')
local major,minor=ffi.new('int[1]',2),ffi.new('int[1]',0)
assert(xi.XIQueryVersion(display,major,minor)==0,'XInput 2 unavailable')
local count=ffi.new('int[1]')
local devices=xi.XIQueryDevice(display,0,count);assert(devices~=nil and count[0]>0,'Cannot list native input devices')
local id,enabled
for i=0,count[0]-1 do
 if ffi.string(devices[i].name)=='multitouch' then id=devices[i].deviceid;enabled=devices[i].enabled;break end
end
xi.XIFreeDeviceInfo(devices)
assert(id,'Native multitouch device missing')
if mode=='status' then print('NATIVE_TOUCH',enabled,'SAVED',original);x.XCloseDisplay(display);return end
if mode=='disable' and original==nil then
 local f=assert(io.open(state,'w'));assert(f:write(tostring(enabled)));assert(f:close())
end
local target=mode=='disable' and 0 or original
if enabled~=target then
 local atom=x.XInternAtom(display,'Device Enabled',1);assert(atom~=0,'Native device property missing')
 xi.XIChangeProperty(display,id,atom,19,8,0,ffi.new('unsigned char[1]',target),1)
 x.XSync(display,0)
end
devices=xi.XIQueryDevice(display,id,count);assert(devices~=nil and count[0]==1,'Cannot verify native touch state')
local actual=devices[0].enabled
xi.XIFreeDeviceInfo(devices);x.XCloseDisplay(display)
assert(actual==target,'Native touch state did not change')
if mode=='restore' then assert(os.remove(state)) end
