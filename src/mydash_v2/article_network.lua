local U=require('util');local A=require('article')
local request=arg[1] or '';assert(request:match('^%d+%-%d+$'),'Invalid request id')
local requestpath=U.root..'/cache/article-request.'..request..'.json'
local resultpath=U.root..'/cache/article-result.'..request..'.json'
local item=U.load(requestpath,{});local tempfile=U.root..'/cache/article-download.'..request..'.tmp'
local function publish(path,bytes)
 local temporary=path..'.'..request..'.pending'
 assert(U.write(temporary,bytes));assert(os.rename(temporary,path))
end
local function run()
 assert(type(item.title)=='string' and item.title~='','资讯标题缺失')
 U.exec('mkdir -p '..U.quote('/mnt/us/RSS'))
 local id=A.id(item);local book='/mnt/us/RSS/'..id..'.epub';local metapath='/mnt/us/RSS/'..id..'.json'
 local meta=U.load(metapath,{})
 if meta.link==item.link and meta.status and U.read(book) then
  U.save(resultpath,{id=request,article_id=id,status=meta.status,cached=true});return
 end
 local ready=A.feed_book(item)
 local clean,status
 if ready then status='feed'
 elseif U.validurl(item.link) then
  local ok=U.exec('curl --fail --silent --show-error --compressed --location --user-agent "Mozilla/5.0" --proto "=http,https" --proto-redir "=http,https" --connect-timeout 5 --max-time 18 --max-filesize 2097152 -o '..U.quote(tempfile)..' '..U.quote(item.link)..' 2>>'..U.quote(U.root..'/network.log'))
  local html=U.read(tempfile)
  if ok and html and #html<=2097152 then clean=A.public_body(html);if clean then status='public' end end
 end
 if not ready and not clean then
  clean=A.summary(item);status=(item.content_kind=='feed' and not item.truncated) and 'feed' or 'summary'
 end
 assert(ready or (clean and #U.utf8(U.plain(clean))>=8),'未取得可阅读内容，请更新订阅后重试')
 local epub=ready or A.epub(item,clean,status)
 if U.read(book)~=epub then publish(book,epub) end
 publish(metapath,U.json.encode({link=item.link,title=item.title,source=item.source,status=status,time=os.time()},{indent=true}))
 assert(U.save(resultpath,{id=request,article_id=id,status=status}))
end
local ok,err=xpcall(run,debug.traceback)
os.remove(tempfile);os.remove(requestpath)
if not ok then U.save(resultpath,{id=request,error='正文准备失败，请检查网络后重试'});io.stderr:write(tostring(err)..'\n') end
