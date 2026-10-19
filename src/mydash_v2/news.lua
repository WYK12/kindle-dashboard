local U=require('util')
local N={sources={
 {id='huxiu',name='虎嗅热文',url='https://www.huxiu.com/'},
 {id='thepaper',name='澎湃热榜',url='https://cache.thepaper.cn/contentapi/wwwIndex/rightSidebar'},
}}
function N.parse(source,body)
 local rows={}
 if source.id=='huxiu' then
  htmlparser_opts={silent=true,looplimit=30000}
  local ok,root=pcall(require('htmlparser').parse,body,30000)
  if not ok or not root then return rows end
  local ok,nodes=pcall(root.select,root,'.hot-article-wrap .article-wrap__info a.title-wrap')
  if not ok then return rows end
  local seen={}
  for i,node in ipairs(nodes) do
   local link=node.attributes.href or ''
   local title=U.plain(node.root._text:sub(node._openend+1,node._closestart-1)):gsub('^原创%s+','')
   if title~='' and link:match('^https://www%.huxiu%.com/article/%d+%.html$') and not seen[link] then
    seen[link]=true;rows[#rows+1]={title=title,link=link,source=source.name,board=source.id,rank=i,period='48小时热文',body='',content_kind='summary'}
   end
   if #rows>=20 then break end
  end
 elseif source.id=='thepaper' then
  local data=U.json.decode(body)
  local entries=type(data)=='table' and data.resultCode==1 and type(data.data)=='table' and data.data.hotNews
  if type(entries)~='table' then return rows end
  for i,entry in ipairs(entries) do
   if type(entry)=='table' and not entry.paywalled and (not entry.contType or entry.contType==0) then
    local title=type(entry.name)=='string' and U.plain(entry.name) or ''
    local id=tostring(entry.contId or '')
    if title~='' and id:match('^%d+$') then rows[#rows+1]={title=title,source=source.name,board=source.id,rank=i,
     link='https://m.thepaper.cn/newsDetail_forward_'..id,body=type(entry.summary)=='string' and U.plain(entry.summary) or '',content_kind='summary'} end
   end
   if #rows>=20 then break end
  end
 end
 return rows
end
function N.items(snapshot,board)
 if not board or board=='all' then return snapshot.items or {} end
 local rows={};for _,item in ipairs(snapshot.items or {}) do if item.board==board then rows[#rows+1]=item end end
 return rows
end
function N.label(item)
 return (item.source or '')..(item.rank and (' · 第 '..item.rank..' 位') or '')
end
-- Interleave the platforms' own rankings; never invent a combined heat score.
function N.merge(feeds,sources)
 local items,seen={},{}
 for row=1,50 do
  for _,feed in ipairs(feeds) do
   local source=sources[feed.url]
   local item=source and source.items[row]
   if item then
    local key=item.link and item.link~='' and item.link or (item.source or '')..'\n'..item.title
    if not seen[key] then seen[key]=true;items[#items+1]=item end
   end
  end
 end
 return items
end
function N.replace(previous,current)
 local old=(previous.items or {})[previous.home_index or 1]
 local items=current.items or {}
 current.home_index=math.max(1,math.min(previous.home_index or 1,#items))
 current.next_change=previous.next_change
 if old then
  for i,item in ipairs(items) do
   if item.source==old.source and item.title==old.title and item.link==old.link then current.home_index=i;break end
  end
 end
 return current
end
function N.advance(rss,now)
 if not rss.next_change then rss.next_change=now+180;return false end
 if now<rss.next_change then return false end
 rss.next_change=now+180
 local count=#(rss.items or {})
 if count<2 then return false end
 rss.home_index=(rss.home_index or 1)%count+1
 return true
end
return N
