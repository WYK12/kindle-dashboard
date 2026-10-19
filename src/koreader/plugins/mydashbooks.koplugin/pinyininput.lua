local InputDialog=require('ui/widget/inputdialog')
local UIManager=require('ui/uimanager')
local InputText=require('ui/widget/inputtext')
local VirtualKeyboard=require('ui/widget/virtualkeyboard')
local Geom=require('ui/geometry')
local InfoMessage=require('ui/widget/infomessage')
local P=dofile('/mnt/us/mydash_v2/pinyin.lua')
local I={}
local PlainKeyboard=VirtualKeyboard:extend{}
function PlainKeyboard:getKeyboardLayout()return 'en'end
function PlainKeyboard:setKeyboardLayout()self:init();self:_refresh(true)end
local LetterInput=InputText:extend{}
function LetterInput:initKeyboard()
 self.key_events={}
 self.keyboard=PlainKeyboard:new{keyboard_layer=self.input_type=='number' and 4 or 2,inputbox=self}
end
function I.show(options)
 local dialog;local mode=true;local page=1;local busy=false;local last='';local lastLabels=''
 local function refresh(reset)
  if not dialog or not dialog.button_table then return end
  local text=dialog:getInputText()
  if reset or text~=last then page=1 end
  last=text
  local words=mode and P.lookup(text) or {}
  local pages=math.max(1,math.ceil(#words/4));page=math.min(page,pages)
  local labels={};for i=1,4 do labels[i]=words[(page-1)*4+i] or ' ' end
  labels[5]=page>1 and '上一组' or ' ';labels[6]=page<pages and '下一组' or ' '
  local signature=table.concat(labels,'|');if signature==lastLabels then return end;lastLabels=signature
  for i=1,4 do
   local button=dialog.button_table:getButtonById('candidate'..i)
   button:setText(words[(page-1)*4+i] or ' ',button.width)
  end
  dialog.button_table:getButtonById('prev'):setText(page>1 and '上一组' or ' ',dialog.button_table:getButtonById('prev').width)
  dialog.button_table:getButtonById('next'):setText(page<pages and '下一组' or ' ',dialog.button_table:getButtonById('next').width)
  local tableArea=dialog.button_table.dimen;local first=dialog.button_table:getButtonById('candidate1').dimen
  local area=tableArea and first and Geom:new{x=tableArea.x,y=first.y,w=tableArea.w,h=first.h+2} or nil
  UIManager:setDirty(dialog,'ui',area)
 end
 local function setText(text)
  busy=true;dialog:setInputText(text,true,false);busy=false;refresh(true)
 end
 local function submit()
  local text=dialog:getInputText()
  text=text:gsub('^%s+',''):gsub('%s+$','')
  if text=='' then return end
  -- Candidate selection is explicit: huozhe can mean 活着 or 或者.
  if mode and text:find('[A-Za-z]') then
   UIManager:show(InfoMessage:new{text='书名里还有拼音，请先点候选汉字，再搜索。\n英文书名请切换 English。'})
   return
  end
  UIManager:close(dialog);options.submit(text)
 end
 local candidates={}
 for i=1,4 do local index=i
  candidates[#candidates+1]={id='candidate'..i,text=' ',font_size=20,callback=function()
   if mode then setText(P.choose(dialog:getInputText(),(page-1)*4+index)) end
  end}
 end
 candidates[#candidates+1]={id='prev',text=' ',font_size=16,callback=function()page=math.max(1,page-1);refresh()end}
 candidates[#candidates+1]={id='next',text=' ',font_size=16,callback=function()page=page+1;refresh()end}
 local actions={
  {text='取消',id='close',callback=function()UIManager:close(dialog);if options.cancel then options.cancel() end end},
  {text='搜索',is_enter_default=true,callback=submit},
 }
 if options.home then
  table.insert(actions,2,{text='首页',id='home',callback=function()UIManager:close(dialog);options.home()end})
 end
 dialog=InputDialog:new{
  title=options.title or '中文搜索',input=options.text or '',input_hint='书名或作者',inputtext_class=LetterInput,
  description='输入拼音后点候选汉字，确认书名再搜索。英文书名切换 English。',
  buttons={candidates,
   {{text='中文拼音',callback=function()mode=true;refresh(true)end},
    {text='English',callback=function()mode=false;refresh(true)end},
    {text='清空',callback=function()setText('')end}},
   actions},
  edited_callback=function()if not busy then refresh(true) end end,
 }
 -- Keep this input widget on the plain letter layout. Candidate selection belongs
 -- to the dialog, so keyboard reinitialization cannot silently disable Chinese.
 UIManager:show(dialog);dialog:onShowKeyboard();refresh(true)
 return dialog
end
return I
