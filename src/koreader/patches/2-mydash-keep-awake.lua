-- Match the homepage's owned powerd hold without resetting Kindle's t1 timer.
if os.getenv('MYDASH_MANAGED_READER')~='1' then return end
local hold=io.open((os.getenv('MYDASH_NATIVE_STATE') or '/tmp/mydash-v2-native')..'/screensaver','r')
if not hold then return end
hold:close()
local share=require('pluginshare')
share.keepalive=true
share.pause_auto_suspend=true
