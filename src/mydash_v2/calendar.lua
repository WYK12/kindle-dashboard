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
 local wide=R.landscape;local width=R.width-96;local cell=wide and 193 or 140
 local top,step=wide and 310 or 366,wide and 92 or 128
 local today=os.date('*t');local days,first=C.days(C.year,C.month)
 R.begin('日历',back)
 R.text(C.year..' 年 '..C.month..' 月',48,wide and 154 or 170,52,width,80,'heavy')
 for col,label in ipairs({'周一','周二','周三','周四','周五','周六','周日'})do
  R.text(label,48+(col-1)*cell+math.floor((cell-112)/2),wide and 244 or 290,34,112,54,'heavy')
 end
 R.rect(48,wide and 299 or 348,width,3,true)
 for day=1,days do
  local slot=first+day-1;local x=48+(slot%7)*cell;local y=top+math.floor(slot/7)*step
  local isToday=C.year==today.year and C.month==today.month and day==today.day
  if isToday then
   local bx=x+math.floor((cell-116)/2)
   R.rect(bx,y+4,116,wide and 86 or 120,true);R.rect(bx+4,y+8,108,wide and 78 or 112,false)
  end
  local label=tostring(day);local size=wide and 44 or 48
  R.text(label,x+math.floor((cell-#label*(wide and 28 or 30))/2),y+(wide and (isToday and 5 or 17) or (isToday and 10 or 30)),size,96,wide and 58 or 68,'heavy')
  if isToday then R.text('今天',x+math.floor((cell-72)/2),y+(wide and 57 or 76),wide and 24 or 30,72,wide and 32 or 42,'heavy') end
 end
 local by=wide and 916 or 1190;local gap=wide and 460 or 328
 R.compact('上个月',48,by,wide and 432 or 300,wide and 66 or 84,function()C.shift(-1);changed()end)
 R.compact('回到本月',48+gap,by,wide and 432 or 320,wide and 66 or 84,function()C.open();changed()end)
 R.compact('下个月',wide and 968 or 724,by,wide and 432 or 300,wide and 66 or 84,function()C.shift(1);changed()end)
 local weekdays={'日','一','二','三','四','五','六'}
 R.text('今天：'..os.date('%Y年%m月%d日')..'  周'..weekdays[today.wday],48,wide and 1000 or 1310,32,width,54,'heavy')
end
return C
