local U=require('util');local F=require('refresh')
local function clone(v)return U.json.decode(U.json.encode(v))end
local a={time=1,quotes={x={price=12,quote_at=100,fetched_at=1}}};local b=clone(a)
b.time=2;b.quotes.x.fetched_at=2;assert(F.same('markets',a,b))
b.quotes.x.price=13;assert(not F.same('markets',a,b));b=clone(a)
b.quotes.x.quote_at=101;assert(not F.same('markets',a,b));b=clone(a)
b.quotes.x.error='failed';assert(not F.same('markets',a,b))
a={city='南京',time=1,data={current={temperature_2m=20},daily={time={'2026-10-20'}}}};b=clone(a)
b.time=2;assert(F.same('weather',a,b));b.data.daily.time[1]='2026-10-21';assert(not F.same('weather',a,b))
a={time=1,items={{title='标题',link='https://example.com',source='虎嗅'}}};b=clone(a)
b.time=2;b.home_index=2;assert(F.same('hotspots',a,b));b.items[1].title='新标题';assert(not F.same('hotspots',a,b))
local now=1800;local time,dofileReal=os.time,dofile
os.time=function()return now end
local cache={};local calls={};local failed={};local saved=0
U.config=function()return {refresh_minutes=30}end
package.loaded.markets={config=function()return {interval=5}end}
U.load=function(path,default)return clone(cache[path:match('([^/]+)$')] or default)end
U.save=function(path,value)cache[path:match('([^/]+)$')]=clone(value);saved=saved+1;return true end
dofile=function(path)
 if path==U.root..'/market_network.lua' then
  calls[#calls+1]='markets';cache['markets.json']={time=now,quotes={},errors=failed.markets and {'markets failed'} or {}}
 elseif path==U.root..'/network.lua' then
  local name=arg[1];assert(arg[2]=='batch');calls[#calls+1]=name
  cache[name=='weather' and 'weather.json' or 'hotspots.json']={time=now}
  return {errors=failed[name] and {name..' failed'} or {}}
 else return dofileReal(path)end
end
local function run(mode)
 calls={};local attempted,state=F.run(mode or 'auto');assert(#attempted==#calls)
 return table.concat(calls,','),state
end
local names,state=run();assert(names=='weather,hotspots,markets')
assert(state.jobs.weather.due==3600 and state.jobs.hotspots.due==2400 and state.jobs.markets.due==2100)
local writes=saved;assert(run()=='');assert(saved==writes,'Not due must not request or publish')
now=2100;assert(run()=='markets')
now=2400;assert(run()=='hotspots,markets')
now=3600;assert(run()=='weather,hotspots,markets')
failed.markets=true;now=3900;names,state=run();assert(names=='markets' and state.jobs.markets.failures==1 and state.jobs.markets.due==4500)
now=4200;assert(run()=='hotspots','A failing category must not delay healthy categories')
now=4500;names,state=run();assert(names=='markets' and state.jobs.markets.failures==2 and state.jobs.markets.due==5700)
local resumed=F.state(clone(state),F.periods({refresh_minutes=30},{interval=5}),{},now)
assert(resumed.jobs.markets.due==5700 and resumed.jobs.markets.failures==2,'Restart must preserve backoff')
failed.markets=nil;now=4501;names,state=run('markets')
assert(names=='markets' and state.jobs.markets.failures==0 and state.jobs.markets.due==5100,'Manual refresh must bypass and reset backoff')
local job={period=300,failures=0}
for i=1,10 do F.complete(job,0,{'failed'});assert(job.due<=3600)end
assert(job.due==3600)
F.complete(job,0,{});assert(job.due==300 and job.failures==0)
assert(F.next(state)%300==0,'All automatic updates must share five-minute slots')
now=4502;names,state=run('auto,weather,markets');assert(names=='weather,markets','Queued manual requests must coalesce without being lost')
local changed=F.state(clone(state),F.periods({refresh_minutes=60},{interval=5}),{},now)
assert(changed.jobs.weather.period==3600 and changed.jobs.weather.due==8400)
os.time,dofile=time,dofileReal
print('PASS: semantic cache equality, shared cadence, due-only jobs, outage backoff, healthy-job isolation, restart, manual retry and recovery')
