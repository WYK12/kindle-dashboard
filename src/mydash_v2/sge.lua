local U=require('util');local S={}
local function clean(html) return (html:gsub('<!%-%-.-%-%->','')) end
local function cells(row)
 local f={};for value in row:gmatch('<td[^>]*>(.-)</td>') do f[#f+1]=U.plain(value) end;return f
end
local function dateinfo(date)
 local y,m,d=date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$');if not y then return nil end
 local t=os.time{year=tonumber(y),month=tonumber(m),day=tonumber(d),hour=0,min=0,sec=0,isdst=false}
 return os.date('%Y-%m-%d',t)==date and t or nil
end
function S.delayed(html,now)
 if type(html)~='string' then return nil end
 html=clean(html);local title=U.plain(html:match('<h1[^>]*>(.-)</h1>'))
 local y,m,d=title:match('(%d%d%d%d)年(%d%d?)月(%d%d?)日')
 if not y then return nil end
 local date=string.format('%04d-%02d-%02d',tonumber(y),tonumber(m),tonumber(d));local at=dateinfo(date)
 if not at or date>os.date('%Y-%m-%d',now) then return nil end
 for row in html:gmatch('<tr[^>]*>(.-)</tr>') do local f=cells(row)
  if f[1]=='Au99.99' then local price=tonumber(f[2]);if not price or price<=0 then return nil end
   return {symbol='SGE_AU9999',name='国内黄金 Au99.99',price=price,unit='元/克',source='上金所',kind='sge_delayed',quote_date=date,quote_at=at,fetched_at=now}
  end
 end
end
function S.daily(html,now)
 if type(html)~='string' then return nil end
 local best;html=clean(html)
 for row in html:gmatch('<tr[^>]*>(.-)</tr>') do local f=cells(row)
  if f[2]=='Au99.99' then local at=dateinfo(f[1] or '');local price=tonumber(f[6]);local percent=f[8] and tonumber((f[8]:gsub('%%','')))
   if at and f[1]<=os.date('%Y-%m-%d',now) and price and price>0 and (not best or f[1]>best.quote_date) then
    best={symbol='SGE_AU9999',name='国内黄金 Au99.99',price=price,unit='元/克',source='上金所',kind='sge_daily',quote_date=f[1],quote_at=at,fetched_at=now,change=tonumber(f[7]),percent=percent}
   end
  end
 end
 return best
end
return S
