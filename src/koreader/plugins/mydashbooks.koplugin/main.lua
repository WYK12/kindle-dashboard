-- MYDASH_BOOKS_OWNED_PLUGIN
local WidgetContainer=require('ui/widget/container/widgetcontainer')
local UIManager=require('ui/uimanager')
local Menu=require('ui/widget/menu')
local TitleBar=require('ui/widget/titlebar')
local InputDialog=require('ui/widget/inputdialog')
local InfoMessage=require('ui/widget/infomessage')
local NetworkMgr=require('ui/network/manager')
local Trapper=require('ui/trapper')
local Event=require('ui/event')
local Device=require('device')
local Font=require('ui/font')
local TextWidget=require('ui/widget/textwidget')
local IconWidget=require('ui/widget/iconwidget')
local BB=require('ffi/blitbuffer')
local lfs=require('libs/libkoreader-lfs')
local B=require('booktransfer')
local S=require('booksearch')
local sequence=0
local Books=WidgetContainer:extend{name='mydashbooks'}
function Books:init()
 self.ui.menu:registerToMainMenu(self)
 self.ui:registerPostInitCallback(function()
  if self.ui.document then
   self:initializeReadingLayout();self:installLibraryButton()
  elseif os.getenv('MYDASH_BOOKSTORE')=='1' then
   UIManager:nextTick(function()self:showHub()end)
  end
 end)
end
function Books:addToMainMenu(items)
 if self:isLibraryBook() then items.mydash_books_back={text='返回书库',sorting_hint='exit_menu',callback=function()self:returnToLibrary()end} end
 if not self.ui.document then items.mydash_books={text='书库',callback=function()self:showHub()end} end
 if os.getenv('MYDASH_BOOKSTORE')=='1' then items.mydash_books_return={text='返回自定义首页',sorting_hint='exit_menu',callback=function()self:returnHome()end} end
end
function Books:isLibraryBook()
 local file=self.ui.document and self.ui.document.file or ''
 return file:sub(1,#B.directory+1)==B.directory..'/'
end
function Books:initializeReadingLayout()
 if not self:isLibraryBook() then return end
 local c=self.ui.document.configurable
 if c and c.t_page_margin and self.ui.typeset then
  c.sync_t_b_page_margins=0;self.ui.typeset.sync_t_b_page_margins=false
  if c.t_page_margin<90 then
   c.t_page_margin=90;self.ui:handleEvent(Event:new('SetPageTopMargin',90))
  end
 end
end
function Books:returnToLibrary()
 self.ui:handleEvent(Event:new('CloseReaderMenu'))
 self:showHub()
 return true
end
function Books:installLibraryButton()
 -- PDFs use the menu action: overlaying a control would cover their fixed page.
 local c=self.ui.document and self.ui.document.configurable
 if not self:isLibraryBook() or not c or not c.t_page_margin or not self.ui.typeset then return end
 local screen=Device.screen
 self.library_rect={x=screen:scaleBySize(22),y=screen:scaleBySize(28),w=screen:scaleBySize(116),h=screen:scaleBySize(42)}
 self.library_label=self.library_label or TextWidget:new{text='‹ 书库',face=Font:getFace('cfont',22),bold=true}
 self.direct_home_rect={x=screen:getWidth()-screen:scaleBySize(70),y=screen:scaleBySize(26),w=screen:scaleBySize(42),h=screen:scaleBySize(42)}
 if self.home_icon then self.home_icon:free() end
 self.home_icon=IconWidget:new{icon='home',width=self.direct_home_rect.w,height=self.direct_home_rect.h}
 self.ui.view:registerViewModule('mydash_book_library',self)
 local r={x=0,y=0,w=screen:scaleBySize(180),h=screen:scaleBySize(90)}
 local overrides={'readermenu_tap','readermenu_ext_tap','readerconfigmenu_tap','readerconfigmenu_ext_tap','tap_forward','tap_backward','tap_link','readerhighlight_tap','readerhighlight_tap_select_mode','tap_top_left_corner','tap_top_right_corner'}
 self.ui:registerTouchZones({{id='mydash_book_library',ges='tap',
  screen_zone={ratio_x=r.x/screen:getWidth(),ratio_y=r.y/screen:getHeight(),ratio_w=r.w/screen:getWidth(),ratio_h=r.h/screen:getHeight()},
  overrides=overrides,
  handler=function()return self:returnToLibrary()end,
 },{id='mydash_book_direct_home',ges='tap',
  screen_zone={ratio_x=1-screen:scaleBySize(112)/screen:getWidth(),ratio_y=0,ratio_w=screen:scaleBySize(112)/screen:getWidth(),ratio_h=r.h/screen:getHeight()},
  overrides=overrides,handler=function()self:returnHome();return true end,
 }})
end
function Books:paintTo(bb,x,y)
 if not self.library_label or not self:isLibraryBook() then return end
 local r=self.library_rect;local size=self.library_label:getSize()
 bb:paintRect(x+r.x,y+r.y,r.w,r.h,BB.COLOR_WHITE)
 self.library_label:paintTo(bb,x+r.x,y+r.y+math.floor((r.h-size.h)/2))
 r=self.direct_home_rect
 bb:paintRect(x+r.x,y+r.y,r.w,r.h,BB.COLOR_WHITE)
 self.home_icon:paintTo(bb,x+r.x,y+r.y)
end
function Books:onReaderReady()self:initializeReadingLayout();self:installLibraryButton()end
function Books:onScreenResize()self:installLibraryButton()end
function Books:onCloseDocument()
 if self.home_icon then self.home_icon:free();self.home_icon=nil end
 if self.library_label then self.library_label:free();self.library_label=nil end
 if self.ui.view then self.ui.view.view_modules.mydash_book_library=nil end
end
function Books:returnHome()
 local f=io.open('/tmp/mydash-v2-return','w')
 if not f then UIManager:show(InfoMessage:new{text='暂时无法返回首页，请重试'});return end
 f:write('home');f:close()
 self:closeMenu()
 -- Native exit saves the document on the next UI tick; quit only afterwards.
 self.ui.menu:exitOrRestart(function()UIManager:quit()end)
end
function Books:closeMenu()
 if self.book_menu then UIManager:close(self.book_menu);self.book_menu=nil end
end
function Books:onCloseWidget()self:closeMenu()end
function Books:menu(title,items,onback)
 self:closeMenu()
 self.book_menu=Menu:new{title=title,item_table=items,covers_fullscreen=true,is_popout=false,is_borderless=true,
  custom_title_bar=TitleBar:new{title=title,fullscreen=true,left_icon='home',left_icon_size_ratio=1,
   left_icon_allow_flash=false,left_icon_tap_callback=function()self:returnHome()end,
   close_callback=function()self.book_menu:onClose()end},
  title_bar_left_icon='home',onLeftButtonTap=function()self:returnHome()end,
  onCloseAllMenus=function()
   if onback then onback() else self:showHub() end
   return true
  end}
 self.book_menu.title_bar.left_icon_allow_flash=false
 local home=self.book_menu.title_bar.left_button
 home.padding_bottom=math.max(0,self.book_menu.title_bar:getHeight()-home.height-home.padding_top)
 home:update();home.allow_flash=false
 UIManager:show(self.book_menu)
end
function Books:showHub()
 self:menu('书库',{
  {text='搜书',callback=function()self:searchBooks()end},
  {text='我的书',callback=function()self:showShelf()end},
 },function()self:returnHome()end)
end
function Books:openFile(path)
 self:closeMenu()
 if self.ui.document and self.ui.document.file==path then return end
 if self.ui.document then self.ui:switchDocument(path) else self.ui:openFile(path) end
end
function Books:runTask(work,message)
 local progress=InfoMessage:new{text=message..'\n点击可取消',alignment='center',show_icon=false,face=Font:getFace('infofont',22)}
 UIManager:show(progress);UIManager:forceRePaint()
 local completed,result=Trapper:dismissableRunInSubprocess(work,progress)
 UIManager:close(progress);UIManager:forceRePaint()
 return completed,result
end
function Books:download(url,title)
 local path=B.lookup(url);if path then self:openFile(path);return end
 NetworkMgr:runWhenConnected(function()
  sequence=sequence+1
  local part=B.directory..'/.download-'..os.time()..'-'..sequence..'.part'
  Trapper:wrap(function()
   local completed,result=self:runTask(function()return B.fetch(url,title,part)end,'正在下载《'..title..'》…')
   B.cleanup(part)
   if not completed then return end
   if result and result.path then self:openFile(result.path)
   else UIManager:show(InfoMessage:new{text=result and result.error or '下载失败，请重试'}) end
  end)
 end)
end
function Books:inputLink()
 local dialog
 dialog=InputDialog:new{title='下载书籍',input='',input_hint='https://…/book.epub',description='EPUB / PDF / MOBI，单本最多 32 MB',buttons={{{text='取消',id='close',callback=function()UIManager:close(dialog)end},{text='首页',callback=function()UIManager:close(dialog);self:returnHome()end},{text='下载并阅读',is_enter_default=true,callback=function()
  local url=dialog:getInputText():gsub('^%s+',''):gsub('%s+$','')
  if not B.validurl(url) then UIManager:show(InfoMessage:new{text='请输入完整的 http 或 https 下载链接'});return end
  UIManager:close(dialog);self:download(url,'下载书籍')
 end}}}}
 UIManager:show(dialog);dialog:onShowKeyboard()
end
function Books:shelfItems(query)
 local items={}
 local needle=query and query:gsub('%s+',''):lower()
 if lfs.attributes(B.directory,'mode')=='directory' then
  for name in lfs.dir(B.directory) do
   if name:match('%.epub$') or name:match('%.pdf$') or name:match('%.mobi$') then
    local path=B.directory..'/'..name
    local title=name:gsub('_%x+%.(epub)$',''):gsub('_%x+%.(pdf)$',''):gsub('_%x+%.(mobi)$','')
    if lfs.attributes(path,'mode')=='file' and (not needle or title:gsub('%s+',''):lower():find(needle,1,true)) then
     items[#items+1]={text=title,callback=function()self:openFile(path)end}
    end
   end
  end
 end
 table.sort(items,function(a,b)return a.text<b.text end)
 return items
end
function Books:showShelf()
 local items=self:shelfItems()
 if #items==0 then items[1]={text='还没有下载的书籍'} end
 items[#items+1]={text='返回书库',callback=function()self:showHub()end}
 self:menu('我的书',items)
end
function Books:searchBooks()
 self:closeMenu()
 require('pinyininput').show{
  title='搜书 · 本地 / '..S.name,text=self.book_query or '',
  submit=function(query)self:findBooks(query)end,
  cancel=function()self:showHub()end,
  home=function()self:returnHome()end,
 }
end
function Books:bookTask(message,work,done)
 NetworkMgr:runWhenConnected(function()
  self:closeMenu();local scratch=os.tmpname()
  Trapper:wrap(function()
   local completed,result=self:runTask(function()return work(scratch)end,message)
   S.cleanup(scratch)
   if completed then done(result or {error='书源没有返回结果，请重试'}) else self:showHub() end
  end)
 end)
end
function Books:findBooks(query,nexturl,online)
 query=S.query(query)
 if not query then UIManager:show(InfoMessage:new{text='请输入书名或作者'});return end
 self.book_query=query
 if not nexturl and not online then
  local localitems=self:shelfItems(query)
  if #localitems>0 then
   localitems[#localitems+1]={text='继续在线搜索 · '..S.name,callback=function()self:findBooks(query,nil,true)end}
   localitems[#localitems+1]={text='返回书库',callback=function()self:showHub()end}
   self:menu('本地找到《'..query..'》',localitems);return
  end
 end
 self:bookTask('正在搜索《'..query..'》…',function(scratch)return S.search(query,nexturl,scratch)end,function(result)
  local items={}
  if result.error then items[#items+1]={text=result.error}
  elseif #(result.items or {})==0 then
   items[#items+1]={text=S.name..'未找到《'..query..'》'}
   items[#items+1]={text='已有 EPUB / PDF / MOBI 链接？下载并阅读',callback=function()self:inputLink()end}
  else
   for _,item in ipairs(result.items) do local book=item
    items[#items+1]={text=book.title..((book.author or '')~='' and ' · '..book.author or ''),callback=function()self:showBookDetail(book)end}
   end
  end
  if result.nexturl then items[#items+1]={text='下一批结果',callback=function()self:findBooks(query,result.nexturl)end} end
  items[#items+1]={text='重新搜索',callback=function()self:searchBooks()end}
  items[#items+1]={text='返回书库',callback=function()self:showHub()end}
  self.book_results={title=S.name..' · '..query,items=items}
  self:menu(self.book_results.title,items)
 end)
end
function Books:showBookResults()
 if self.book_results then self:menu(self.book_results.title,self.book_results.items) else self:searchBooks() end
end
function Books:showBookDetail(item)
 self:bookTask('正在读取书籍信息…',function(scratch)return S.detail(item.url,scratch)end,function(book)
  local items={}
  if book.error then items[#items+1]={text=book.error}
  else
   if book.author and book.author~='' then items[#items+1]={text='作者：'..book.author} end
   if book.size then items[#items+1]={text='大小：'..book.size} end
   for _,entry in ipairs(book.formats or {}) do local format=entry
    items[#items+1]={text='下载 '..format.format..' 并阅读',callback=function()self:download(format.url,book.title)end}
   end
   if #(book.formats or {})==0 then items[#items+1]={text='此书暂没有可用的下载格式'} end
  end
  items[#items+1]={text='返回搜索结果',callback=function()self:showBookResults()end}
  items[#items+1]={text='重新搜索',callback=function()self:searchBooks()end}
  self:menu(book.title or item.title,items)
 end)
end
return Books
