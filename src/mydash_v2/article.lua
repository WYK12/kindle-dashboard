local U=require('util');package.path=package.path..';/mnt/us/koreader/?.lua'
local A={}
local bit=require('bit')
local function escape(s) return U.entities(s or ''):gsub('[%z\1-\8\11\12\14-\31]',''):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;') end
A.escape=escape
function A.id(item)
 return require('ffi/sha2').sha256((item.link or '')~='' and item.link or ((item.source or '')..'\n'..item.title)):sub(1,24)
end
local function parser(html)
 htmlparser_opts={silent=true,looplimit=30000}
 local ok,root=pcall(require('htmlparser').parse,html,30000)
 return ok and root or nil
end
local drop={script=true,style=true,noscript=true,iframe=true,object=true,svg=true,form=true,button=true,input=true,textarea=true,select=true,nav=true,aside=true,footer=true,header=true}
local keep={p=true,div=true,section=true,article=true,blockquote=true,h1=true,h2=true,h3=true,h4=true,h5=true,h6=true,ul=true,ol=true,li=true,pre=true,code=true,strong=true,em=true,b=true,i=true,sub=true,sup=true,table=true,thead=true,tbody=true,tr=true,td=true,th=true,figure=true,figcaption=true}
local function serialize(node)
 local tag=(node.name or ''):lower();if drop[tag] then return '' end
 local cls=(node.attributes and ((node.attributes.class or '')..' '..(node.attributes.id or ''))) or ''
 cls=cls:lower()
 if cls:find('comment',1,true) or cls:find('recommend',1,true) or cls:find('related',1,true) or cls:find('paywall',1,true) then return '' end
 if tag=='br' then return '<br/>' elseif tag=='hr' then return '<hr/>'
 elseif tag=='img' then return '<p class="image-note">[图片'..((node.attributes.alt or '')~='' and ('：'..escape(node.attributes.alt)) or '')..']</p>' end
 local root=node.root;local cursor=tag=='root' and 1 or node._openend+1
 local stop=tag=='root' and #root._text or node._closestart-1
 local out={};local children={};for _,c in ipairs(node.nodes or {}) do children[#children+1]=c end
 table.sort(children,function(a,b)return a._openstart<b._openstart end)
 for _,child in ipairs(children) do
  if child._openstart>=cursor and child._openstart<=stop then
   out[#out+1]=escape(root._text:sub(cursor,child._openstart-1):gsub('<!%-%-.-%-%->',''))
   out[#out+1]=serialize(child);cursor=math.max(cursor,child._closeend+1)
  end
 end
 if cursor<=stop then out[#out+1]=escape(root._text:sub(cursor,stop):gsub('<!%-%-.-%-%->','')) end
 local content=table.concat(out)
 if tag=='p' and not content:find('<hr',1,true) and U.plain(content):gsub('\226\128\139',''):match('^%s*$') then return '' end
 if keep[tag] then return '<'..tag..'>'..content..'</'..tag..'>' end
 return content
end
function A.sanitize(html)
 local root=parser(html or '');if not root then return nil end
 return serialize(root)
end
function A.public_body(html)
 -- The Paper's public mobile pages embed their article in Next.js page data.
 local payload=html:match('<script[^>]-id=["\']__NEXT_DATA__["\'][^>]*>(.-)</script>')
 local data=payload and U.json.decode(payload)
 local props=type(data)=='table' and data.props
 local page=type(props)=='table' and props.pageProps
 local detail=type(page)=='table' and page.detailData
 detail=type(detail)=='table' and detail.contentDetail
 if type(detail)=='table' and type(detail.content)=='string' and not detail.paywalled then
  local clean=A.sanitize(detail.content)
  local text=clean and U.plain(clean) or ''
  if #U.utf8(text)>=220 and not text:find('登录后阅读全文',1,true) and not text:find('订阅后阅读全文',1,true) then return clean end
 end
 local root=parser(html);if not root then return nil end
 for _,selector in ipairs({'.article-body','.entry-content','.post-content','.post-body','.article-content','.article__content','#article-content','.left_zw','article'}) do
  local ok,nodes=pcall(root.select,root,selector)
  if ok then for _,node in ipairs(nodes) do
   local clean=serialize(node);local text=U.plain(clean)
   if #U.utf8(text)>=220 and not text:find('登录后阅读全文',1,true) and not text:find('订阅后阅读全文',1,true) then return clean end
  end end
 end
end
function A.summary(item)
 local html=item.html
 if not html or html=='' then
  local text=U.plain(item.body or ''):gsub('查看全文',''):gsub('阅读全文','')
  return '<p>'..escape(text)..'</p>'
 end
 local clean=A.sanitize(html) or ('<p>'..escape(U.plain(item.body or ''))..'</p>')
 return clean:gsub('查看全文',''):gsub('阅读全文','')
end
local crcTable={}
for i=0,255 do local c=i;for _=1,8 do c=bit.bxor(bit.rshift(c,1),bit.band(c,1)==1 and 0xEDB88320 or 0) end;crcTable[i]=c end
local function crc32(s)
 local c=-1;for i=1,#s do c=bit.bxor(bit.rshift(c,8),crcTable[bit.band(bit.bxor(c,s:byte(i)),255)]) end
 return bit.bnot(c)%4294967296
end
local function p16(n) return string.char(n%256,math.floor(n/256)%256) end
local function p32(n) return p16(n%65536)..p16(math.floor(n/65536)) end
local function zip(entries)
 local chunks,central={},{};local offset=0
 for _,item in ipairs(entries) do local name,data=item[1],item[2];local crc=crc32(data);local n=#data
  local common=p16(20)..p16(2048)..p16(0)..p16(0)..p16(33)..p32(crc)..p32(n)..p32(n)..p16(#name)
  local localpart=p32(0x04034b50)..common..p16(0)..name..data
  central[#central+1]=p32(0x02014b50)..p16(20)..common..p16(0)..p16(0)..p16(0)..p16(0)..p32(0)..p32(offset)..name
  chunks[#chunks+1]=localpart;offset=offset+#localpart
 end
 local directory=table.concat(central)
 return table.concat(chunks)..directory..p32(0x06054b50)..p16(0)..p16(0)..p16(#entries)..p16(#entries)..p32(#directory)..p32(offset)..p16(0)
end
function A.epub(item,html,status)
 local id=A.id(item);local title=escape(item.title);local source=escape(item.source or 'RSS')
 local note=status=='summary' and '<p class="notice">当前仅有订阅摘要，未取得可公开提取的正文。</p>' or ''
 local xhtml='<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN"><head><title>'..title..'</title><link rel="stylesheet" href="style.css" type="text/css"/></head><body><h1>'..title..'</h1><p class="source">'..source..'</p>'..note..html..'<hr/><p class="source">来源：'..escape(item.link or '')..'</p></body></html>'
 local css='body{color:#000;background:#fff;}h1{font-size:1.4em;line-height:1.4;margin:0 0 1em;}h2,h3{line-height:1.4;}p{line-height:1.65;margin:0 0 .8em;text-indent:2em;}blockquote{margin:1em;}pre{white-space:pre-wrap;}p.source,p.notice,p.image-note{text-indent:0;font-size:.9em;}p.notice{border-top:1px solid #000;border-bottom:1px solid #000;padding:.5em 0;}table{border-collapse:collapse;}td,th{padding:.3em;border:1px solid #000;}'
 local opf='<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">urn:mydash:'..id..'</dc:identifier><dc:title>'..title..'</dc:title><dc:creator>'..source..'</dc:creator><dc:language>zh-CN</dc:language></metadata><manifest><item id="text" href="article.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="ncx"><itemref idref="text"/></spine></package>'
 local ncx='<?xml version="1.0" encoding="utf-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="urn:mydash:'..id..'"/></head><docTitle><text>'..title..'</text></docTitle><navMap><navPoint id="article" playOrder="1"><navLabel><text>'..title..'</text></navLabel><content src="article.xhtml"/></navPoint></navMap></ncx>'
 return zip({{'mimetype','application/epub+zip'},{'META-INF/container.xml','<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'},{'OEBPS/content.opf',opf},{'OEBPS/toc.ncx',ncx},{'OEBPS/style.css',css},{'OEBPS/article.xhtml',xhtml}})
end
function A.feed_book(item)
 if item.content_kind~='feed' or item.truncated then return nil end
 local clean=A.summary(item)
 if not clean or #U.utf8(U.plain(clean))<8 then return nil end
 return A.epub(item,clean,'feed')
end
return A
