local U=require('util');local M=require('markets');local S=require('sge');local cfg=M.config()
local cache=U.load(U.root..'/cache/markets.json',{quotes={}});cache.quotes=cache.quotes or {}
local now=os.time();local errors={}
local function fetch(url,timeout)
 local path=U.root..'/cache/market-download.tmp'
 local ok=U.exec('curl --fail --silent --show-error --compressed --location --proto "=https" --proto-redir "=https" --connect-timeout 8 --max-time '..(timeout or 16)..' --max-filesize 262144 -o '..U.quote(path)..' '..U.quote(url)..' 2>>'..U.quote(U.root..'/markets.log'))
 local s=ok and U.read(path);os.remove(path);os.remove(U.root..'/cache/market-download.tmp')
 return s and #s<=262144 and s or nil
end
local function update(symbol,q)
 if q then cache.quotes[symbol]=q
 else if cache.quotes[symbol] then cache.quotes[symbol].error='下载或数据校验失败' end;errors[#errors+1]=symbol end
end
local function run()
 local chinese={};local seen={};local domestic=false
 for i,item in ipairs(cfg.watchlist or {}) do
  local s=item.symbol
  if i<=12 and M.valid(s) and not seen[s] then
   seen[s]=true
   if s=='SGE_AU9999' then domestic=true
   elseif s=='XAU' or s=='XAG' then local body=fetch('https://api.gold-api.com/price/'..s);local json=body and U.json.decode(body);update(s,M.gold(json,s,now))
   else chinese[#chinese+1]=s end
  end
 end
 if #chinese>0 then local body=fetch('https://qt.gtimg.cn/q='..table.concat(chinese,','))
  for _,s in ipairs(chinese) do update(s,body and M.tencent(body,s,now)) end
 end
 if domestic then
  local delayed=fetch('https://www.sge.com.cn/h5_sjzx/yshq',25)
  local q=delayed and S.delayed(delayed,os.time())
  if not q or q.quote_date~=os.date('%Y-%m-%d') then
   local url='https://www.sge.com.cn/sjzx/quotation_daily_new?start_date='..os.date('%Y-%m-%d',os.time()-45*86400)..'&end_date='..os.date('%Y-%m-%d')..'&inst_ids=Au99.99'
   local daily=fetch(url,25);local close=daily and S.daily(daily,os.time())
   if close and (not q or close.quote_date>=q.quote_date) then q=close end
  end
  update('SGE_AU9999',q)
 end
 cache.time=os.time();cache.errors=errors;assert(U.save(U.root..'/cache/markets.json',cache))
end
local ok,err=xpcall(run,debug.traceback)
if not ok then cache.time=os.time();cache.errors={tostring(err)};U.save(U.root..'/cache/markets.json',cache) end
