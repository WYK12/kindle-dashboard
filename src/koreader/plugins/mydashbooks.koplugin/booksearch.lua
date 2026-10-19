local util=require('util')
local S={name='读书派',origin='https://www.dushupai.com'}
local function quote(s)return "'"..tostring(s):gsub("'","'\\''").."'"end
local function plain(s)return util.htmlToPlainText(s or ''):gsub('%s+',' '):gsub('^%s+',''):gsub('%s+$','')end
local function encode(s)return (s:gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end))end
function S.query(text)
 if type(text)~='string' or #text>240 or text:find('[%c]') then return nil end
 text=text:gsub('^%s+',''):gsub('%s+$',''):gsub('^《(.-)》$','%1'):gsub('^%s+',''):gsub('%s+$','')
 if text~='' then return text end
end
function S.allowed(url)
 return type(url)=='string' and #url<=4096 and not url:find('[%c%s]') and url:match('^https://www%.dushupai%.com/')~=nil
end
function S.absolute(url)
 url=util.htmlEntitiesToUtf8(url or '')
 if url:sub(1,1)=='/' and url:sub(1,2)~='//' then url=S.origin..url end
 if S.allowed(url) then return url end
end
function S.cleanup(scratch)
 os.remove(scratch);os.remove(scratch..'.html');os.remove(scratch..'.url')
end
local function get(url,scratch)
 if not S.allowed(url) then return nil,nil,'书源地址无效' end
 local command='curl --fail --silent --show-error --location --proto "=https" --proto-redir "=https" --connect-timeout 5 --max-time 20 --max-filesize 2097152 -A '..quote('MyDashBooks/2.17 (Kindle personal reader)')..' -o '..quote(scratch..'.html')..' -w "%{url_effective}" '..quote(url)..' >'..quote(scratch..'.url')..' 2>/dev/null'
 local ok=os.execute(command)==0
 local f=io.open(scratch..'.html','rb');local html=f and f:read('*a');if f then f:close() end
 f=io.open(scratch..'.url','rb');local final=f and f:read('*a');if f then f:close() end
 os.remove(scratch..'.html');os.remove(scratch..'.url')
 if not ok or not html then return nil,nil,'读书派连接失败，请稍后重试' end
 if not S.allowed(final) then return nil,nil,'书源跳转异常，请稍后重试' end
 return html,final
end
local function rows(html)
 local items,seen={},{}
 for row in html:gmatch('<li%s+class=["\']portfolio%-item["\'][^>]*>(.-)</li>') do
  local link,title=row:match('<a[^>]-href=["\']([^"\']+)["\'][^>]-title=["\']([^"\']+)["\']')
  link=link and S.absolute(link)
  if link and link:match('/book%-content%-%d+%.html$') and not seen[link] then
   seen[link]=true;items[#items+1]={title=plain(title),author=plain(row:match('<div%s+class=["\']portfolio%-author["\'][^>]*>(.-)</div>')),url=link}
  end
 end
 return items
end
local function nextpage(html)
 for link,label in html:gmatch('<a[^>]-href=["\']([^"\']+)["\'][^>]*>(.-)</a>') do
  if plain(label)=='下一页' then return S.absolute(link) end
 end
end
function S.parseSearch(html,url,query)
 if not html:find('portfolio-book',1,true) and not html:find('没有',1,true) then return {error='书源返回了异常页面，请稍后重试'} end
 local items={};local q=query and query:gsub('%s+',''):lower()
 for i,item in ipairs(rows(html)) do
  local title=item.title:gsub('%s+',''):lower();local author=item.author:gsub('%s+',''):lower()
  local rank=not q and 0 or title==q and 0 or title:find(q,1,true) and 1 or author:find(q,1,true) and 2
  -- The website also returns loose character matches; keep actual title/author matches.
  if rank or (q and q:match('^%d+$')) then item.rank=rank or 3;item.order=i;items[#items+1]=item end
 end
 table.sort(items,function(a,b)return a.rank==b.rank and a.order<b.order or a.rank<b.rank end)
 return {items=items,nexturl=nextpage(html),url=url}
end
function S.search(query,nexturl,scratch)
 query=S.query(query);if not query then return {error='请输入书名或作者'} end
 if nexturl and (not S.allowed(nexturl) or not nexturl:find('/search.html?',1,true)) then return {error='分页地址无效'} end
 local own=not scratch;scratch=scratch or os.tmpname()
 local html,url,err=get(nexturl or (S.origin..'/search.html?k='..encode(query)),scratch)
 if own then S.cleanup(scratch) end
 return html and S.parseSearch(html,url,query) or {error=err}
end
function S.parseDetail(html,url)
 local book={url=url,formats={},title=plain(html:match('<h1%s+class=["\']post%-title["\'][^>]*>(.-)</h1>'))}
 for row in html:gmatch('<li[^>]*>(.-)</li>') do
  local text=plain(row)
  book.author=book.author or text:match('^作者：%s*(.*)')
  book.format=book.format or text:match('^格式：%s*(.*)')
 end
 if book.title=='' then return {error='无法读取书籍信息，请稍后重试'} end
 return book
end
function S.detail(url,scratch)
 local id=S.allowed(url) and url:match('/book%-content%-(%d+)%.html$')
 if not id then return {error='书籍地址无效'} end
 local own=not scratch;scratch=scratch or os.tmpname()
 local html,final,err=get(url,scratch)
 local book=html and S.parseDetail(html,final) or {error=err}
 if not book.error then
  local download,_,e=get(S.origin..'/download-book-'..id..'.html',scratch)
  if not download then book.error=e else
   for link in download:gmatch('<a[^>]-href=["\']([^"\']+)["\']') do
    link=util.htmlEntitiesToUtf8(link)
    if link:match('^https://[%w%-]+%.ctfile%.com/f/%d+%-%d+%-%x+') then
     book.formats[1]={format=book.format or '电子书',url=link};break
    end
   end
   if #book.formats==0 then book.error='此版本暂无可直接下载的文件，请选择其他版本' end
  end
 end
 if own then S.cleanup(scratch) end
 return book
end
function S.parseCatalog(html)
 local items=rows(html)
 if #items==0 then return {error='书目暂时无法读取，请稍后重试'} end
 return {items=items,nexturl=nextpage(html)}
end
function S.browse(url,scratch)
 if not S.allowed(url) or not url:match('/book%-category%-[%w%-]+%.html$') then return {error='书目地址无效'} end
 local own=not scratch;scratch=scratch or os.tmpname()
 local html,_,err=get(url,scratch)
 if own then S.cleanup(scratch) end
 return html and S.parseCatalog(html) or {error=err}
end
return S
