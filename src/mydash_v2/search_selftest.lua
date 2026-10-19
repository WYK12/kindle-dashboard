local U=require('util');local S=require('stock_search')
for _,name in ipairs({'home','render','stock_search','search_network'}) do assert(loadfile(U.root..'/'..name..'.lua')) end
local raw=[[v_hint="sh~600519~\u8d35\u5dde\u8305\u53f0~gzmt~GP-A^hk~01787~\u5c71\u4e1c\u9ec4\u91d1~sdhj~GP^sz~159934~\u9ec4\u91d1ETF~hjetf~ETF"]]
local rows=assert(S.parse(raw));assert(#rows==2 and rows[1].name=='贵州茅台' and rows[1].symbol=='sh600519' and rows[2].symbol=='sz159934')
assert(#S.parse('v_hint=""')==0);assert(S.parse('arbitrary script')==nil)
assert(#S.merge(rows,rows)==2);assert(#S.merge(rows,{},'sh600519')==1)
local q,filter=S.remote_query('sh600519');assert(q=='600519' and filter=='sh600519')
local found={};for _,v in ipairs(S.local_results('huangjin')) do found[v.symbol]=true end
assert(found.SGE_AU9999 and found.XAU and found.sh518880 and not found.XAG)
print('SEARCH_SELFTEST_OK: Unicode names, supported exchanges, malformed/empty responses, deduplication, exact code filter, local gold aliases')
