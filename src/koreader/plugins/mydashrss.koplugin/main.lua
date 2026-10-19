-- MYDASH_RSS_OWNED_PLUGIN
local WidgetContainer=require('ui/widget/container/widgetcontainer')
local Event=require('ui/event')
local UIManager=require('ui/uimanager')
local Device=require('device')
local Font=require('ui/font')
local TextWidget=require('ui/widget/textwidget')
local IconWidget=require('ui/widget/iconwidget')
local BB=require('ffi/blitbuffer')
local MyDashRSS=WidgetContainer:extend{name='mydashrss',is_doc_only=true}
function MyDashRSS:init()
 self.ui.menu:registerToMainMenu(self)
 self.ui:registerPostInitCallback(function()self:initializeLayout();self:installHomeButton()end)
end
function MyDashRSS:isRSSArticle()
 local file=self.ui.document and self.ui.document.file or ''
 return file:match('^/mnt/us/RSS/%x+%.epub$')
end
function MyDashRSS:initializeLayout()
 local settings=self.ui.doc_settings
 if not self:isRSSArticle() then return end
 -- Keep the home control below the native clock and above article text.
 local c=self.ui.document.configurable
 c.sync_t_b_page_margins=0;self.ui.typeset.sync_t_b_page_margins=false
 if (c.t_page_margin or 0)<90 then
  c.t_page_margin=90;self.ui:handleEvent(Event:new('SetPageTopMargin',c.t_page_margin))
 end
 if not settings:readSetting('mydash_layout_initialized') then
  c.h_page_margins={math.max(24,c.h_page_margins[1]),math.max(24,c.h_page_margins[2])}
  self.ui:handleEvent(Event:new('SetPageHorizMargins',c.h_page_margins))
 end
 settings:saveSetting('mydash_layout_initialized',true)
end
function MyDashRSS:onReaderReady()self:initializeLayout()end
function MyDashRSS:returnHome(destination)
 local f=io.open('/tmp/mydash-v2-return','w')
 if not f then
  UIManager:show(require('ui/widget/infomessage'):new{text='暂时无法返回，请重试'})
  return true
 end
 f:write(destination=='rss' and 'rss' or 'home');f:close()
 self.ui.menu:exitOrRestart(function()UIManager:quit()end)
 return true
end
function MyDashRSS:installHomeButton()
 if not self:isRSSArticle() then return end
 local screen=Device.screen
 self.home_rect={x=screen:scaleBySize(22),y=screen:scaleBySize(28),w=screen:scaleBySize(116),h=screen:scaleBySize(42)}
 self.home_label=self.home_label or TextWidget:new{text='‹ 热点',face=Font:getFace('cfont',22),bold=true}
 self.direct_home_rect={x=screen:getWidth()-screen:scaleBySize(70),y=screen:scaleBySize(26),w=screen:scaleBySize(42),h=screen:scaleBySize(42)}
 if self.home_icon then self.home_icon:free() end
 self.home_icon=IconWidget:new{icon='home',width=self.direct_home_rect.w,height=self.direct_home_rect.h}
 self.ui.view:registerViewModule('mydash_rss_home',self)
 local r={x=0,y=0,w=screen:scaleBySize(180),h=screen:scaleBySize(90)}
 local overrides={'readermenu_tap','readermenu_ext_tap','readerconfigmenu_tap','readerconfigmenu_ext_tap','tap_forward','tap_backward','tap_link','readerhighlight_tap','readerhighlight_tap_select_mode','tap_top_left_corner','tap_top_right_corner'}
 self.ui:registerTouchZones({{id='mydash_rss_home',ges='tap',
  screen_zone={ratio_x=r.x/screen:getWidth(),ratio_y=r.y/screen:getHeight(),ratio_w=r.w/screen:getWidth(),ratio_h=r.h/screen:getHeight()},
  overrides=overrides,
  handler=function()return self:returnHome('rss')end,
 },{id='mydash_rss_direct_home',ges='tap',
  screen_zone={ratio_x=1-screen:scaleBySize(112)/screen:getWidth(),ratio_y=0,ratio_w=screen:scaleBySize(112)/screen:getWidth(),ratio_h=r.h/screen:getHeight()},
  overrides=overrides,handler=function()return self:returnHome()end,
 }})
end
function MyDashRSS:paintTo(bb,x,y)
 if not self.home_label or not self:isRSSArticle() then return end
 local r=self.home_rect;local size=self.home_label:getSize()
 bb:paintRect(x+r.x,y+r.y,r.w,r.h,BB.COLOR_WHITE)
 self.home_label:paintTo(bb,x+r.x,y+r.y+math.floor((r.h-size.h)/2))
 r=self.direct_home_rect
 bb:paintRect(x+r.x,y+r.y,r.w,r.h,BB.COLOR_WHITE)
 self.home_icon:paintTo(bb,x+r.x,y+r.y)
end
function MyDashRSS:onScreenResize()self:installHomeButton()end
function MyDashRSS:onCloseDocument()
 if self.home_icon then self.home_icon:free();self.home_icon=nil end
 if self.home_label then self.home_label:free();self.home_label=nil end
 self.ui.view.view_modules.mydash_rss_home=nil
end
function MyDashRSS:addToMainMenu(menu_items)
 if not self:isRSSArticle() then return end
 menu_items.mydash_rss_return={text='返回热点榜',sorting_hint='exit_menu',callback=function()
  self:returnHome('rss')
 end}
 menu_items.mydash_rss_home={text='返回自定义首页',sorting_hint='exit_menu',callback=function()self:returnHome()end}
end
return MyDashRSS
