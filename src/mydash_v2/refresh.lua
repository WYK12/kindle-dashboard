local U=require('util')
local F={names={'weather','hotspots','markets'}}
function F.periods(cfg,markets)
 return {weather=math.max(30,tonumber(cfg.refresh_minutes) or 60)*60,hotspots=600,markets=math.max(5,tonumber(markets.interval) or 5)*60}
end
local function align(t)return math.ceil(t/300)*300 end
function F.state(saved,periods,times,now)
 saved=saved or {};saved.jobs=saved.jobs or {}
 for _,name in ipairs(F.names)do
  local job=saved.jobs[name]
  if not job then
   local last=math.min(tonumber(times[name]) or 0,now)
   job={due=last>0 and align(last+periods[name]) or 0,failures=0};saved.jobs[name]=job
  elseif job.period~=periods[name] then
   job.due=align(math.min(job.attempt or 0,now)+periods[name]);job.failures=0
  end
  job.period=periods[name]
 end
 return saved
end
function F.next(state)
 local next=math.huge
 for _,name in ipairs(F.names)do next=math.min(next,state.jobs[name].due or 0)end
 return next
end
function F.complete(job,now,errors)
 job.attempt=now;job.errors=errors or {}
 job.failures=#job.errors>0 and math.min((job.failures or 0)+1,6) or 0
 local delay=math.min(job.period*2^job.failures,math.max(3600,job.period))
 job.due=align(now+delay)
end
local function equal(a,b,skip)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a)do if not(skip and skip[k]) and not equal(v,b[k],skip)then return false end end
 for k in pairs(b)do if not(skip and skip[k]) and a[k]==nil then return false end end
 return true
end
function F.same(kind,a,b)
 a=a or {};b=b or {}
 if kind=='weather' then return a.city==b.city and equal(a.data,b.data) end
 if kind=='hotspots' then return equal(a.items or {},b.items or {}) end
 return equal(a.quotes or {},b.quotes or {},{fetched_at=true})
end
function F.run(mode)
 local force={};for name in (mode or 'auto'):gmatch('[^,]+')do force[name]=true end
 local cfg=U.config();local markets=require('markets').config();local now=os.time()
 local state=F.state(U.load(U.root..'/cache/refresh-state.json',{}),F.periods(cfg,markets),{
  weather=U.load(U.root..'/cache/weather.json',{}).time,
  hotspots=U.load(U.root..'/cache/hotspots.json',{}).time,
  markets=U.load(U.root..'/cache/markets.json',{}).time,
 },now)
 local attempted={};local previousArg=arg
 for _,name in ipairs(F.names)do
  local job=state.jobs[name]
  if force.update or force[name] or os.time()>=(job.due or 0) then
   local ok,result=pcall(function()
    if name=='markets' then
     dofile(U.root..'/market_network.lua')
     return U.load(U.root..'/cache/markets.json',{}).errors or {}
    end
    arg={name,'batch'}
    return (dofile(U.root..'/network.lua') or {}).errors or {'更新没有返回结果'}
   end)
   arg=previousArg
   F.complete(job,os.time(),ok and result or {tostring(result)})
   attempted[#attempted+1]=name
  end
 end
 if #attempted>0 then
  state.time=os.time();assert(U.save(U.root..'/cache/refresh-state.json',state))
  local errors={}
  for _,name in ipairs(F.names)do for _,message in ipairs(state.jobs[name].errors or {})do errors[#errors+1]=message end end
  assert(U.save(U.root..'/cache/status.json',{time=state.time,errors=errors,attempted=attempted}))
 end
 return attempted,state
end
if arg and arg[0] and arg[0]:match('/refresh%.lua$') then F.run(arg[1] or 'auto')end
return F
