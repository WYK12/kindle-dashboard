local U=require('util');local S=require('sge');local M=require('markets')
assert(loadfile(U.root..'/sge.lua'));assert(loadfile(U.root..'/market_network.lua'));assert(loadfile(U.root..'/home.lua'))
local now=os.time{year=2026,month=10,day=18,hour=21,min=0,sec=0}
local function delayed(price) return '<h1>上海黄金交易所2026年10月18日延时行情</h1><table><tr><td>iAu99.99</td><td>9999</td></tr><tr><td>Au99.99</td><td>'..price..'</td><td>910</td></tr></table>' end
assert(S.delayed(delayed('0.0'),now)==nil)
local q=assert(S.delayed(delayed('900.50'),now));assert(q.price==900.50 and q.unit=='元/克' and q.quote_date=='2026-10-18' and q.percent==nil)
assert(M.state(q,now,5)=='延时行情')
local function row(date,contract,close,percent) return '<tr><!-- <td>99</td> --><td>'..date..'</td><td>'..contract..'</td><td>893.99</td><td>902.00</td><td>893.00</td><td>'..close..'</td><td>8.61</td><td>'..percent..'</td></tr>' end
local html='<table>'..row('2026-10-15','Au99.99','892.96','-0.96%')..row('2026-10-16','iAu99.99','9999','0%')..row('2026-10-16','Au99.99','901.57','0.96%')..row('2026-10-19','Au99.99','9999','0%')..'</table>'
q=assert(S.daily(html,now));assert(q.price==901.57 and q.quote_date=='2026-10-16' and q.percent==0.96 and q.change==8.61 and q.kind=='sge_daily')
assert(os.date('%H:%M',q.quote_at)=='00:00' and M.state(q,now,5)=='每日收盘')
assert(not S.daily(row('2026-10-16','Au99.99','0','0%'),now))
assert(not S.daily(row('2026-02-31','Au99.99','900','0%'),now))
assert(M.normalize('Au99.99')=='SGE_AU9999' and M.normalize('au9999')=='SGE_AU9999')
print('SGE_SELFTEST_OK: reject zero/future/invalid date, exact Au99.99, daily close, percent, source date only, aliases')
