local U=require('util');local M=require('markets');local S={}
local aliases={SGE_AU9999='国内黄金 上金所 au9999 au99.99 sge gold huangjin gnhj',XAU='国际黄金 xau gold huangjin gjhj',XAG='国际白银 xag silver baiyin gjby',sh000001='上证指数 shangzheng szzs',sh000300='沪深300 hushen hs300',sz399001='深证成指 shenzhen szcz',sz399006='创业板 chuangyeban cyb',sh000016='上证50 shangzheng sz50',sh518880='黄金ETF huangjin hj etf gold'}
function S.local_results(query)
 aliases.usIXIC='纳斯达克 纳指 综合指数 nasdaq nasidake nsdk ixic .ixic'
 query=query:lower():gsub('%s+','');local rows={}
 for _,v in ipairs(M.presets) do local text=(v.name..' '..v.symbol..' '..(aliases[v.symbol] or '')):lower()
  if query~='' and text:find(query,1,true) then rows[#rows+1]={symbol=v.symbol,name=v.name} end
 end
 return rows
end
function S.parse(raw)
 if type(raw)~='string' then return nil end
 local quoted=raw:match('v_hint%s*=%s*(".-")%s*;?%s*$');if not quoted then return nil end
 local payload=U.json.decode(quoted);if type(payload)~='string' then return nil end
 local rows={};local seen={}
 for row in (payload..'^'):gmatch('(.-)%^') do local f={};for part in (row..'~'):gmatch('(.-)~') do f[#f+1]=part end
  local symbol=(f[1] or '')..(f[2] or '')
  if M.valid(symbol) and not seen[symbol] and f[3] and f[3]~='' then
   local name=f[3];if table.concat(U.utf8(name))~=name then name=M.decode_gbk(name) end
   if name then rows[#rows+1]={symbol=symbol,name=name};seen[symbol]=true end
  end
 end
 return rows
end
function S.merge(a,b,filter)
 local rows={};local seen={};for _,group in ipairs({a,b}) do for _,v in ipairs(group or {}) do
  if not seen[v.symbol] and (not filter or filter==v.symbol) then rows[#rows+1]=v;seen[v.symbol]=true end
  if #rows>=12 then return rows end
 end end;return rows
end
function S.remote_query(q)
 if q:lower():match('^s[hz]%d%d%d%d%d%d$') then return q:sub(3),q:lower() end
 return q,nil
end
return S
