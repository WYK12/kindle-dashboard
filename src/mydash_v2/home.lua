local P=require('pinyin')
local U=require('util');local R=require('render');local ffi=require('ffi');local M=require('markets');local A=require('article');local N=require('news');local C=require('calendar');local L=require('reading');local F=require('refresh')
ffi.cdef[[
struct input_event { long sec; long usec; unsigned short type; unsigned short code; int value; };
int open(const char*,int,...); int read(int,void*,unsigned int); int close(int);
int ioctl(int,unsigned long,...); int usleep(unsigned int); int getpid(void);

struct input_absinfo { int value,minimum,maximum,fuzz,flat,resolution; };
]]
local cfg=U.config();local page='home';local running=true;local fd=-1;local grabbed=false
local todos=U.load(U.root..'/todos.json',{});local rss={items={}};local weather={};local status={}
local notice='';local listpage=1;local selected=nil;local draft='';local inputkind='';local keyboardUpper=false
local articleRequest='';local articleStarted=0;local articleError=''
local hourpage=1
local hotBoard='all'
local keyboardPinyin=false;local candidatePage=1;local homeClockDirty=false;local lastHomeDate=''
local cityresults={};local lastCities='';local lastMinute='';local asleep=false;local nextPower=0;local nextRefresh=0;local lastCache='';local redraw=true;local full=true
local marketcfg=M.config();local marketcache=U.load(U.root..'/cache/markets.json',{quotes={}});local lastMarket='';local marketpage=1
local refreshstate;local lastRefresh='';local manualPending=false
local keyboardDirty=false;local keyboardCaseDirty=false;local keyboardNotice='';local nextActivity=0;local nextCache=0
local stockquery='';local stockresults={};local stockrequest='';local stockpending=false;local stockStarted=0;local stockresultpage=1;local stockerror=''
local ev=ffi.new('struct input_event[1]');local size=ffi.sizeof(ev[0]);assert(size==16,'仅支持 ARMv7 32 位 input_event')
local ts=ffi.new('struct timespec[1]')
local function monotonic() ffi.C.clock_gettime(1,ts);return tonumber(ts[0].tv_sec)+tonumber(ts[0].tv_nsec)/1e9 end
local weekday={'日','一','二','三','四','五','六'}
local cities={{name='南京',latitude=32.06,longitude=118.79},{name='北京',latitude=39.90,longitude=116.41},{name='上海',latitude=31.23,longitude=121.47},{name='杭州',latitude=30.27,longitude=120.15},{name='苏州',latitude=31.30,longitude=120.58},{name='广州',latitude=23.13,longitude=113.26},{name='深圳',latitude=22.54,longitude=114.06},{name='成都',latitude=30.57,longitude=104.07},{name='武汉',latitude=30.59,longitude=114.31},{name='香港',latitude=22.32,longitude=114.17}}
local function readcache()
 local nextWeather=U.load(U.root..'/cache/weather.json',{});local nextRSS=U.load(U.root..'/cache/hotspots.json',{items={}})
 local weatherChanged=not F.same('weather',weather,nextWeather);local newsChanged=not F.same('hotspots',rss,nextRSS)
 weather=nextWeather;rss=N.replace(rss,nextRSS);status=U.load(U.root..'/cache/status.json',{})
 return weatherChanged,newsChanged
end
local function schedule(now)
 refreshstate=F.state(U.load(U.root..'/cache/refresh-state.json',{}),F.periods(cfg,marketcfg),{weather=weather.time,hotspots=rss.time,markets=marketcache.time},now)
 nextRefresh=F.next(refreshstate)
end
local powerd
do
 local ok,lib=pcall(require,'liblipclua')
 if ok then local opened,handle=pcall(lib.init,'com.wyk12.mydash.power');if opened then powerd=handle end end
end
local function lipc(prop)
 if powerd then
  local ok,value=pcall(function()
   if prop=='state' then return powerd:get_string_property('com.lab126.powerd',prop) end
   return powerd:get_int_property('com.lab126.powerd',prop)
  end)
  if ok and value~=nil then return tostring(value) end
 end
 return U.capture('lipc-get-prop com.lab126.powerd '..prop)
end
local lightfile='/sys/class/backlight/max77696-bl/brightness'
local function setlight(level)
 local ok=U.exec('lipc-set-prop com.lab126.powerd flIntensity '..level)
 if ok and level==0 then
  -- Like KOReader on PW3: the stock zero step still leaves the LEDs on.
  ok=U.exec("printf '0\\n' > "..U.quote(lightfile)) and tonumber(U.read(lightfile))==0
 end
 notice=ok and (level==0 and '背光已关闭' or '') or '亮度设置失败，请重试'
 redraw=true
end
local function network(mode,text)
 local script=mode=='search' and '/fetch.sh' or '/refresh.sh'
 local command='/bin/sh '..U.quote(U.root..script)..' '..U.quote(mode or 'update')..' '..U.quote(text or '')..' >/dev/null 2>&1 &'
 os.execute(command)
 if mode~='auto' then
  manualPending=mode~='search'
  if page~='keyboard' then notice='正在后台更新';redraw=true end
 end
end
local function savecfg() assert(U.save(U.root..'/config.json',cfg));nextRefresh=0 end
local function native(mode,value)
 return U.exec('/bin/sh '..U.quote(U.root..'/native_ui.sh')..' '..U.quote(mode)..' '..U.quote(value or '')..' >>'..U.quote(U.root..'/app.log')..' 2>&1')
end
local function release(keepNative)
 if not keepNative then native('show') end
 if fd>=0 then if grabbed then ffi.C.ioctl(fd,0x40044590,ffi.cast('int',0)) end ffi.C.close(fd) end fd=-1;grabbed=false
end
local function acquire()
 fd=ffi.C.open('/dev/input/event1',2048);assert(fd>=0,'无法打开触摸设备')
 if ffi.C.ioctl(fd,0x40044590,ffi.cast('int',1))~=0 then release();error('触摸设备正在被其他应用使用；首页未启动') end
 grabbed=true
 assert(native('hide'),'无法隐藏原生顶部栏，请查看 app.log')
 if not native('awake',cfg.keep_awake==false and '0' or '1') then notice='常显设置失败，请查看 app.log' end
end
local function coordinates()
 local a=ffi.new('struct input_absinfo[1]');local b=ffi.new('struct input_absinfo[1]')
 local ax=ffi.C.ioctl(fd,0x80184575,a)==0;local ay=ffi.C.ioctl(fd,0x80184576,b)==0
 return ax and tonumber(a[0].value) or nil,ay and tonumber(b[0].value) or nil
end
local function quit(action)
 local label=({bookstore='正在打开书库',reader='正在打开书籍',readarticle='正在打开文章',browser='正在打开浏览器'})[action]
 if label then R.begin('',nil,true);R.text(label,math.floor((R.width-976)/2),math.floor((R.height-100)/2),44,976,100);R.finish(false) end
 U.write(U.root..'/next_action',action or 'native');running=false
end
local function launchArticle(id)
 assert(id:match('^%x+$') and #id==24,'Invalid article id')
 U.write(U.root..'/reader_id',id)
 U.save(U.root..'/cache/reader-resume.json',{listpage=listpage,board=hotBoard})
 quit('readarticle')
end
local function openArticle(item)
 selected=item;articleError='';notice=''
 if item.content_kind=='hot_summary' then page='hotdetail';redraw=true;full=true;return end
 local id=A.id(item);local meta=U.load('/mnt/us/RSS/'..id..'.json',{})
 if meta.link==item.link and meta.status and U.read('/mnt/us/RSS/'..id..'.epub') then launchArticle(id);return end
 local book=A.feed_book(item)
 if book and U.write('/mnt/us/RSS/'..id..'.epub',book) and U.save('/mnt/us/RSS/'..id..'.json',{link=item.link,title=item.title,source=item.source,status='feed',time=os.time()}) then launchArticle(id);return end
 articleRequest=tostring(ffi.C.getpid())..'-'..tostring(math.floor(monotonic()*1000));articleStarted=os.time()
 assert(U.save(U.root..'/cache/article-request.'..articleRequest..'.json',item))
 os.execute('/bin/sh '..U.quote(U.root..'/article_fetch.sh')..' '..U.quote(articleRequest)..' >/dev/null 2>&1 &')
 page='preparearticle';redraw=true;full=true
end
local batteryCache;local batteryExpires=0
local function battery()if os.time()>=batteryExpires then local n=tonumber(lipc('battLevel'));batteryCache=n and (n..'%') or '--';batteryExpires=os.time()+30 end;return batteryCache end
local function wname(code)
 code=tonumber(code) or -1
 if code==0 then return '晴' elseif code<=3 and code>=0 then return '多云' elseif code==45 or code==48 then return '雾' elseif code>=51 and code<=67 then return '雨' elseif code>=71 and code<=77 then return '雪' elseif code>=80 and code<=82 then return '阵雨' elseif code>=85 and code<=86 then return '阵雪' elseif code>=95 then return '雷雨' end return '天气'
end
local function value(n,suffix)
 if type(n)~='number' then return '--' end
 return string.format('%.0f',n)..(suffix or '')
end
local function weatherupdated()
 return weather.time and ('更新 '..os.date('%m-%d %H:%M',weather.time)..'  ·  Open-Meteo') or '暂无天气缓存'
end
local function weatherupdate()network('weather')end
local function weatherline()
 if weather.city~=cfg.city.name or not weather.data then return cfg.city.name..'  尚无天气缓存' end
 local c=weather.data.current;return weather.city..'  '..tostring(c.temperature_2m)..'°C  '..wname(c.weather_code)
end
local function footer()
 local quiet=page=='home' and (notice=='更新完成' or notice=='行情已更新' or notice=='正在后台更新' or notice=='正在更新行情')
 if notice~='' and not quiet then R.text(U.short(notice,30),48,page=='home' and R.height-158 or R.height-66,32,R.width-96,page=='home' and 44 or 60,'bold') end
 if page=='home' then
  local path=L.last()
  local defs={{'书库','bookstore'},{'继续阅读',function()
   if not L.valid(path) then quit('bookstore');return end
   assert(U.write(U.root..'/reader_book',path));quit('reader')
  end},{'浏览器','browser'},{'待办','todos'},{'设置','settings'}}
  local x=80;local gap=(R.width-160-520)/4
  for _,b in ipairs(defs) do
   local width=#U.utf8(b[1])*40
   R.text(b[1],x,R.height-97,40,width+12,64,'bold')
   R.hitbox(x-32,R.height-116,width+64,94,b[2])
   x=x+width+gap
  end
 end
end
local function nav() page='home';notice='';redraw=true;full=true end
local function input(kind,value) inputkind=kind;draft=value or '';keyboardPinyin=kind~='feed';keyboardUpper=false;candidatePage=1;keyboardDirty=false;page='keyboard';redraw=true end
local function marketupdate()
 network('markets')
end
local function savemarkets(orderOnly) assert(U.save(U.root..'/markets_config.json',marketcfg));if not orderOnly then network('markets') end;redraw=true end
local function addmarket(symbol,name)
 for _,v in ipairs(marketcfg.watchlist) do if v.symbol==symbol then notice='已在自选中';return false end end
 if #marketcfg.watchlist>=12 then notice='最多添加 12 个品种';return false end
 marketcfg.watchlist[#marketcfg.watchlist+1]={symbol=symbol,name=name};savemarkets();return true
end
local function searchstocks(query)
 if stockrequest~='' then os.remove(U.root..'/cache/search-result.'..stockrequest..'.json') end
 stockquery=query;stockresults={};stockerror='';stockresultpage=1;stockpending=true;stockStarted=os.time()
 stockrequest=tostring(ffi.C.getpid())..'-'..tostring(math.floor(monotonic()*1000))
 os.execute('/bin/sh '..U.quote(U.root..'/search.sh')..' '..U.quote(query)..' '..U.quote(stockrequest)..' >/dev/null 2>&1 &')
 page='stockresults';redraw=true
end
local function inputtext()
 local chars=U.utf8(draft);return (#chars>120 and ('…'..table.concat(chars,'',#chars-118,#chars)) or draft)..'|'
end
local function keyboardLabel() return keyboardPinyin and '拼音' or keyboardUpper and 'ABC' or 'abc' end
function R.keyboardLayout()
 local wide=R.landscape
 return {width=R.width-96,inputY=wide and 158 or 195,inputH=wide and 130 or 240,hintY=wide and 310 or 470,
  candidatesY=wide and 360 or 520,candidateStep=wide and 228 or 164,candidateW=wide and 212 or 156,
  keyY=wide and 460 or 610,keyStepX=wide and 136 or 98,keyStepY=wide and 80 or 108,keyW=wide and 128 or 94,keyH=wide and 72 or 98,
  controlsY=wide and 910 or 1170,controlH=wide and 84 or 100,x=wide and {48,392,736,1080} or {48,284,520,756},w=wide and {320,320,320,320} or {220,220,220,268}}
end
local function candidates(register)
 local k=R.keyboardLayout();R.rect(48,k.candidatesY,k.width,78,false)
 local words=keyboardPinyin and P.lookup(draft) or {}
 candidatePage=math.max(1,math.min(candidatePage,math.max(1,math.ceil(#words/4))))
 for i=1,6 do
  local x=48+(i-1)*k.candidateStep;local index=i
  local text=i<=4 and (words[(candidatePage-1)*4+i] or '') or i==5 and (candidatePage>1 and '上组' or '') or (candidatePage*4<#words and '下组' or '')
  if keyboardPinyin then R.text(U.short(text,5),x+8,k.candidatesY+18,30,k.candidateW-8,48,'medium') end
  if register then R.hitbox(x,k.candidatesY,k.candidateW,78,function()
   if not keyboardPinyin then return end
   if index<=4 then draft=P.choose(draft,(candidatePage-1)*4+index);candidatePage=1
   elseif index==5 then candidatePage=math.max(1,candidatePage-1)
   else candidatePage=candidatePage+1 end
   keyboardDirty=true
  end) end
 end
end
local function drawInput()
 local k=R.keyboardLayout();local clearNotice=keyboardNotice~=notice
 R.partial();R.rect(48,k.inputY,k.width,k.inputH,false);R.text(inputtext(),48,k.inputY,35,k.width,k.inputH)
 candidates(false)
 if keyboardCaseDirty then
  R.rect(k.x[1]+3,k.controlsY+3,k.w[1]-6,k.controlH-6,false);R.text(keyboardLabel(),k.x[1]+20,k.controlsY+math.floor((k.controlH-48)/2),36,k.w[1]-40,58)
  R.rect(48,k.hintY,k.width,45,false);if keyboardPinyin then R.text('输入拼音，点选汉字',48,k.hintY,28,k.width,45,'medium') end
 end
 if clearNotice then R.rect(48,R.height-66,k.width,60,false);footer() end
 R.finish(false,{top=k.inputY,left=48,width=k.width,height=(clearNotice and R.height-6 or keyboardCaseDirty and k.controlsY+k.controlH or k.candidatesY+78)-k.inputY})
 keyboardDirty=false;keyboardCaseDirty=false;keyboardNotice=notice
end
local function wrapped(s,limit)
 local out={};local row='';local n=0
 for _,c in ipairs(U.utf8(s)) do local w=#c>1 and 2 or 1;if n+w>limit or c=='\n' then out[#out+1]=row;row='';n=0 end;if c~='\n' then row=row..c;n=n+w end end
 if row~='' then out[#out+1]=row end return out
end
local function drawSettings()
  local wide=R.landscape;local width=R.width-96
  R.begin('设置',nav,true)
  local function row(label,value,y,act)
   local x,w=48,976
   if wide then
    local slot=({[169]=0,[281]=1,[393]=2,[505]=3,[617]=4,[1090]=5})[y]
    x=48+(slot%2)*704;y=160+math.floor(slot/2)*140;w=648
   end
   R.text(label,x,y,30,wide and 330 or 500,50,'medium')
   R.text(value,wide and x+340 or 650,y,28,wide and 308 or 374,48,'medium')
   R.rect(x,y+76,w,2,true);R.hitbox(x,y-12,w,100,act)
  end
  row('城市',cfg.city.name,169,'cities')
  row('热点榜单','虎嗅 · 澎湃',281,'rss')
  row('天气更新间隔',cfg.refresh_minutes..' 分钟',393,function()local values={[30]=60,[60]=180,[180]=30};cfg.refresh_minutes=values[cfg.refresh_minutes] or 60;savecfg();redraw=true end)
  local enabled=not U.read(U.root..'/DISABLE_AUTOSTART') and U.read('/mnt/us/emergency.sh')
  row('开机自启',enabled and '开启' or '关闭',505,function()
   if enabled then U.write(U.root..'/DISABLE_AUTOSTART','disabled\n');notice='已关闭自启'
   else if U.exec('/bin/sh '..U.quote(U.root..'/autostart.sh')..' enable >>'..U.quote(U.root..'/app.log')..' 2>&1') then notice='已开启自启' else notice='自启入口被占用，请查看 app.log' end end;redraw=true
  end)
  row('首页常显',cfg.keep_awake==false and '关闭' or '开启',617,function()
   local enabled=cfg.keep_awake==false
   if native('awake',enabled and '1' or '0') then cfg.keep_awake=enabled;savecfg();notice=enabled and '首页常显已开启' or '已恢复自动休眠'
   else notice='常显设置失败，请查看 app.log' end;redraw=true
  end)
  local light=tonumber(lipc('flIntensity')) or 0
  local lightstatus=tonumber(U.read(lightfile))==0 and '已关闭' or light==0 and '最低亮度' or (tostring(light)..' / 24')
  R.text('背光',48,wide and 600 or 744,32,500,50)
  R.text(lightstatus,650,wide and 602 or 746,28,374,48,'medium')
  R.compact('减亮',48,wide and 680 or 822,wide and 428 or 308,66,function()setlight(math.max(0,light-2))end)
  R.compact('增亮',wide and 510 or 382,wide and 680 or 822,wide and 428 or 308,66,function()setlight(math.min(24,light+2))end)
  R.compact('关闭背光',wide and 972 or 716,wide and 680 or 822,wide and 428 or 308,66,function()setlight(0)end)
  R.rect(48,wide and 770 or 930,width,2,true)
  R.compact('清除残影',48,wide and 810 or 972,wide and 428 or 474,66,'refresh')
  R.compact('休眠',wide and 510 or 550,wide and 810 or 972,wide and 428 or 474,66,function()
   if not native('awake','0') then notice='无法恢复休眠，请查看 app.log';redraw=true;return end
   release();asleep=true;nextPower=os.time()+2
   U.exec('lipc-set-prop com.lab126.powerd powerButton 1');redraw=false
  end)
  row('看板方向',cfg.dashboard_landscape and '横屏' or '竖屏',1090,function()
   cfg.dashboard_landscape=not cfg.dashboard_landscape;savecfg();notice=cfg.dashboard_landscape and '已切换横屏' or '已切换竖屏';redraw=true;full=true
  end)
  R.compact('原生首页',wide and 972 or 48,wide and 810 or 1208,wide and 428 or 976,66,'native')

end
function R.drawHotspot(partial)
 local area=R.landscape and {left=976,top=372,width=424,height=512} or {left=48,top=1072,width=976,height=186}
 if partial then R.partial();R.rect(area.left,area.top,area.width,area.height,false) end
 local item=(rss.items or {})[rss.home_index or 1]
 local x,y,w,h=R.landscape and 1000 or 48,R.landscape and 548 or 1138,R.landscape and 400 or 976,R.landscape and 300 or 120
 if R.landscape then
  R.text('热点',1000,380,40,200,60,'bold');R.text('全部',1310,384,34,90,54,'bold')
  if item then R.text('综合 · '..N.label(item),1000,456,30,400,90,'bold') end
 else
  R.text('热点',48,1080,40,160,60,'bold')
  if item then R.text('综合 · '..N.label(item),228,1084,32,640,54,'bold') end
  R.text('全部',900,1084,34,124,54,'bold')
 end
 R.text(item and U.short(item.title,40) or '暂无热点，点击更新',x,y,40,w,h,'bold')
 if partial then R.finish(false,area)
 else
  R.hitbox(area.left,area.top,area.width,R.landscape and 170 or 66,'rss')
  R.hitbox(x,y,w,h,item and function()
   local current=(rss.items or {})[rss.home_index or 1];if current then openArticle(current) end
  end or 'rss')
 end
end
function R.drawLandscapeHome()
 local pending=0;for _,task in ipairs(todos)do if not task.done then pending=pending+1 end end
 R.begin('',nil,true)
 R.text(os.date('%Y年%m月%d日')..'  周'..weekday[tonumber(os.date('%w'))+1],48,28,34,960,54,'bold')
 R.hitbox(32,12,960,78,function()C.open();page='calendar';redraw=true end)
 R.text('电量 '..battery(),1176,28,34,224,54,'bold')
 R.text(os.date('%H:%M'),48,128,118,475,160,'bold')
 R.text('待办  '..pending,52,296,32,220,54,'bold');R.hitbox(48,290,240,62,'todos')
 R.text('刷新',350,296,32,150,54,'bold');R.hitbox(328,290,180,62,'refresh')
 R.rect(520,130,3,190,true)
 local data=weather.city==cfg.city.name and weather.data or nil
 local c=data and data.current;local daily=data and data.daily
 R.text(cfg.city.name..'  '..(c and wname(c.weather_code) or '天气'),568,126,36,832,58,'bold')
 R.text(c and (value(c.temperature_2m)..'°C') or '--°C',566,194,72,350,94,'bold')
 R.text(daily and (value((daily.temperature_2m_min or {})[1])..' ~ '..value((daily.temperature_2m_max or {})[1])..'°C') or '-- ~ --°C',940,194,32,300,50,'bold')
 R.text('预报',1276,194,32,124,50,'bold')
 R.text(weather.time and os.date('%m-%d %H:%M',weather.time) or '尚未更新',940,256,30,460,50,'bold')
 R.hitbox(544,116,856,214,'weather');R.rect(48,358,1352,2,true)
 R.text('自选行情',48,380,40,500,60,'bold');R.text('全部',810,384,34,124,54,'bold')
 for _,label in ipairs({{'品种',48,270},{'报价',340,298},{'涨跌',660,160},{'时间',830,104}})do R.text(label[1],label[2],450,30,label[3],50,'bold')end
 local shortnames={SGE_AU9999='国内黄金',usIXIC='纳斯达克综合'}
 for i=1,math.min(6,#marketcfg.watchlist)do
  local item=marketcfg.watchlist[i];local q=(marketcache.quotes or {})[item.symbol];local y=500+(i-1)*66
  R.text(U.short(shortnames[item.symbol] or item.name or item.symbol,6),48,y+8,40,270,64,'bold')
  local price=q and string.format('%.2f',q.price) or '--'
  if q then
   if item.symbol=='SGE_AU9999' then price='¥'..price..'/g'
   elseif item.symbol=='XAU' or item.symbol=='XAG' then price='$'..price..'/oz'
   elseif q.unit=='点' then price=price..'点' end
  end
  R.text(price,340,y+8,40,298,64,'bold')
  R.text(q and q.percent and string.format('%+.2f%%',q.percent) or '—',660,y+12,32,160,54,'bold')
  R.text(q and (q.quote_date and q.quote_date:sub(6) or q.quote_at and os.date('%m-%d',q.quote_at)) or '--',830,y,28,104,36,'bold')
  if q and not q.quote_date and q.quote_at then R.text(os.date('%H:%M',q.quote_at),830,y+34,28,104,36,'bold')end
 end
 if #marketcfg.watchlist==0 then R.text('添加自选',48,540,40,880,70,'bold')end
 R.hitbox(48,372,886,516,'markets');R.rect(952,380,2,500,true)
 R.drawHotspot(false);R.rect(48,904,1352,2,true)
end
local function draw()
 R.setLandscape(cfg.dashboard_landscape==true)
 local wide=R.landscape;local width=R.width-96
 if page=='home' and R.landscape then
  lastHomeDate=os.date('%Y-%m-%d');R.drawLandscapeHome()
 elseif page=='home' then
  lastHomeDate=os.date('%Y-%m-%d')
  local function text(s,x,y,size,w,h,bold) R.text(s,x,y,size,w,h,bold and 'bold' or 'medium') end
  local pending=0;for _,v in ipairs(todos) do if not v.done then pending=pending+1 end end
  R.begin('',nil,true)
  text(os.date('%Y年%m月%d日')..'  周'..weekday[tonumber(os.date('%w'))+1],48,28,34,720,54,true)
  R.hitbox(32,12,736,78,function()C.open();page='calendar';redraw=true end)
  text('电量 '..battery(),800,28,34,224,54,true)
  text(os.date('%H:%M'),48,128,118,475,160,true)
  text('待办  '..pending,52,310,34,220,54,true)
  R.hitbox(48,298,240,76,'todos')
  text('刷新',366,310,34,150,54,true)
  R.hitbox(340,298,180,76,'refresh')
  R.rect(554,130,3,250,true)
  local data=weather.city==cfg.city.name and weather.data or nil
  local c=data and data.current;local d=data and data.daily
  text(cfg.city.name..'  '..(c and wname(c.weather_code) or '天气'),600,126,36,424,58,true)
  text(c and (value(c.temperature_2m)..'°C') or '--°C',598,194,72,426,94,true)
  local range=d and (value((d.temperature_2m_min or {})[1])..' ~ '..value((d.temperature_2m_max or {})[1])..'°C') or '-- ~ --°C'
  text(range,600,294,32,290,50,true)
  text('预报',900,294,32,124,50,true)
  text(weather.time and os.date('%m-%d %H:%M',weather.time) or '尚未更新',600,348,32,424,50,true)
  R.hitbox(576,116,448,290,'weather')
  R.rect(48,414,976,2,true)
  text('自选行情',48,438,40,500,60,true)
  text('全部',900,442,34,124,54,true)
  text('品种',48,510,32,292,50,true)
  text('报价',366,510,32,310,50,true)
  text('涨跌',692,510,32,178,50,true)
  text('数据时间',884,510,32,140,50,true)
  local shortnames={SGE_AU9999='国内黄金',usIXIC='纳斯达克综合'}
  local count=math.min(6,#marketcfg.watchlist)
  for i=1,count do
   local item=marketcfg.watchlist[i];local q=(marketcache.quotes or {})[item.symbol];local y=572+(i-1)*80
   text(U.short(shortnames[item.symbol] or item.name or item.symbol,7),48,y+8,40,292,64,true)
   local price=q and string.format('%.2f',q.price) or '--'
   if q then
    if item.symbol=='SGE_AU9999' then price='¥'..price..'/g'
    elseif item.symbol=='XAU' or item.symbol=='XAG' then price='$'..price..'/oz'
    elseif q.unit=='点' then price=price..'点' end
   end
   text(price,366,y+6,42,310,66,true)
   text(q and q.percent and string.format('%+.2f%%',q.percent) or '—',692,y+12,36,178,58,true)
   local when=q and (q.quote_date and q.quote_date:sub(6) or (q.quote_at and os.date('%m-%d',q.quote_at))) or '--'
   text(when,884,y,32,140,40,true)
   if q and not q.quote_date and q.quote_at then text(os.date('%H:%M',q.quote_at),884,y+36,32,140,40,true) end
  end
  if count==0 then text('添加自选',48,600,40,976,70,true) end
  R.hitbox(48,430,976,626,'markets')
  R.rect(48,1060,976,2,true)
  R.drawHotspot(false)
  R.rect(48,1280,976,2,true)

 elseif page=='calendar' then
  lastHomeDate=os.date('%Y-%m-%d')
  C.draw(nav,function()redraw=true end)
 elseif page=='markets' then
  local pages=math.max(1,math.ceil(#marketcfg.watchlist/6));marketpage=math.max(1,math.min(marketpage,pages))
  R.begin('行情看板',nav);local first=(marketpage-1)*6+1;local now=os.time()
  local priceX,changeX=wide and 550 or 424,wide and 1050 or 756
  R.text('品种',48,160,34,wide and 470 or 350,50,'heavy');R.text('最新',priceX,160,34,wide and 450 or 270,50,'heavy');R.text('涨跌幅',changeX,160,34,R.width-48-changeX,50,'heavy')
  R.rect(48,211,width,3,true)
  if #marketcfg.watchlist==0 then R.text('还没有自选品种，点击下方“自选”添加',48,260,36,width,130) end
  for i=first,math.min(first+5,#marketcfg.watchlist) do
   local item=marketcfg.watchlist[i];local q=(marketcache.quotes or {})[item.symbol];local y=(wide and 224 or 232)+(i-first)*(wide and 108 or 144)
   R.text(U.short((q and q.name) or item.name or item.symbol,wide and 12 or 11),48,y,34,wide and 470 or 350,56,'heavy')
   R.text(q and string.format('%.2f',q.price) or '--',priceX,y-2,44,wide and 450 or 300,62,'heavy')
   local change=q and q.percent and string.format('%s %+.2f%%',q.percent>0 and '↑' or q.percent<0 and '↓' or '—',q.percent) or '--'
   R.text(change,changeX,y+2,36,R.width-48-changeX,56,'heavy')
   local time=q and (q.quote_date and (q.quote_date..'（日期）') or (q.quote_at and os.date('%m-%d %H:%M',q.quote_at))) or '暂无报价'
   local detail=(q and q.unit or item.symbol)..'  ·  '..(q and q.source or '数据源')..'  ·  '..time..'  ·  '..M.state(q,now,marketcfg.interval)
   R.text(detail,48,y+(wide and 62 or 66),30,width,40,'heavy')
   R.rect(48,y+(wide and 104 or 134),width,2,true)
  end
  R.text('第 '..marketpage..' / '..pages..' 页  ·  '..#marketcfg.watchlist..' 个自选',48,wide and 884 or 1090,32,wide and 620 or width,42,'heavy')
  local by=wide and 936 or 1150;local gap=wide and 344 or 236;local bw=wide and 320 or 220
  R.compact('上一页',48,by,bw,66,function()marketpage=math.max(1,marketpage-1);redraw=true end)
  R.compact('下一页',48+gap,by,bw,66,function()marketpage=math.min(pages,marketpage+1);redraw=true end)
  R.compact('更新',48+gap*2,by,bw,66,marketupdate)
  R.compact('自选',48+gap*3,by,wide and bw or 268,66,function()page='marketlist';listpage=1;redraw=true end)
  R.text((marketcache.time and ('获取 '..os.date('%m-%d %H:%M',marketcache.time)) or '尚未获取')..'  ·  每 '..marketcfg.interval..' 分钟更新',wide and 700 or 48,wide and 884 or 1260,wide and 28 or 32,wide and 700 or width,42,'heavy')
 elseif page=='marketlist' then
  R.begin('管理自选',function()page='markets';redraw=true end);local first=(listpage-1)*6+1
  for i=first,math.min(first+5,#marketcfg.watchlist) do local item=marketcfg.watchlist[i];local q=(marketcache.quotes or {})[item.symbol];local y=(wide and 156 or 174)+(i-first)*(wide and 112 or 148)
   R.text(U.short((q and q.name) or item.name or item.symbol,wide and 22 or 13),48,y+8,32,wide and 800 or 500,54)
   R.text(item.symbol,48,y+(wide and 62 or 66),26,wide and 800 or 500,40)
   local upX,downX,removeX=wide and 920 or 576,wide and 1080 or 728,wide and 1240 or 880
   if i>1 then R.compact('上移',upX,y+10,140,82,function()local target=M.move(marketcfg.watchlist,i,-1);if target then listpage=math.ceil(target/6);savemarkets(true) end end)
   else R.text('最前',upX+18,y+32,30,104,44) end
   if i<#marketcfg.watchlist then R.compact('下移',downX,y+10,140,82,function()local target=M.move(marketcfg.watchlist,i,1);if target then listpage=math.ceil(target/6);savemarkets(true) end end)
   else R.text('最后',downX+18,y+32,30,104,44) end
   R.compact('移除',removeX,y+10,wide and 160 or 144,82,function()table.remove(marketcfg.watchlist,i);savemarkets();listpage=math.min(listpage,math.max(1,math.ceil(#marketcfg.watchlist/6)));marketpage=1 end)
   R.rect(48,y+(wide and 108 or 136),width,2,true)
  end
  local y=wide and 842 or 1095
  R.button('上一页',48,y,wide and 320 or 220,wide and 84 or 100,function()listpage=math.max(1,listpage-1);redraw=true end)
  R.button('下一页',wide and 392 or 284,y,wide and 320 or 220,wide and 84 or 100,function()listpage=math.min(math.max(1,math.ceil(#marketcfg.watchlist/6)),listpage+1);redraw=true end)
  R.button('添加品种',wide and 736 or 520,y,wide and 664 or 504,wide and 84 or 100,function()page='marketadd';redraw=true end)
  R.button('刷新间隔：'..marketcfg.interval..' 分钟',48,wide and 934 or 1230,width,wide and 66 or 90,function()local values={[5]=15,[15]=30,[30]=5};marketcfg.interval=values[marketcfg.interval] or 5;savemarkets() end)
 elseif page=='marketadd' then
  R.begin('添加行情品种',function()page='marketlist';redraw=true end)
  local cols=wide and 3 or 2;local gap=wide and 460 or 502
  for i,item in ipairs(M.presets) do R.button(item.name,48+((i-1)%cols)*gap,174+math.floor((i-1)/cols)*(wide and 160 or 155),wide and 432 or 474,125,function()if addmarket(item.symbol,item.name) then page='marketlist' end;redraw=true end) end
  R.button('搜索名称 / 拼音 / 代码',48,wide and 890 or 1050,width,110,function()input('market')end)
 elseif page=='stockresults' then
  R.begin('选择搜索结果',function()input('market',stockquery)end)
  R.text('搜索：'..U.short(stockquery,38),48,155,28,width,50)
  if stockpending then R.text('正在搜索…',48,270,38,width,80)
  elseif #stockresults==0 then R.text(stockerror~='' and stockerror or '没有匹配结果，请换个拼音或代码',48,270,34,width,130)
  else
   local first=(stockresultpage-1)*6+1
   for i=first,math.min(first+5,#stockresults) do local item=stockresults[i]
    R.button(U.short(item.name,18)..'  '..item.symbol,48,220+(i-first)*(wide and 110 or 140),width,wide and 92 or 115,function()
     if addmarket(item.symbol,item.name) then listpage=math.max(1,math.ceil(#marketcfg.watchlist/6));page='marketlist';notice='已添加 '..item.name end;redraw=true
    end)
   end
  end
  local y=wide and 900 or 1140;local gap=wide and 460 or 326
  R.button('上一页',48,y,wide and 432 or 300,100,function()stockresultpage=math.max(1,stockresultpage-1);redraw=true end)
  R.button('下一页',48+gap,y,wide and 432 or 300,100,function()stockresultpage=math.min(math.max(1,math.ceil(#stockresults/6)),stockresultpage+1);redraw=true end)
  R.button('修改搜索',wide and 968 or 700,y,wide and 432 or 324,100,function()input('market',stockquery)end)
  if stockerror~='' and #stockresults>0 then R.text('网络搜索失败，显示本地匹配',48,wide and 1010 or 1260,27,width,50) end
 elseif page=='weather' then
  R.begin('天气',nav)
  local function text(s,x,y,size,w,h,bold) R.text(s,x,y,size,w,h,'heavy') end
  local data=weather.city==cfg.city.name and weather.data or nil
  local c=data and data.current;local d=data and data.daily or {};local h=data and data.hourly or {}
  if wide then
   text(cfg.city.name,48,158,40,620,60)
   text(c and (value(c.temperature_2m)..'°C') or '--°C',48,224,106,620,142)
   text(c and wname(c.weather_code) or '暂无天气',48,390,42,620,64)
   text(value((d.temperature_2m_min or {})[1])..' ~ '..value((d.temperature_2m_max or {})[1])..'°C',48,470,36,620,56)
   text('湿度 '..value(c and c.relative_humidity_2m,'%'),48,540,34,620,54)
   text(weatherupdated(),48,600,30,620,80)
   R.rect(712,158,2,500,true)
   text('未来 3 天',756,158,36,644,56)
   for i=1,3 do
    local x=756+(i-1)*224;local date=(d.time or {})[i]
    text(date and (i==1 and '今天' or date:sub(6):gsub('%-','/')) or '--',x,242,34,196,54)
    text(date and wname((d.weather_code or {})[i]) or '--',x,310,36,196,56)
    text(value((d.temperature_2m_min or {})[i])..' / '..value((d.temperature_2m_max or {})[i])..'°C',x,378,32,196,56)
    text('降雨 '..value((d.precipitation_probability_max or {})[i],'%'),x,446,28,196,48)
   end
   R.rect(48,694,width,2,true);text('接下来 6 小时',48,716,36,width,56)
   local rows={};local now=os.date('%Y-%m-%dT%H:00')
   for i,t in ipairs(h.time or {})do if t>=now and #rows<6 then rows[#rows+1]=i end end
   for n=1,6 do local i=rows[n];local x=48+(n-1)*228
    text(i and h.time[i]:sub(12,16) or '--',x,772,32,212,50)
    text(value(i and (h.temperature_2m or {})[i])..'°',x,822,38,212,58)
    text(i and wname((h.weather_code or {})[i]) or '--',x,878,32,212,50)
   end
   R.compact('未来 7 天',48,934,320,66,'weatherdays')
   R.compact('逐小时',392,934,320,66,function()hourpage=1;page='weatherhours';redraw=true end)
   R.compact('更新天气',736,934,320,66,weatherupdate)
   R.compact('选择城市',1080,934,320,66,'cities')
  else
  text(cfg.city.name,48,158,40,450,60,true)
  text(c and (value(c.temperature_2m)..'°C') or '--°C',48,224,106,520,142,true)
  text(c and wname(c.weather_code) or '暂无天气',600,209,42,424,64)
  text(value((d.temperature_2m_min or {})[1])..' ~ '..value((d.temperature_2m_max or {})[1])..'°C',600,283,36,424,56)
  text('湿度 '..value(c and c.relative_humidity_2m,'%'),600,344,34,424,54)
  text(weatherupdated(),48,410,30,976,48)
  R.rect(48,480,976,2,true)
  text('未来 3 天',48,505,36,976,56,true)
  for i=1,3 do
   local x=48+(i-1)*334;local date=(d.time or {})[i]
   if i>1 then R.rect(x-18,568,2,222,true) end
   text(date and (i==1 and '今天' or date:sub(6):gsub('%-','/')) or '--',x,568,34,306,54)
   text(date and wname((d.weather_code or {})[i]) or '--',x,626,36,306,56)
   text(value((d.temperature_2m_min or {})[i])..' / '..value((d.temperature_2m_max or {})[i])..'°C',x,687,36,306,56,true)
   text('降雨 '..value((d.precipitation_probability_max or {})[i],'%'),x,748,30,306,48)
  end
  R.rect(48,810,976,2,true)
  text('接下来 6 小时',48,836,36,976,56,true)
  local rows={};local now=os.date('%Y-%m-%dT%H:00')
  for i,t in ipairs(h.time or {}) do if t>=now and #rows<6 then rows[#rows+1]=i end end
  for n=1,6 do
   local i=rows[n];local x=48+(n-1)*164
   text(i and h.time[i]:sub(12,16) or '--',x,910,32,156,50)
   text(value(i and (h.temperature_2m or {})[i])..'°',x,966,38,156,58,true)
   text(i and wname((h.weather_code or {})[i]) or '--',x,1028,32,156,50)
  end
  R.compact('未来 7 天',48,1134,474,66,'weatherdays')
  R.compact('逐小时',550,1134,474,66,function()hourpage=1;page='weatherhours';redraw=true end)
  R.compact('更新天气',48,1218,474,66,weatherupdate)
  R.compact('选择城市',550,1218,474,66,'cities')
  end
 elseif page=='weatherdays' then
  R.begin(cfg.city.name..' · 未来 7 天',function()page='weather';redraw=true end)
  R.text(weatherupdated(),48,158,30,width,48,'heavy')
  local weatherX,tempX,rainX=wide and 390 or 280,wide and 650 or 480,wide and 1140 or 830
  R.text('日期',48,220,32,wide and 310 or 210,50,'heavy');R.text('天气',weatherX,220,32,wide and 220 or 160,50,'heavy');R.text('最低 / 最高',tempX,220,32,wide and 450 or 295,50,'heavy');R.text('降雨概率',rainX,220,32,R.width-48-rainX,50,'heavy')
  R.rect(48,266,width,3,true)
  local d=weather.city==cfg.city.name and weather.data and weather.data.daily or {};local times=d.time or {}
  if #times<2 then R.text('暂无多日预报，请点更新天气',48,365,34,width,110,'heavy') end
  for i=1,math.min(7,#times) do local date=times[i];local y=(wide and 274 or 288)+(i-1)*(wide and 88 or 116)
   local yy,mm,dd=date:match('^(%d+)%-(%d+)%-(%d+)$');local stamp=yy and os.time{year=yy,month=mm,day=dd,hour=12}
   local label=date:sub(6):gsub('%-','/')..(stamp and (' 周'..weekday[tonumber(os.date('%w',stamp))+1]) or '')
   R.text(label,48,y,34,wide and 310 or 215,54,'heavy');R.text(wname((d.weather_code or {})[i]),weatherX,y,36,wide and 220 or 160,56,'heavy')
   R.text(value((d.temperature_2m_min or {})[i])..' / '..value((d.temperature_2m_max or {})[i],'°C'),tempX,y,36,wide and 450 or 310,56,'heavy')
   R.text(value((d.precipitation_probability_max or {})[i],'%'),rainX+(wide and 0 or 10),y,36,wide and 260 or 184,56,'heavy')
   R.text('最高风速 '..value((d.wind_speed_10m_max or {})[i],' km/h'),weatherX,y+(wide and 44 or 56),wide and 28 or 30,wide and 1010 or 730,wide and 40 or 46,'heavy')
   R.rect(48,y+(wide and 84 or 109),width,2,true)
  end
  R.compact('逐小时',48,wide and 934 or 1140,wide and 648 or 474,66,function()hourpage=1;page='weatherhours';redraw=true end)
  R.compact('更新天气',wide and 752 or 550,wide and 934 or 1140,wide and 648 or 474,66,weatherupdate)
 elseif page=='weatherhours' then
  R.begin(cfg.city.name..' · 逐小时',function()page='weather';redraw=true end)
  R.text(weatherupdated(),48,158,30,width,48,'heavy')
  local tempX,weatherX,rainX=wide and 430 or 320,wide and 760 or 550,wide and 1140 or 830
  R.text('时间',48,220,32,wide and 340 or 235,50,'heavy');R.text('温度',tempX,220,32,wide and 280 or 185,50,'heavy');R.text('天气',weatherX,220,32,wide and 300 or 180,50,'heavy');R.text('降雨概率',rainX,220,32,R.width-48-rainX,50,'heavy')
  R.rect(48,266,width,3,true)
  local h=weather.city==cfg.city.name and weather.data and weather.data.hourly or {};local rows={};local now=os.date('%Y-%m-%dT%H:00')
  for i,t in ipairs(h.time or {}) do if t>=now and #rows<48 then rows[#rows+1]=i end end
  local pages=math.max(1,math.ceil(#rows/7));hourpage=math.min(hourpage,pages);local first=(hourpage-1)*7+1
  if #rows==0 then R.text('暂无小时预报，请点更新天气',48,365,34,width,110,'heavy') end
  for n=first,math.min(first+6,#rows) do local i=rows[n];local y=(wide and 274 or 284)+(n-first)*(wide and 84 or 108)
   R.text(h.time[i]:sub(6):gsub('T',' '),48,y,34,wide and 340 or 235,54,'heavy')
   R.text(value((h.temperature_2m or {})[i],'°C'),tempX,y,40,wide and 280 or 185,60,'heavy')
   R.text(wname((h.weather_code or {})[i]),weatherX,y,36,wide and 300 or 200,56,'heavy')
   R.text(value((h.precipitation_probability or {})[i],'%'),rainX+(wide and 0 or 10),y,36,wide and 260 or 184,56,'heavy')
   R.text('风速 '..value((h.wind_speed_10m or {})[i],' km/h'),tempX,y+(wide and 44 or 56),wide and 28 or 30,wide and 970 or 700,wide and 40 or 46,'heavy')
   R.rect(48,y+(wide and 82 or 102),width,2,true)
  end
  R.text('第 '..hourpage..' / '..pages..' 页  ·  未来 48 小时',48,wide and 880 or 1080,32,width,50,'heavy')
  local y=wide and 934 or 1140;local gap=wide and 344 or 236;local bw=wide and 320 or 220
  R.compact('上一页',48,y,bw,66,function()hourpage=math.max(1,hourpage-1);redraw=true end)
  R.compact('下一页',48+gap,y,bw,66,function()hourpage=math.min(pages,hourpage+1);redraw=true end)
  R.compact('7 天天气',48+gap*2,y,bw,66,'weatherdays');R.compact('更新',48+gap*3,y,wide and bw or 268,66,weatherupdate)
 elseif page=='rss' then
  R.begin('热点榜',nav,true)
  local tabGap=wide and 460 or 332
  for i,board in ipairs({{'综合','all'},{'虎嗅','huxiu'},{'澎湃','thepaper'}}) do
   R.compact(board[1],48+(i-1)*tabGap,116,wide and 432 or 312,62,function()hotBoard=board[2];listpage=1;redraw=true end)
   if hotBoard==board[2] then R.rect(66+(i-1)*tabGap,169,wide and 396 or 276,4,true) end
  end
  local items=N.items(rss,hotBoard);local pages=math.max(1,math.ceil(#items/6))
  listpage=math.max(1,math.min(listpage,pages));local first=(listpage-1)*6+1
  R.text((rss.time and ('更新 '..os.date('%H:%M',rss.time)..' · ') or '')..#items..' 条 · 第 '..listpage..' / '..pages..' 页',48,195,28,wide and 620 or width,44,'bold')
  if #items==0 then R.text('暂无热点，点击更新',48,260,36,width,70,'bold') end
  for i=first,math.min(first+5,#items) do
   local item=items[i];local slot=i-first;local x=wide and 48+(slot%2)*704 or 48;local y=250+(wide and math.floor(slot/2)*220 or slot*145)
   local tw=wide and 564 or 892
   R.text(item.rank and string.format('%02d',item.rank) or '—',x,y,42,72,70,'bold')
   R.text(U.short(item.title,wide and 42 or 46),x+84,y,36,tw,wide and 136 or 88,'bold')
   R.text((item.source or '')..(item.period and (' · '..item.period) or ''),x+84,y+(wide and 146 or 90),28,tw,40,'bold')
   R.rect(x,y+(wide and 208 or 137),wide and 648 or width,2,true)
   R.hitbox(x,y-3,wide and 648 or width,wide and 214 or 142,function()openArticle(item)end)
  end
  local y=wide and 934 or 1208;local gap=wide and 344 or 236;local bw=wide and 320 or 220
  R.compact('上一页',48,y,bw,66,function()listpage=math.max(1,listpage-1);redraw=true end)
  R.compact('下一页',48+gap,y,bw,66,function()listpage=math.min(pages,listpage+1);redraw=true end)
  R.compact('更新',48+gap*2,y,bw,66,function()network('hotspots')end)
  R.compact('首页',48+gap*3,y,wide and bw or 268,66,'home')
  R.text('每 10 分钟更新 · 首页每 3 分钟轮换',wide and 700 or 48,wide and 195 or 1310,28,wide and 700 or width,50,'bold')
 elseif page=='hotdetail' then
  R.begin('热点详情',function()page='rss';redraw=true end,true)
  R.text(N.label(selected),48,139,30,width,60,'bold')
  R.text(selected.title,48,230,40,width,wide and 140 or 210,'bold')
  R.text('热榜摘要',48,wide and 390 or 490,32,width,60,'bold')
  R.text(selected.body~='' and selected.body or '该话题暂未提供摘要。',48,wide and 460 or 560,36,width,wide and 440 or 580,'bold')
  R.button('返回热点榜',48,wide and 934 or 1210,wide and 648 or width,wide and 66 or 76,function()page='rss';redraw=true end)
  R.compact('首页',wide and 752 or 756,wide and 934 or 1310,wide and 648 or 268,66,'home')
 elseif page=='preparearticle' then
  R.begin('阅读热点',function()page='rss';redraw=true end)
  R.text(U.short(selected.title,60),48,190,38,width,210)
  R.text(articleError~='' and articleError or '正在准备正文…',48,wide and 450 or 520,38,width,150)
  if articleError~='' then R.button('重试',48,wide and 680 or 870,width,wide and 84 or 110,function()openArticle(selected)end) end
  R.button('返回热点榜',48,wide and 810 or 1040,width,wide and 84 or 110,function()page='rss';redraw=true end)
  R.compact('返回首页',48,wide and 934 or 1190,width,76,'home')
 elseif page=='todos' then
  R.begin('待办',nav);local first=(listpage-1)*7+1
  if #todos==0 then R.text('暂无待办',48,210,40,width,80) end
  for i=first,math.min(first+6,#todos) do local task=todos[i];local y=165+(i-first)*(wide and 98 or 140)
   R.button((task.done and '✓  ' or '□  ')..U.short(task.text,wide and 28 or 20),48,y,wide and 1150 or 795,wide and 84 or 110,function()task.done=not task.done;U.save(U.root..'/todos.json',todos);redraw=true end)
   R.button('删',wide and 1244 or 868,y,156,wide and 84 or 110,function()table.remove(todos,i);U.save(U.root..'/todos.json',todos);redraw=true end)
  end
  local y=wide and 910 or 1208
  R.button('上一页',48,y,wide and 320 or 225,wide and 84 or 100,function()listpage=math.max(1,listpage-1);redraw=true end)
  R.button('下一页',wide and 392 or 290,y,wide and 320 or 225,wide and 84 or 100,function()listpage=math.min(math.max(1,math.ceil(#todos/7)),listpage+1);redraw=true end)
  R.button('添加',wide and 736 or 532,y,wide and 664 or 492,wide and 84 or 100,'addtodo')
 elseif page=='addtodo' then
  R.begin('添加待办',function()page='todos';redraw=true end)
  local cols=wide and 3 or 2;local gap=wide and 460 or 502
  for i,label in ipairs({'阅读','喝水','运动','学习','买东西','休息'}) do
   R.button(label,48+((i-1)%cols)*gap,190+math.floor((i-1)/cols)*155,wide and 432 or 474,120,function()todos[#todos+1]={text=label,done=false};U.save(U.root..'/todos.json',todos);page='todos';redraw=true end)
  end
  R.button('输入文字',48,wide and 560 or 760,width,115,function()input('todo')end)
 elseif page=='settings' then
  drawSettings()
 elseif page=='cities' then
  R.begin('选择城市',function()page='settings';redraw=true end)
  local cols=wide and 3 or 2;local gap=wide and 460 or 502
  for i,c in ipairs(cities) do R.button(c.name,48+((i-1)%cols)*gap,175+math.floor((i-1)/cols)*172,wide and 432 or 474,135,function()cfg.city=c;savecfg();network();page='weather';redraw=true end) end
  R.button('搜索其他城市',48,wide and 890 or 1080,width,wide and 100 or 115,function()input('city')end)
 elseif page=='cityresults' then
  R.begin('搜索结果',function()page='cities';redraw=true end)
  for i,c in ipairs(cityresults) do R.button(U.short(c.name..' '..(c.admin1 or '')..' '..(c.country or ''),wide and 32 or 23),48,175+(i-1)*(wide and 112 or 163),width,wide and 92 or 126,function()cfg.city={name=c.name,latitude=c.latitude,longitude=c.longitude};savecfg();network();page='weather';redraw=true end) end
  if #cityresults==0 then R.text('暂无结果，请稍后返回再搜索',48,205,34,width,100) end
 elseif page=='feeds' then
  R.begin('RSS 订阅源',function()page='settings';redraw=true end)
  local pages=math.max(1,math.ceil(#cfg.feeds/4));listpage=math.max(1,math.min(listpage,pages));local first=(listpage-1)*4+1
  for i=first,math.min(first+3,#cfg.feeds) do local f=cfg.feeds[i];local slot=i-first;local x=wide and 48+(slot%2)*704 or 48;local y=180+(wide and math.floor(slot/2)*300 or slot*220)
   R.text(U.short(f.name,20),x,y,38,wide and 478 or 780,wide and 100 or 60);R.text(U.short(f.url,48),x,y+(wide and 120 or 70),24,wide and 478 or 780,wide and 150 or 75)
   R.button('删除',wide and x+512 or 846,y,wide and 136 or 178,110,function()table.remove(cfg.feeds,i);savecfg();redraw=true end)
  end
  R.text('第 '..listpage..' / '..pages..' 页  ·  '..#cfg.feeds..' 个订阅',48,wide and 780 or 1060,32,width,50)
  R.compact('上一页',48,wide and 844 or 1140,wide and 648 or 474,66,function()listpage=math.max(1,listpage-1);redraw=true end)
  R.compact('下一页',wide and 752 or 550,wide and 844 or 1140,wide and 648 or 474,66,function()listpage=math.min(pages,listpage+1);redraw=true end)
  if #cfg.feeds<12 then R.button('添加订阅地址',48,wide and 934 or 1240,width,wide and 66 or 100,function()input('feed','https://')end) end
 elseif page=='keyboard' then
  local labels={todo='输入待办',city='输入城市名称',feed='输入 RSS 地址',market='搜索股票 / ETF'}
  R.begin(labels[inputkind],function()page=inputkind=='todo' and 'addtodo' or inputkind=='city' and 'cities' or inputkind=='market' and 'marketadd' or 'feeds';redraw=true end)
  local k=R.keyboardLayout()
  R.text(inputtext(),48,k.inputY,35,k.width,k.inputH)
  if keyboardPinyin then R.text('输入拼音，点选汉字',48,k.hintY,28,k.width,45,'medium') end
  candidates(true)
  local keys={'1234567890','qwertyuiop','asdfghjkl-','zxcvbnm._/','?:=&%+#@~;'}
  for row,keyrow in ipairs(keys) do for col=1,#keyrow do local key=keyrow:sub(col,col)
   R.button(key,48+(col-1)*k.keyStepX,k.keyY+(row-1)*k.keyStepY,k.keyW,k.keyH,function()if #draft<(inputkind=='market' and 160 or 1024) then draft=draft..(keyboardUpper and key:upper() or key);candidatePage=1 end;keyboardDirty=true end)
  end end
  R.button(keyboardLabel(),k.x[1],k.controlsY,k.w[1],k.controlH,function()if keyboardPinyin then keyboardPinyin=false;keyboardUpper=false elseif not keyboardUpper then keyboardUpper=true else keyboardPinyin=true;keyboardUpper=false end;candidatePage=1;keyboardCaseDirty=true;keyboardDirty=true end)
  R.button('空格',k.x[2],k.controlsY,k.w[2],k.controlH,function()if keyboardPinyin then local next=P.commit(draft);draft=next~=draft and next or draft..' ' else draft=draft..' ' end;candidatePage=1;keyboardDirty=true end)
  R.button('退格',k.x[3],k.controlsY,k.w[3],k.controlH,function()local a=U.utf8(draft);a[#a]=nil;draft=table.concat(a);candidatePage=1;keyboardDirty=true end)
  R.button(inputkind=='market' and '搜索' or '保存',k.x[4],k.controlsY,k.w[4],k.controlH,function()
   if keyboardPinyin then draft=P.commit(draft) end
   if draft:match('^%s*$') then notice='请先输入内容';keyboardDirty=true;return end
   if inputkind=='todo' then todos[#todos+1]={text=draft,done=false};U.save(U.root..'/todos.json',todos);page='todos'
   elseif inputkind=='feed' then if #cfg.feeds>=12 then notice='最多添加 12 个订阅源';redraw=true;return end;if not U.validurl(draft) then notice='请输入完整 http 或 https 地址';redraw=true;return end;cfg.feeds[#cfg.feeds+1]={name='订阅 '..(#cfg.feeds+1),url=draft};savecfg();network();page='feeds';listpage=math.ceil(#cfg.feeds/4)
   elseif inputkind=='market' then searchstocks(draft)
   else os.remove(U.root..'/cache/cities.json');lastCities='';network('search',draft);page='cityresults';cityresults={} end
   notice='';redraw=true
  end)
 end
 footer();R.finish(full);homeClockDirty=false;R.homeHotDirty=false;redraw=false;full=false;keyboardDirty=false;keyboardCaseDirty=false;if page=='keyboard' then keyboardNotice=notice end
end
local function action(a)
 if not a then return end
 if monotonic()>=nextActivity then U.exec('lipc-set-prop com.lab126.powerd touchScreenSaverTimeout 1 >/dev/null 2>&1');nextActivity=monotonic()+2 end
 notice='';local oldpage=page
 if type(a)=='function' then a()
 elseif a=='reader' or a=='bookstore' or a=='browser' or a=='native' then quit(a)
 elseif a=='refresh' then R.forceFull=true;redraw=true;full=true
 elseif a=='update' then network()
 else page=a;listpage=1;redraw=true end
 if page~=oldpage then full=true end
end
os.remove('/tmp/mydash-v2.stop')
U.write('/tmp/mydash-v2.pid',tostring(ffi.C.getpid()));readcache()
lastMarket=U.read(U.root..'/cache/markets.json') or '';lastCache=U.read(U.root..'/cache/status.json') or '';lastRefresh=U.read(U.root..'/cache/refresh-state.json') or ''
schedule(os.time())
if U.read('/tmp/mydash-v2-resume')=='rss' then
 os.remove('/tmp/mydash-v2-resume');page='rss'
 local resume=U.load(U.root..'/cache/reader-resume.json',{})
 hotBoard=(resume.board=='huxiu' or resume.board=='thepaper') and resume.board or 'all'
 listpage=math.max(1,math.min(math.floor(tonumber(resume.listpage) or 1),math.max(1,math.ceil(#N.items(rss,hotBoard)/6))))
end
local function checkcache(now)
 if not U.read('/tmp/mydash-v2-refresh/pid') then
 local marketraw=U.read(U.root..'/cache/markets.json') or ''
 if marketraw~='' and marketraw~=lastMarket then
  local incoming=U.json.decode(marketraw)
  if incoming then
   local changed=not F.same('markets',marketcache,incoming)
   if page=='markets' then for _,item in ipairs(marketcfg.watchlist)do
    if M.state((marketcache.quotes or {})[item.symbol],now,marketcfg.interval)~=M.state((incoming.quotes or {})[item.symbol],now,marketcfg.interval) then changed=true end
   end end
   marketcache=incoming;if changed and (page=='home' or page=='markets') then redraw=true end
  end
  lastMarket=marketraw
 end
 local marker=U.read(U.root..'/cache/status.json') or ''
 if marker~=lastCache then
  lastCache=marker;local previousError=status.errors and status.errors[1];local weatherChanged,newsChanged=readcache()
  if (weatherChanged and (page=='home' or page:match('^weather'))) or (newsChanged and (page=='home' or page=='rss')) then redraw=true end
  if page~='keyboard' then
   local oldNotice=notice;local problem=status.errors and status.errors[1]
   if manualPending then notice=problem or '更新完成';redraw=true
   elseif problem then notice=problem
   elseif notice==previousError then notice='' end
   if notice~=oldNotice then redraw=true end
  end
  manualPending=false
 end
 local updated=U.read(U.root..'/cache/refresh-state.json') or ''
 if updated~=lastRefresh then lastRefresh=updated;schedule(now) end
 end
 if page=='cityresults' then local raw=U.read(U.root..'/cache/cities.json') or '';if raw~='' and raw~=lastCities then
  lastCities=raw;local results=U.json.decode(raw) or {};cityresults=results.results or {};notice=results.error or (#cityresults==0 and '未找到城市，请换个名称重试' or '');redraw=true
 end end
 if page=='stockresults' and stockpending then
  local result=U.load(U.root..'/cache/search-result.'..stockrequest..'.json',{})
  if result.id==stockrequest then stockpending=false;stockresults=result.results or {};stockerror=result.error or '';redraw=true
  elseif now-stockStarted>=18 then stockpending=false;stockerror='搜索超时，请修改后重试';redraw=true end
 end
end
local function main()
 if arg[1]=='--input-benchmark' then
  page='keyboard';inputkind='market';draft='';notice='';full=true
  local before=monotonic();draw();print(string.format('KEYBOARD_FULL %.4f s %d commands',monotonic()-before,R.last_command_count))
  local total=0;local buttons=#R.buttons
  for c in ('maotai12'):gmatch('.') do draft=draft..c;keyboardDirty=true;before=monotonic();drawInput();total=total+monotonic()-before;assert(#R.buttons==buttons) end
  print(string.format('KEYBOARD_PARTIAL average %.4f s %d commands',total/8,R.last_command_count));page='home';draw();return
 end
 if arg[1]=='--render-test' then
  readcache();notice='';selected={title='热点排版测试',body=string.rep('南京的天气与今天的阅读。',12),link='https://example.com',source='百度热搜',rank=1}
  marketcache=U.load(U.root..'/cache/markets.json',{quotes={}})
  stockquery='maotai';stockresults={{symbol='sh600519',name='贵州茅台'}}
  for _,name in ipairs({'home','calendar','weather','weatherdays','weatherhours','rss','hotdetail','preparearticle','todos','addtodo','settings','cities','cityresults','feeds','keyboard','markets','marketlist','marketadd','stockresults'}) do
   page=name;inputkind='todo';draft='Read 20 pages';draw();print('RENDER_OK '..name)
  end
  page='keyboard';inputkind='market';draft='';draw();print('RENDER_OK empty stock keyboard')
  page='home';draw();return
 end
 require('ffi/posix_h')
 local inputWait=ffi.new('struct pollfd[1]')
 acquire();local x,y=coordinates();local contact=false;local slot=0;local released=false;local lasttap=0;local initial=true
 while running do
  if U.read('/tmp/mydash-v2.stop') then quit('native');break end
  local now=os.time()
  if now>=nextPower then
   local state=lipc('state');local active=state=='active' or state=='screenSaverPending';nextPower=now+2
   if not active and not asleep then release();asleep=true
   elseif active and asleep then acquire();asleep=false;initial=true;x,y=coordinates();contact=false;released=false;R.forceFull=true;redraw=true;full=true end
  end
  if not asleep then
   if os.date('%H:%M')~=lastMinute then
    lastMinute=os.date('%H:%M')
    if page=='home' or page=='calendar' then if os.date('%Y-%m-%d')~=lastHomeDate then redraw=true elseif page=='home' then homeClockDirty=true end end
   end
   if now>=nextRefresh then network('auto');nextRefresh=now+300 end
   if now>=nextCache then nextCache=now+1;checkcache(now) end
   if page=='preparearticle' and articleError=='' then
    local result=U.load(U.root..'/cache/article-result.'..articleRequest..'.json',{})
    if result.id==articleRequest then
     os.remove(U.root..'/cache/article-result.'..articleRequest..'.json')
     if result.article_id and result.article_id:match('^%x+$') and #result.article_id==24 then launchArticle(result.article_id)
     else articleError=result.error or '正文准备失败，请重试';redraw=true end
    elseif now-articleStarted>=35 then articleError='准备超时，请返回列表后重试';redraw=true end
   end
   if page=='home' and N.advance(rss,now) then R.homeHotDirty=true end
   if redraw then draw() elseif page=='keyboard' and keyboardDirty then drawInput()
   elseif page=='home' and homeClockDirty then
    R.partial();R.rect(48,128,475,160,false);R.text(os.date('%H:%M'),48,128,118,475,160,'bold')
    R.rect(R.width-272,28,224,54,false);R.text('电量 '..battery(),R.width-272,28,34,224,54,'bold')
    R.finish(false);homeClockDirty=false
   elseif page=='home' and R.homeHotDirty then
    R.drawHotspot(true);R.homeHotDirty=false
   end
   if initial then
    -- Drop the outgoing page's gesture queued while acquiring/painting this one.
    U.discard_input(fd,ev,size);x,y=coordinates();contact=false;released=false;slot=0;initial=false
   end
   local n=ffi.C.read(fd,ev,size)
   if n==size then local e=ev[0]
    if e.type==3 then
     if e.code==47 then slot=tonumber(e.value)
     elseif slot==0 then
      if e.code==57 then if e.value>=0 then contact=true else if contact then released=true end;contact=false end
      elseif e.code==53 then x=tonumber(e.value) elseif e.code==54 then y=tonumber(e.value) end
     end
    elseif e.type==0 and e.code==3 then x,y=coordinates();contact=false;released=false
    elseif e.type==0 and e.code==0 and released then
     released=false;local tap=monotonic();if x and y and tap-lasttap>=(page=='keyboard' and 0.05 or 0.18) then lasttap=tap;action(R.hit(x,y)) end
    end
   else
    inputWait[0].fd=fd;inputWait[0].events=ffi.C.POLLIN
    ffi.C.poll(inputWait,1,(page=='preparearticle' or stockpending) and 100 or 1000)
   end
  else ffi.C.usleep(200000) end
 end
end
local ok,err=xpcall(main,debug.traceback)
local nextAction=U.read(U.root..'/next_action')
release(ok and (nextAction=='bookstore' or nextAction=='reader' or nextAction=='readarticle'))
R.close();os.remove('/tmp/mydash-v2.pid');os.remove('/tmp/mydash-v2.stop')
if powerd then pcall(function()powerd:close()end) end
if not ok then io.stderr:write(err..'\n');os.exit(1) end
