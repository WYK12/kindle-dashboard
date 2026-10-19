local C={}
local offsets={0,3,2,5,0,3,5,1,4,6,2,4}
local lengths={31,28,31,30,31,30,31,31,30,31,30,31}
function C.days(year,month)
 local days=lengths[month]
 if month==2 and year%4==0 and (year%100~=0 or year%400==0) then days=29 end
 local y=year-(month<3 and 1 or 0)
 local first=(y+math.floor(y/4)-math.floor(y/100)+math.floor(y/400)+offsets[month])%7
 return days,first -- Monday is column zero.
end
function C.open()
 local today=os.date('*t');C.year=today.year;C.month=today.month
end
function C.shift(step)
 local month=C.year*12+C.month-1+step
 C.year=math.floor(month/12);C.month=month%12+1
end
function C.draw(back,changed)
 local R=require('render')
 if not C.year then C.open() end
 local today=os.date('*t');local days,first=C.days(C.year,C.month)
 R.begin('日历',back)
 R.text(C.year..' 年 '..C.month..' 月',48,170,52,976,80,'heavy')
 for col,label in ipairs({'周一','周二','周三','周四','周五','周六','周日'})do
  R.text(label,80+(col-1)*140,290,34,112,54,'heavy')
 end
 R.rect(48,348,976,3,true)
 for day=1,days do
  local slot=first+day-1;local x=48+(slot%7)*140;local y=366+math.floor(slot/7)*128
  local isToday=C.year==today.year and C.month==today.month and day==today.day
  if isToday then
   R.rect(x+10,y+4,116,120,true);R.rect(x+14,y+8,108,112,false)
  end
  local label=tostring(day)
  R.text(label,x+math.floor((136-#label*30)/2),y+(isToday and 10 or 30),48,96,68,'heavy')
  if isToday then R.text('今天',x+36,y+76,30,72,42,'heavy') end
 end
 R.compact('上个月',48,1190,300,84,function()C.shift(-1);changed()end)
 R.compact('回到本月',376,1190,320,84,function()C.open();changed()end)
 R.compact('下个月',724,1190,300,84,function()C.shift(1);changed()end)
 local weekdays={'日','一','二','三','四','五','六'}
 R.text('今天：'..os.date('%Y年%m月%d日')..'  周'..weekdays[today.wday],48,1310,32,976,54,'heavy')
end
return C
