-- Follow the dashboard only in its managed reader process; leave saved locks alone.
if os.getenv('MYDASH_MANAGED_READER')~='1' then return end
local file=io.open('/mnt/us/mydash_v2/config.json','r')
if not file then return end
local source=file:read('*a');file:close()
local ok,cfg=pcall(require('dkjson').decode,source)
if not ok or type(cfg)~='table' then return end
local settings=G_reader_settings
local isTrue,nilOrFalse=settings.isTrue,settings.nilOrFalse
-- Native file manager and reader honor these sticky-rotation queries. Override
-- this instance's queries, rather than persisting a lock or per-book direction.
function settings:isTrue(key)
 if key=='lock_rotation' then return true end
 if key=='keyboard_key_compact' and cfg.dashboard_landscape==true then return true end
 return isTrue(self,key)
end
function settings:nilOrFalse(key)
 if key=='lock_rotation' then return false end
 return nilOrFalse(self,key)
end
local screen=require('device').screen
-- KOReader rotation modes are inverse to the dashboard's BlitBuffer rotation1.
screen:setRotationMode(cfg.dashboard_landscape==true and screen.DEVICE_ROTATED_COUNTER_CLOCKWISE or screen.DEVICE_ROTATED_UPRIGHT)
