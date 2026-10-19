local lfs=require('libs/libkoreader-lfs')
local B={directory='/mnt/us/Books',limit=33554432}
local function quote(s)return "'"..tostring(s):gsub("'","'\\''").."'"end
function B.validurl(s)
 return type(s)=='string' and #s<=4096 and s:match('^https?://[%w%-%._%[%]:]+') and not s:find('[%c%s]')
end
function B.detect(path)
 local f=io.open(path,'rb');if not f then return nil end
 local head=f:read(4096) or '';f:close()
 if head:sub(1,4)=='PK\3\4' then
  if head:find('application/epub+zip',1,true) then return 'epub' end
  return nil
 end
 local pdf=head:find('%PDF-',1,true);if pdf and pdf<=1024 then return 'pdf' end
 if #head>=78 and head:sub(61,68)=='BOOKMOBI' then return 'mobi' end
end
local function id(url)return require('ffi/sha2').sha256(url):sub(1,16)end
function B.lookup(url)
 local key=id(url)
 if lfs.attributes(B.directory,'mode')~='directory' then return nil end
 for name in lfs.dir(B.directory) do
  if name:match('_'..key..'%.epub$') or name:match('_'..key..'%.pdf$') or name:match('_'..key..'%.mobi$') then
   local path=B.directory..'/'..name
   if B.detect(path) then return path end
  end
 end
end
local function filename(title)
 local out={};for c in (title or '下载书籍'):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
  if #out>=50 then break end;out[#out+1]=c
 end
 local s=table.concat(out):gsub('[%c/\\:*?"<>|]','_'):gsub('^%.+',''):gsub('%s+$','')
 return s~='' and s or '下载书籍'
end
local function request(url,data,part)
 local J=require('dkjson');local input=part..'.request';local output=part..'.json';local extra=''
 if data then
  local f=io.open(input,'wb');if not f then return nil end
  f:write(J.encode(data));f:close()
  extra=' -H "Content-Type: application/json" --data-binary @'..quote(input)
 end
 local ok=os.execute('curl --fail --silent --show-error --location --proto "=https" --proto-redir "=https" --connect-timeout 6 --max-time 25 --max-filesize 1048576 -o '..quote(output)..extra..' '..quote(url)..' 2>/dev/null')==0
 local f=io.open(output,'rb');local raw=f and f:read('*a');if f then f:close() end
 os.remove(input);os.remove(output)
 local result=ok and raw and J.decode(raw)
 return type(result)=='table' and result or nil
end
function B.resolve(url,part)
 local id=url:match('^https://[%w%-]+%.ctfile%.com/f/([^?#]+)')
 if not id then return url end
 local pwd=url:match('[?&]pwd=([%w]+)') or ''
 if #id>128 or not id:match('^%d+%-%d+%-%x+$') or #pwd>64 then return nil,'下载链接无效' end
 local base='https://urlapi.ctfile.com/api/v2/'
 local r=request(base..'resource?kind=file&id='..id..'&folder_id=0&fk=&passcode='..pwd..'&type_id=0',nil,part)
 if not r or r.code~=200 or type(r.data)~='table' then return nil,'下载服务暂不可用，请稍后重试' end
 local d=r.data;local cap=d.capabilities or {};local f=d.file or {}
 if cap.download==false or cap.canDownload==false or cap.vip_required or cap.captchaRequired or (cap.download~=true and cap.canDownload~=true) then
  return nil,'此版本需要登录或验证，请选择其他版本'
 end
 if tonumber(f.file_size_bytes) and tonumber(f.file_size_bytes)>B.limit then return nil,'文件超过 32 MB，请选择其他版本' end
 local wait=tonumber(f.wait_seconds) or 0
 if wait<0 or wait>30 then return nil,'下载需要等待，请稍后重试' end
 if wait>0 then require('socket').sleep(wait) end
 local payload={context=d.context or {kind='file',id=id,folder_id='0',fk='',passcode=pwd,type_id='0'},
  mb=false,app=false,verifycode=f.verifycode,
  original_file={file_id=f.file_id,userid=f.userid,file_chk=f.file_chk,start_time=f.start_time,wait_seconds=f.wait_seconds}}
 for attempt=1,2 do
  r=request(base..'download',payload,part)
  d=r and type(r.data)=='table' and r.data or {}
  local code=d.code or (r and r.code);local remaining=tonumber(d.remaining_seconds)
  if code==200 and type(d.downurl)=='string' and #d.downurl<=4096 and not d.downurl:find('[%c%s]') then
   if d.downurl:match('^https://[%w%-]+%.tv002%.com/') or d.downurl:match('^https://[%w%-]+%.ctfile%.com/') then return d.downurl end
   return nil,'下载地址暂不支持，请选择其他版本'
  elseif code==218 and attempt==1 and remaining and remaining>0 and remaining<=30 then
   require('socket').sleep(remaining)
  else
   return nil,(code==217 or code==219) and '此版本需要登录或验证，请选择其他版本' or '暂时无法获取文件，请稍后重试'
  end
 end
 return nil,'下载尚未准备好，请稍后重试'
end
function B.unpack(path)
 local pipe=io.popen('unzip -l '..quote(path)..' 2>/dev/null')
 if not pipe then return nil,'无法读取书籍压缩包' end
 local chosen;local count=0;local rank={epub=1,mobi=2,azw3=3,pdf=4}
 for line in pipe:lines() do
  count=count+1;if count>1000 or #line>4096 then pipe:close();return nil,'压缩包内容过多，请选择其他版本' end
  local length,name=line:match('^%s*(%d+)%s+%S+%s+%S+%s+(.-)%s*$')
  local ext=name and name:lower():match('%.([%w]+)$');length=tonumber(length)
  if ext and rank[ext] and length>0 and length<=B.limit and not name:find('[%c]') and name:sub(1,1)~='/' and name:sub(1,1)~='-' and not ('/'..name..'/'):find('/../',1,true) then
   if not chosen or rank[ext]<chosen.rank then chosen={name=name,length=length,rank=rank[ext]} end
  end
 end
 pipe:close()
 if not chosen then return nil,'压缩包内没有可用的 EPUB、PDF 或 MOBI 书籍（最多 32 MB）' end
 local output=path..'.book'
 local f=io.open(output,'wb');if not f then return nil,'无法保存书籍' end
 pipe=io.popen('unzip -p '..quote(path)..' '..quote(chosen.name)..' 2>/dev/null')
 if not pipe then f:close();os.remove(output);return nil,'无法解开书籍压缩包' end
 local bytes=0
 while true do
  local chunk=pipe:read(65536);if not chunk then break end
  bytes=bytes+#chunk
  if bytes>B.limit then break end
  if not f:write(chunk) then bytes=B.limit+1;break end
 end
 f:close();local ok=pipe:close()
 local ext=bytes==chosen.length and bytes<=B.limit and (ok==true or ok==0) and B.detect(output)
 if not ext then os.remove(output);return nil,'压缩包内的书籍无效或未下载完整，请选择其他版本' end
 if not os.rename(output,path) then os.remove(output);return nil,'无法保存解包后的书籍' end
 return ext
end
function B.cleanup(part)
 for _,suffix in ipairs({'','.request','.json','.book'}) do os.remove(part..suffix) end
end
function B.fetch(url,title,part)
 if not B.validurl(url) then return {error='请输入完整的 http 或 https 下载链接'} end
 local cached=B.lookup(url);if cached then return {path=cached,cached=true} end
 if os.execute('mkdir -p '..quote(B.directory))~=0 then return {error='无法创建下载目录'} end
 if not part:match('^/mnt/us/Books/%.download%-%d+%-%d+%.part$') then return {error='下载任务无效'} end
 local free=io.popen("df -Pk /mnt/us | awk 'NR==2 {print $4}'")
 local kb=free and tonumber(free:read('*a'));if free then free:close() end
 if kb and kb<35000 then return {error='可用空间不足，请先整理书籍'} end
 local resolved,err=B.resolve(url,part)
 if not resolved then return {error=err} end
 local command='curl --fail --silent --show-error --location --proto "=http,https" --proto-redir "=http,https" --connect-timeout 6 --max-time 300 --max-filesize '..B.limit..' -o '..quote(part)..' '..quote(resolved)..' 2>/dev/null'
 local ok=os.execute(command)==0
 local bytes=lfs.attributes(part,'size') or 0
 if not ok or bytes==0 or bytes>B.limit then os.remove(part);return {error='下载失败，请检查网络、链接或文件大小（最多 32 MB）'} end
 local ext=B.detect(part)
 if not ext then
  local f=io.open(part,'rb');local head=f and f:read(4);if f then f:close() end
  if head=='PK\3\4' then ext,err=B.unpack(part) end
 end
 if not ext then os.remove(part);return {error=err or '链接没有返回 EPUB、PDF 或 MOBI 文件，可能是网页或登录页'} end
 local path=B.directory..'/'..filename(title)..'_'..id(url)..'.'..ext
 if not os.rename(part,path) then os.remove(part);return {error='无法保存书籍'} end
 return {path=path}
end
return B
