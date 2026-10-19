-- Run with the installed AutoSuspend implementation, without real power calls.
local getenv,open=os.getenv,io.open
local managed,held,share=false,false,{}
os.getenv=function(key)if key=='MYDASH_MANAGED_READER' then return managed and '1' or nil end;return getenv(key)end
io.open=function(path,mode)
 if path=='/tmp/mydash-v2-native/screensaver' then return held and {close=function()end} or nil end
 return open(path,mode)
end
package.loaded.pluginshare=share
local patch=assert(arg[1])
local function apply(m,h)
 managed,held=m,h;share.keepalive=nil;share.pause_auto_suspend=nil;dofile(patch)
 assert((share.keepalive==true)==(m and h))
 assert((share.pause_auto_suspend==true)==(m and h))
end
apply(false,true);apply(true,false);apply(true,true)
local resets,suspends,scheduled=0,0,0
local power={isCharging=function()return false end,resetT1Timeout=function()resets=resets+1 end}
package.loaded.device={canSuspend=function()return true end,isKindle=function()return true end,
 getPowerDevice=function()return power end,hasAuxBattery=function()return false end,canPowerOff=function()return false end}
package.loaded.optmath={};package.loaded['ui/network/manager']={}
package.loaded['ui/uimanager']={getElapsedTimeSinceBoot=function()return 100000 end,
 suspend=function()suspends=suspends+1 end,scheduleIn=function(_,delay)assert(delay==900);scheduled=scheduled+1 end}
package.loaded['ui/widget/container/widgetcontainer']={extend=function(_,o)return o end}
package.loaded.datetime={};package.loaded.logger={dbg=function()end}
package.loaded['ui/time']={to_number=function(n)return n end}
package.loaded.gettext=function(s)return s end;package.loaded['ffi/util']={template=function(s)return s end}
local autosuspend=dofile('/mnt/us/koreader/plugins/autosuspend.koplugin/main.lua')
autosuspend.last_action_time=0;autosuspend.last_t1_reset_time=0
autosuspend:_schedule();autosuspend:_schedule_kindle()
assert(suspends==0 and resets==0 and scheduled==1,'Owned keep-awake must defer idle suspend and skip t1 reset')
apply(true,false);autosuspend:_schedule();assert(suspends==1,'Without a hold normal idle suspend must remain available')
os.getenv,io.open=getenv,open
print('READER_KEEP_AWAKE_OK managed/unmanaged, held/released, elapsed idle timeout')
