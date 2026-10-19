-- Run with the dashboard directory on LUA_PATH (host Lua or Kindle LuaJIT).
local N=require('news')
local function item(name,source) return {title=name,link='https://example.com/'..name,source=source} end
local a,b,c=item('a','A'),item('b','B'),item('c','C')
local feeds={{url='a'},{url='b'},{url='c'}}
local rows=N.merge(feeds,{a={items={a,item('a2','A')}},b={items={b}},c={items={a,c}},deleted={items={item('deleted','D')}}})
assert(#rows==4 and rows[1]==a and rows[2]==b and rows[3].title=='a2' and rows[4]==c)
assert(#N.merge(feeds,{})==0)
local rss=N.replace({}, {items={a,b,c}})
assert(not N.advance(rss,1000) and rss.home_index==1)
assert(not N.advance(rss,1179))
assert(N.advance(rss,1180) and rss.home_index==2)
rss=N.replace(rss,{items={c,a,b}})
assert(rss.home_index==3 and rss.next_change==1360)
assert(not N.advance(rss,1359))
assert(N.advance(rss,1360) and rss.home_index==1)
rss=N.replace(rss,{items={a}})
assert(rss.home_index==1 and not N.advance(rss,1540))
rss=N.replace(rss,{items={}})
assert(rss.home_index==1 and not N.advance(rss,1720))
print('PASS: alternating feeds, duplicate links, deleted feeds, 180-second rotation, wrap, cache refresh, empty/single item')

-- Publisher hot articles: use the actual hot module, excluding unrelated links.
local U=require('util')
local huxiu=[[<a href="https://www.huxiu.com/article/999.html">非热榜文章</a><div class="hot-article-wrap">
<div class="article-wrap__info"><a class="title-wrap" href="https://www.huxiu.com/article/123.html"><h3><b>原创</b> 热文甲</h3></a></div>
<div class="article-wrap__info"><a class="title-wrap" href="https://www.huxiu.com/article/124.html"><h3>热文乙</h3></a></div>
<div class="article-wrap__info"><a class="title-wrap" href="https://outside.example/125.html"><h3>外链</h3></a></div></div>]]
local paper=U.json.encode({resultCode=1,data={hotNews={
 {name='新闻甲',contId='123'},{name='付费文章',contId='124',paywalled=true},{name='新闻乙',contId='125'},{name='视频',contId='126',contType=9},
}}})
local first=N.parse(N.sources[1],huxiu);local second=N.parse(N.sources[2],paper)
assert(#first==2 and first[1].title=='热文甲' and first[1].rank==1 and first[1].period=='48小时热文')
assert(#second==2 and second[2].rank==3 and second[1].link=='https://m.thepaper.cn/newsDetail_forward_123')
assert(first[1].content_kind=='summary' and second[1].content_kind=='summary')
assert(#N.parse(N.sources[1],'<html>captcha</html>')==0)
assert(#N.parse(N.sources[2],'{"resultCode":1,"data":"bad"}')==0)
local mixed=N.merge(N.sources,{[N.sources[1].url]={items=first},[N.sources[2].url]={items=second}})
assert(#mixed==4 and mixed[2]==second[1] and #N.items({items=mixed},'huxiu')==2)
local source_payload={[N.sources[1].url]=huxiu,[N.sources[2].url]=paper}
local previous={sources={}};local payload,failed,saved=nil,false,{}
U.config=function()return {city={name='南京',latitude=32.06,longitude=118.79},feeds={{url='https://unused.example/feed'}}}end
U.exec=function(command)
 assert(command:find('--user-agent "Mozilla/5.0"',1,true),'Publishers require a normal browser user agent')
 assert(not command:find('unused.example',1,true),'Old RSS subscriptions must not be downloaded')
 if failed then return false end
 for url,body in pairs(source_payload)do if command:find(url,1,true) then payload=body;return true end end
 error('Unexpected request: '..command)
end
U.read=function()return payload end
U.load=function(_,default)return previous or default end
U.save=function(path,value)saved[path:match('([^/]+)$')]=value;return true end
os.remove=function()return true end
arg={'hotspots'}
local worker=os.getenv('MYDASH_NETWORK_FILE') or U.root..'/network.lua'
dofile(worker)
local result=assert(saved['hotspots.json']);assert(#result.items==4 and #saved['status.json'].errors==0)
previous=result;previous.sources[N.sources[2].url].time=42
source_payload[N.sources[2].url]='{"resultCode":1,"data":{"hotNews":[]}}'
dofile(worker)
assert(#saved['hotspots.json'].items==4 and saved['hotspots.json'].sources[N.sources[2].url].time==42)
assert(#saved['status.json'].errors==1)
previous=saved['hotspots.json'];local last_time=previous.time;failed=true;dofile(worker)
assert(#saved['hotspots.json'].items==4 and saved['hotspots.json'].time==last_time and #saved['status.json'].errors==2)
print('PASS: official publisher hot modules, canonical links, badges, source ranks, paid/video exclusion, offline cache and browser headers')
