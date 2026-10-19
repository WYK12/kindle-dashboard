local U=require('util')
local M={}
M.defaults={interval=5,watchlist={{symbol='SGE_AU9999',name='国内黄金 Au99.99'},{symbol='XAU',name='国际黄金'},{symbol='XAG',name='国际白银'},{symbol='sh000001',name='上证指数'},{symbol='sh000300',name='沪深300'}}}
M.presets={{symbol='SGE_AU9999',name='国内黄金'},{symbol='XAU',name='国际黄金'},{symbol='XAG',name='国际白银'},{symbol='sh000001',name='上证指数'},{symbol='sh000300',name='沪深300'},{symbol='sz399001',name='深证成指'},{symbol='sz399006',name='创业板指'},{symbol='sh000016',name='上证50'},{symbol='sh518880',name='黄金ETF'}}
function M.config() return U.load(U.root..'/markets_config.json',M.defaults) end
function M.move(watchlist,index,step)
 local target=index+step
 if not watchlist[index] or not watchlist[target] then return nil end
 watchlist[index],watchlist[target]=watchlist[target],watchlist[index]
 return target
end
M.presets[#M.presets+1]={symbol='usIXIC',name='纳斯达克综合指数'}
function M.valid(s) return s=='SGE_AU9999' or s=='XAU' or s=='XAG' or s=='usIXIC' or (type(s)=='string' and s:match('^[s][hz]%d%d%d%d%d%d$')) end
function M.normalize(s)
 s=(s or ''):gsub('%s',''):lower()
 if s=='xau' or s=='gold' then return 'XAU' elseif s=='xag' or s=='silver' then return 'XAG' end
 if s=='sge_au9999' or s=='au9999' or s=='au99.99' then return 'SGE_AU9999' end
 if s=='usixic' or s=='ixic' or s=='.ixic' or s=='nasdaq' or s=='纳斯达克' or s=='纳指' then return 'usIXIC' end
 if s:match('^%d%d%d%d%d%d$') then s=(s:match('^[569]') and 'sh' or 'sz')..s end
 return M.valid(s) and s or nil
end
local gbkmap
function M.decode_gbk(s)
 gbkmap=gbkmap or U.read(U.root..'/gbk.map');if not gbkmap then return nil end
 local out={};local i=1
 while i<=#s do local a=s:byte(i)
  if a<128 then out[#out+1]=string.char(a);i=i+1
  else local b=s:byte(i+1)
   if not b or a<129 or a>254 or b<64 or b>254 or b==127 then return nil end
   local index=(a-129)*190+(b-64)-(b>127 and 1 or 0);local c=gbkmap:sub(index*3+1,index*3+3):gsub('%z','')
   if c=='' then return nil end;out[#out+1]=c;i=i+2
  end
 end
 return table.concat(out)
end
function M.epoch(s,utc)
 local y,mo,d,h,mi,se=s:match('^(%d%d%d%d)[%-/]?(%d%d)[%-/]?(%d%d)[T ]?(%d%d):?(%d%d):?(%d%d)')
 if not y then return nil end
 local t=os.time{year=tonumber(y),month=tonumber(mo),day=tonumber(d),hour=tonumber(h),min=tonumber(mi),sec=tonumber(se),isdst=false}
 if utc then t=t+os.difftime(t,os.time(os.date('!*t',t))) end
 return t
end
function M.gold(t,symbol,now)
 if type(t)~='table' or t.symbol~=symbol or not tonumber(t.price) or tonumber(t.price)<=0 or type(t.updatedAt)~='string' or t.currency~='USD' then return nil end
 local timestamp=M.epoch(t.updatedAt,true);if not timestamp then return nil end
 return {symbol=symbol,price=tonumber(t.price),unit='美元/盎司',source='Gold API',quote_at=timestamp,fetched_at=now}
end
function M.tencent(raw,symbol,now)
 local body=raw:match('v_'..symbol..'="(.-)"');if not body then return nil end
 local f={};for v in (body..'~'):gmatch('(.-)~') do f[#f+1]=v end
 local us=symbol=='usIXIC'
 local price,previous=tonumber(f[4]),tonumber(f[5]);local t=f[31] and (us and M.new_york_epoch(f[31]) or M.epoch(f[31],false))
 if not price or price<=0 or not previous or previous<=0 or not t or f[3]~=(us and '.IXIC' or symbol:sub(3)) then return nil end
 local isindex=us or body:find('~ZS~',1,true)~=nil
 return {symbol=symbol,name=us and '纳斯达克综合指数' or (M.decode_gbk(f[2]) or symbol),price=price,previous=previous,change=price-previous,percent=(price/previous-1)*100,unit=isindex and '点' or '人民币',source='腾讯行情',quote_at=t,fetched_at=now,quote_timezone=us and 'America/New_York' or nil}
end
function M.new_york_epoch(s)
 local year,month,day,hour=s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):')
 if not year then return nil end
 year,month,day,hour=tonumber(year),tonumber(month),tonumber(day),tonumber(hour)
 local function sunday(m,n)
  local w=tonumber(os.date('%w',os.time{year=year,month=m,day=1,hour=12}))
  return 1+(7-w)%7+(n-1)*7
 end
 local dst=month>3 and month<11
 if month==3 then local d=sunday(3,2);dst=day>d or (day==d and hour>=2)
 elseif month==11 then local d=sunday(11,1);dst=day<d or (day==d and hour<2) end
 local epoch=M.epoch(s,true);return epoch and epoch+(dst and 4 or 5)*3600 or nil
end
function M.state(q,now,interval)
 if not q then return '未获取' end
 if q.error then return '更新失败·缓存' end
 if now-q.fetched_at>math.max(900,(interval or 5)*180) then return '缓存' end
 if q.kind=='sge_daily' then return '每日收盘' end
 if q.kind=='sge_delayed' then return q.quote_date==os.date('%Y-%m-%d',now) and '延时行情' or '历史延时' end
 if not q.quote_at or now-q.quote_at>900 then return '历史快照' end
 return '报价'
end
return M
