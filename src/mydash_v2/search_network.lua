local U=require('util');local S=require('stock_search');local M=require('markets')
local query,id=arg[1] or '',arg[2] or ''
assert(id:match('^[%w%-]+$') and #id<=80,'Invalid request identifier')
local resultpath=U.root..'/cache/search-result.'..id..'.json'
local tmp=U.root..'/cache/search-download.'..id..'.tmp'
local function run()
 assert(#query>0 and #query<=160 and not query:find('[%z\1-\31]'),'Invalid query')
 local localrows=S.local_results(query);local remote,filter=S.remote_query(query);local rows={};local err
 local normalized=M.normalize(query)
 if normalized~='SGE_AU9999' and normalized~='XAU' and normalized~='XAG' then
  local url='https://smartbox.gtimg.cn/s3/?q='..U.url(remote)..'&t=all'
  local ok=U.exec('curl --fail --silent --show-error --compressed --location --proto "=https" --proto-redir "=https" --connect-timeout 6 --max-time 12 --max-filesize 65536 -o '..U.quote(tmp)..' '..U.quote(url)..' 2>>'..U.quote(U.root..'/search.log'))
  local body=ok and U.read(tmp);rows=body and S.parse(body)
  if not rows then rows={};err='网络搜索失败，请重试' end
 end
 U.save(resultpath,{id=id,query=query,results=S.merge(localrows,rows,filter),error=err,time=os.time()})
end
local ok,err=xpcall(run,debug.traceback);os.remove(tmp)
if not ok then U.save(resultpath,{id=id,query=query,results={},error='搜索异常，请重试',time=os.time()});io.stderr:write(err..'\n') end
