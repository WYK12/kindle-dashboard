local L={}
function L.valid(path)
 if type(path)~='string' then return false end
 local name=path:match('^/mnt/us/Books/([^/\r\n]+)$')
 if not name or not (name:match('%.epub$') or name:match('%.pdf$') or name:match('%.mobi$')) then return false end
 local file=io.open(path,'rb');if not file then return false end;file:close()
 return true
end
function L.last()
 local chunk=loadfile('/mnt/us/koreader/history.lua');if not chunk then return end
 local ok,history=pcall(chunk);if not ok or type(history)~='table' then return end
 for _,item in ipairs(history) do
  if type(item)=='table' and L.valid(item.file) then
   local title=item.file:match('([^/]+)$'):gsub('%.epub$',''):gsub('%.pdf$',''):gsub('%.mobi$','')
   title=title:gsub('_(%x+)$',function(hash)return #hash==16 and '' or '_'..hash end)
   return item.file,title
  end
 end
end
return L
