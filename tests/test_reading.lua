-- The homepage uses KOReader's existing history, skipping news and missing books.
local L=require('reading')
local originalLoad,originalOpen=loadfile,io.open
local history,broken
local existing={['/mnt/us/Books/测试 书_0123456789abcdef.epub']=true,['/mnt/us/Books/旧书.mobi']=true}
loadfile=function(path)
 assert(path=='/mnt/us/koreader/history.lua')
 if broken=='missing' then return nil end
 return function()if broken then error('Invalid history')end;return history end
end
io.open=function(path)
 if existing[path] then return {close=function()end} end
 return nil
end
history={{file='/mnt/us/RSS/news.epub'},{file='/mnt/us/Books/删除的书.epub'},{file='/mnt/us/Books/测试 书_0123456789abcdef.epub'},{file='/mnt/us/Books/旧书.mobi'}}
local path,title=L.last();assert(path==history[3].file and title=='测试 书')
for _,invalid in ipairs({'/mnt/us/RSS/news.epub','/mnt/us/Books/../secret.epub','/mnt/us/Books/folder/book.epub','/mnt/us/Books/a\n.epub','https://example.com/book.epub','/mnt/us/Books/notes.txt'})do assert(not L.valid(invalid))end
assert(not L.valid(nil) and not L.valid({}))
existing[history[3].file]=nil;path,title=L.last();assert(path==history[4].file and title=='旧书')
history={};assert(not L.last())
broken='invalid';assert(not L.last());broken='missing';assert(not L.last())
loadfile,io.open=originalLoad,originalOpen
print('PASS: most recent local book, news/missing-file exclusion, clean title, path validation and damaged/empty history')
