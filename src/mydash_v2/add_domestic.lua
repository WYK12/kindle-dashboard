local U=require('util');local M=require('markets');local cfg=M.config()
for _,v in ipairs(cfg.watchlist) do if v.symbol=='SGE_AU9999' then print('Domestic gold already selected');return end end
if #cfg.watchlist>=12 then print('Watchlist full: domestic gold available in presets');return end
table.insert(cfg.watchlist,1,{symbol='SGE_AU9999',name='国内黄金 Au99.99'})
assert(U.save(U.root..'/markets_config.json',cfg));print('Domestic gold added; other selections retained')
