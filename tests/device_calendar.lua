-- Real fonts/callbacks, offscreen; no writes to live dashboard settings.
assert(os.getenv('MYDASH_RENDER_OFFSCREEN')=='1')
local U=require('util')
local cfg=U.config();cfg.dashboard_landscape=false;U.config=function()return cfg end
U.write=function()return true end;U.save=function()return true end
U.exec=function()return true end;os.remove=function()return true end
local C=require('calendar');local R=require('render')
for _,case in ipairs({{2026,10,31,3},{2024,2,29,3},{1900,2,28,3},{2000,2,29,1},{2100,2,28,0},{2021,2,28,0}})do
 local days,first=C.days(case[1],case[2]);assert(days==case[3] and first==case[4])
end
local draw,labels;local begin,finish,text=R.begin,R.finish,R.text
R.begin=function(...)labels={};return begin(...)end
R.text=function(s,x,y,size,w,h,...)
 assert(x>=0 and y>=0 and x+w<=1072 and y+h<=1448,'Text outside the screen: '..tostring(s))
 labels[#labels+1]=tostring(s);return text(s,x,y,size,w,h,...)
end
R.finish=function(...)
 if not draw then draw=debug.getinfo(2,'f').func end
 return finish(...)
end
arg={'--render-test'};dofile(assert(os.getenv('MYDASH_HOME_FILE')))
local today=os.date('*t')
-- Date tap opens this month even after browsing a different month.
C.year=2020;C.month=1
assert(type(R.hit(100,45))=='function');R.hit(100,45)();draw()
assert(R.page_title=='日历' and C.year==today.year and C.month==today.month)
R.snapshot('/tmp/mydash-calendar-today.png')
local marked=false;for _,s in ipairs(labels)do if s=='今天' then marked=true end end;assert(marked)
-- Crossing New Year, returning to this month, and a month that needs six rows.
C.year=2026;C.month=1;draw();R.hit(150,1220)();draw();assert(C.year==2025 and C.month==12)
R.hit(850,1220)();draw();assert(C.year==2026 and C.month==1)
R.hit(530,1220)();draw();assert(C.year==today.year and C.month==today.month)
C.year=2026;C.month=8;draw()
local count=0;for _,s in ipairs(labels)do if s:match('^%d+$')then count=count+1 end end;assert(count==31)
for _,button in ipairs(R.buttons)do assert(button.y+button.h<=1448)end
R.snapshot('/tmp/mydash-calendar-six-rows.png')
-- The existing back control returns directly to the custom homepage.
R.hit(920,60)();draw();assert(R.page_title=='')
R.hit(100,45)();draw();assert(C.year==today.year and C.month==today.month)
print('DEVICE_CALENDAR_OK date tap, today marker, Gregorian leap years, week columns, month/year navigation, six rows, bounds, direct-home return')
