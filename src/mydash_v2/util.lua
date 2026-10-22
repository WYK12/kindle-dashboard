local M={}
M.root=os.getenv('MYDASH_ROOT') or '/mnt/us/mydash_v2'
package.path=package.path..';'..M.root..'/?.lua;/mnt/us/koreader/common/?.lua'
M.json=require('dkjson')
function M.quote(s) return "'"..tostring(s):gsub("'", "'\\''").."'" end
function M.read(p) local f=io.open(p,'rb'); if not f then return nil end local s=f:read('*a');f:close();return s end
function M.write(p,s) local f,e=io.open(p..'.tmp','wb');if not f then return nil,e end f:write(s);f:close();return os.rename(p..'.tmp',p) end
function M.load(p,default) local s=M.read(p);if not s then return default end local t=M.json.decode(s);return type(t)=='table' and t or default end
function M.save(p,t) return M.write(p,M.json.encode(t,{indent=true})) end
function M.capture(cmd) local f=io.popen(cmd..' 2>/dev/null');if not f then return '' end local s=f:read('*a');f:close();return (s:gsub('%s+$','')) end
function M.exec(cmd) return os.execute(cmd)==0 end
function M.discard_input(fd,events,size)
 local C=require('ffi').C
 while C.read(fd,events,size)==size do end
end
function M.utf8(s) local a={};for c in tostring(s):gmatch('[%z\1-\127\194-\244][\128-\191]*') do a[#a+1]=c end return a end
function M.short(s,n) local a=M.utf8(s);if #a<=n then return s end return table.concat(a,'',1,n-1)..'…' end
function M.url(s) return (s:gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)) end
function M.validurl(s) return type(s)=='string' and #s<=2048 and s:match('^https?://[%w%-%._%[%]:]+') and not s:find('[%c%s]') end
function M.config() return M.load(M.root..'/config.json',{city={name='南京',latitude=32.06,longitude=118.79},feeds={{name='中新网·要闻',url='https://www.chinanews.com.cn/rss/importnews.xml'}},refresh_minutes=60}) end
function M.encodedchar(n)
 if n<0 or n>1114111 or (n>=55296 and n<=57343) or n==65534 or n==65535 then return '' end
 if n<128 then return string.char(n) elseif n<2048 then return string.char(192+math.floor(n/64),128+n%64) elseif n<65536 and not (n>=55296 and n<=57343) then return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) elseif n<=1114111 then return string.char(240+math.floor(n/262144),128+math.floor(n/4096)%64,128+math.floor(n/64)%64,128+n%64) end return ''
end
function M.entities(s)
 local ent={amp='&',lt='<',gt='>',quot='"',apos="'",nbsp=' ',hellip='…',mdash='—',ndash='–',lsquo='‘',rsquo='’',ldquo='“',rdquo='”',bull='•',copy='©',times='×',middot='·'}
 s=s or ''
 s=s:gsub('&#x(%x+);',function(n)return M.encodedchar(tonumber(n,16))end):gsub('&#(%d+);',function(n)return M.encodedchar(tonumber(n))end):gsub('&(%a+);',function(n)return ent[n] or ('&'..n..';')end)
 return s
end
function M.xmlcontent(s)
 local cdata=s:match('^%s*<!%[CDATA%[(.-)%]%]>%s*$');return cdata or M.entities(s)
end
function M.plain(s)
 s=M.entities((s or ''):gsub('<!%[CDATA%[(.-)%]%]>','%1'))
 s=s:gsub('<script[^>]*>.-</script>',''):gsub('<style[^>]*>.-</style>',''):gsub('<[^>]+>',' ')
 return (s:gsub('[%z\1-\31]',' '):gsub('%s+',' '):gsub('^%s+',''):gsub('%s+$',''))
end
function M.feed(xml,source)
 local a={};local pattern=xml:find('<item[%s>]') and '<item[%s>].-</item>' or '<entry[%s>].-</entry>'
 for item in xml:gmatch(pattern) do
  local title=M.plain(item:match('<title[^>]*>(.-)</title>'))
  local link=item:match('<link[^>]*href=["\'](.-)["\']') or M.plain(item:match('<link[^>]*>(.-)</link>'))
  local full=item:match('<content:encoded[^>]*>(.-)</content:encoded>') or item:match('<content[^>]*>(.-)</content>')
  local body=full or item:match('<description[^>]*>(.-)</description>') or item:match('<summary[^>]*>(.-)</summary>') or ''
  local html=M.xmlcontent(body);local text=M.plain(html)
  if title~='' then a[#a+1]={title=title,link=link,body=M.short(text,60000),html=html:sub(1,250000),content_kind=full and 'feed' or 'summary',truncated=#html>250000,source=source};if #a>=20 then break end end
 end
 return a
end
return M
