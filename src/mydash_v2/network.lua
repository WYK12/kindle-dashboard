local U=require('util');local N=require('news');local cfg=U.config()
local function fetch(url)
 if not U.validurl(url) then return nil,'网址格式错误' end
 local path=U.root..'/cache/download.tmp'
 local ok=U.exec('curl --fail --silent --show-error --compressed --location --user-agent "Mozilla/5.0" --proto "=http,https" --proto-redir "=http,https" --connect-timeout 6 --max-time 18 --max-filesize 1048576 -o '..U.quote(path)..' '..U.quote(url)..' 2>>'..U.quote(U.root..'/network.log'))
 local s=U.read(path);os.remove(path);if ok and s and #s<=1048576 then return s end
 return nil,'网络暂不可用，保留缓存'
end
local function run()
 if arg[1]=='search' then
  local s,e=fetch('https://geocoding-api.open-meteo.com/v1/search?name='..U.url(arg[2] or '')..'&count=6&language=zh&format=json')
  local t=s and U.json.decode(s);U.save(U.root..'/cache/cities.json',{results=t and t.results or {},error=e,time=os.time()});return
 end
 local status={time=os.time(),errors={}}
 if arg[1]~='hotspots' then
 local city=cfg.city
 local url='https://api.open-meteo.com/v1/forecast?latitude='..tonumber(city.latitude)..'&longitude='..tonumber(city.longitude)..'&current=temperature_2m,relative_humidity_2m,weather_code&hourly=temperature_2m,weather_code,precipitation_probability,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max&timezone=Asia%2FShanghai&forecast_days=7'
 local s,e=fetch(url);local t=s and U.json.decode(s)
 if t and t.current then U.save(U.root..'/cache/weather.json',{city=city.name,time=os.time(),data=t}) else status.errors[#status.errors+1]='天气：'..(e or '数据格式异常') end
 if arg[1]=='weather' then U.save(U.root..'/cache/status.json',status);return end
 end
 local previous=U.load(U.root..'/cache/hotspots.json',{items={},sources={}});local sources={};local updated=0
 for _,source in ipairs(N.sources) do
  local body,err=fetch(source.url);local rows=body and N.parse(source,body) or {}
  if #rows>0 then sources[source.url]={items=rows,time=os.time()}
  else sources[source.url]=previous.sources and previous.sources[source.url];status.errors[#status.errors+1]=source.name..'：'..(err or '热榜暂不可用，保留缓存') end
  updated=math.max(updated,sources[source.url] and sources[source.url].time or 0)
 end
 U.save(U.root..'/cache/hotspots.json',{items=N.merge(N.sources,sources),sources=sources,time=updated>0 and updated or nil})
 U.save(U.root..'/cache/status.json',status)
end
local ok,err=xpcall(run,debug.traceback)
if not ok then U.save(U.root..'/cache/status.json',{time=os.time(),errors={tostring(err)}}) end
