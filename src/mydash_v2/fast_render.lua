local U=require('util')
require('setupkoenv')
local ffi=require('ffi')
local BB=require('ffi/blitbuffer')
local FT=require('ffi/freetype')
local R={buttons={},lines={},frame_count=0,page_count=0,forceFull=false}
local W,H,STRIDE=1072,1448,1088
local buffer=BB.new(W,H,BB.TYPE_BB8)
buffer:fill(BB.COLOR_WHITE)
local mapped,framebuffer,fbfd
local faces,glyphs={},{}
local glyph_count=0
local ts=ffi.new('struct timespec[1]')
local function now()ffi.C.clock_gettime(1,ts);return tonumber(ts[0].tv_sec)+tonumber(ts[0].tv_nsec)/1e9 end
local function screenY(y)return y end
local function touch(x,y,w,h)
 local d=R.damage
 if not d then R.damage={x=x,y=y,r=x+w,b=y+h}
 else d.x=math.min(d.x,x);d.y=math.min(d.y,y);d.r=math.max(d.r,x+w);d.b=math.max(d.b,y+h) end
end
local function mapScreen()
 if framebuffer then return end
 local state=assert(U.read(U.root..'/fbink-state.txt'),'Missing display geometry')
 assert(state:find('screenWidth=1072;screenHeight=1448;',1,true) and state:find('BPP=8;lineLength=1088;',1,true),'Unsupported framebuffer layout')
 fbfd=ffi.C.open('/dev/fb0',2);assert(fbfd>=0,'Cannot open framebuffer')
 mapped=ffi.C.mmap(nil,STRIDE*H,3,1,fbfd,0)
 if mapped==ffi.cast('void*',-1) then ffi.C.close(fbfd);error('Cannot map framebuffer') end
 framebuffer=BB.new(W,H,BB.TYPE_BB8,mapped,STRIDE)
end
local function faceFor(size)
 local key='b'..size
 if not faces[key] then
  local f=FT.newFaceSize('/usr/java/lib/fonts/STHeitiBold.ttf',size)
  local height,ascender=f:getHeightAndAscender()
  faces[key]={ft=f,ascender=math.ceil(ascender),height=math.max(size+2,math.ceil(height))}
 end
 return faces[key],key
end
local function codepoint(c)
 local a,b,c2,d=c:byte(1,4)
 if a<128 then return a elseif a<224 then return (a-192)*64+b-128
 elseif a<240 then return (a-224)*4096+(b-128)*64+c2-128 end
 return (a-240)*262144+(b-128)*4096+(c2-128)*64+d-128
end
local function glyphFor(face,key,code,heavy)
 local id=(heavy and 'h' or '')..key..':'..code;local glyph=glyphs[id]
 if not glyph then
  if glyph_count>=4096 then for _,g in pairs(glyphs) do g.bb:free() end;glyphs={};glyph_count=0 end
  glyph=face.ft:renderGlyph(code,heavy);glyphs[id]=glyph;glyph_count=glyph_count+1
 end
 return glyph
end
function R.add(s)R.lines[#R.lines+1]=s end
function R.rect(x,y,w,h,black)
 y=screenY(y);w=math.min(w,W-x);h=math.min(h,H-y)
 if w<=0 or h<=0 then return end
 buffer:paintRect(x,y,w,h,black and BB.COLOR_BLACK or BB.COLOR_WHITE)
 touch(x,y,w,h);R.ops=R.ops+1
end
function R.text(s,x,y,size,w,h,weight)
 s=tostring(s or ''):gsub('[%z\1-\8\11\12\14-\31]','')
 if s:match('^%s*$') then return end
 R.add('# -- '..U.quote(s))
 y=screenY(y);w=math.min(w or 960,W-x);h=math.min(h or 60,H-y);size=size or 36
 if w<=0 or h<=0 then return end
 local face,key=faceFor(size);local view=buffer:viewport(x,y,w,h)
 local pen,baseline=0,face.ascender
 for _,c in ipairs(U.utf8(s)) do
  if c=='\n' then pen=0;baseline=baseline+face.height
  else
   local glyph=glyphFor(face,key,codepoint(c),weight=='heavy')
   if pen>0 and pen+glyph.ax>w then pen=0;baseline=baseline+face.height end
   if baseline-face.ascender>=h then break end
   if glyph.bb:getWidth()>0 and glyph.bb:getHeight()>0 then
    view:colorblitFrom(glyph.bb,pen+glyph.l,baseline-glyph.t,0,0,glyph.bb:getWidth(),glyph.bb:getHeight(),BB.COLOR_BLACK)
   end
   pen=pen+glyph.ax
  end
 end
 touch(x,y,w,h);R.ops=R.ops+1
end
function R.hitbox(x,y,w,h,action)R.buttons[#R.buttons+1]={x=x,y=screenY(y),w=w,h=h,action=action}end
function R.compact(label,x,y,w,h,action)
 R.rect(x,y,w,h,true);R.rect(x+2,y+2,w-4,h-4,false)
 R.text(label,x+18,y+math.floor((h-40)/2),30,w-36,44,'medium');R.hitbox(x,y,w,h,action)
end
function R.button(label,x,y,w,h,action)
 R.rect(x,y,w,h,true);R.rect(x+3,y+3,w-6,h-6,false)
 R.text(label,x+20,y+math.floor((h-48)/2),36,w-40,58);R.hitbox(x,y,w,h,action)
end
function R.begin(title,back,compact)
 R.page_title=title
 R.lines={'#!/bin/sh','# Drawn in-process; this file is a page trace.'};R.buttons={};R.damage=nil;R.ops=0;R.started=now()
 buffer:paintRect(0,0,W,H,BB.COLOR_WHITE);touch(0,0,W,H)
 R.text(title,48,compact and 30 or 35,compact and 30 or 42,650,65,compact and 'medium' or nil)
 if back then if compact then R.compact('返回',866,20,158,58,back) else R.button('返回',846,24,178,85,back) end end
 R.rect(48,compact and 90 or 126,976,compact and 2 or 3,true)
end
function R.partial()
 R.lines={'#!/bin/sh','# Partial draw in-process.'}
 if R.page_title then R.add('# -- '..U.quote(R.page_title)) end
 R.damage=nil;R.ops=0;R.started=now()
end
function R.finish(full,region)
 local painted=now();R.frame_count=R.frame_count+1
 if full then R.page_count=R.page_count+1 end
 local flash=R.forceFull or R.frame_count==1 or (full and R.page_count>=8)
 if flash then R.page_count=0;R.last_flash=painted end
 R.forceFull=false
 local d=R.damage
 if not d then return end
 local area=region or {left=d.x,top=d.y,width=d.r-d.x,height=d.b-d.y}
 area.left=math.max(0,area.left);area.top=math.max(0,area.top)
 area.width=math.min(W-area.left,area.width);area.height=math.min(H-area.top,area.height)
 if flash then area={left=0,top=0,width=W,height=H} end
 if os.getenv('MYDASH_RENDER_OFFSCREEN')~='1' then
  mapScreen()
  framebuffer:blitFrom(buffer,area.left,area.top,area.left,area.top,area.width,area.height)
  local command='/var/tmp/mydash-v2-fbink -q -W '..(flash and 'GC16 -f' or 'DU')..' -s top='..area.top..',left='..area.left..',width='..area.width..',height='..area.height
  assert(U.exec(command..' >>'..U.quote(U.root..'/render.log')..' 2>&1'),'Screen refresh failed')
 end
 R.last_command_count=R.ops;R.last_draw_seconds=painted-R.started;R.last_finish_seconds=now()-painted
 U.write('/var/tmp/mydash-v2-frame.sh',table.concat(R.lines,'\n')..'\n')
 U.write('/var/tmp/mydash-v2-perf.txt',string.format('draw=%.4f submit=%.4f operations=%d processes=1 flash=%s region=%dx%d\n',R.last_draw_seconds,R.last_finish_seconds,R.ops,tostring(flash),area.width,area.height))
end
function R.hit(x,y)for _,b in ipairs(R.buttons)do if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then return b.action end end end
function R.close()
 if mapped then framebuffer=nil;ffi.C.munmap(mapped,STRIDE*H);ffi.C.close(fbfd);mapped=nil end
end
function R.snapshot(path)buffer:writePNG(path)end
return R
