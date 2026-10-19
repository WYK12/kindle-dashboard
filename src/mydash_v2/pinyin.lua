-- Read the dictionary bundled with KOReader; no online input service is needed.
local dict=dofile('/mnt/us/koreader/frontend/ui/data/keyboardlayouts/zh_pinyin_data.lua')
local P={}
local extra={santi={'三体'},nasidake={'纳斯达克'}}
function P.lookup(text)
 local stem,tail=tostring(text or ''):match('^(.-)([A-Za-z]+)$')
 if not tail then return {},0,tostring(text or ''),'' end
 local code=tail:lower()
 local words,lengths,seen={},{},{}
 for n=math.min(#code,48),1,-1 do
  local v=extra[code:sub(1,n)] or dict[code:sub(1,n)]
  if v then
   if type(v)=='string' then v={v} end
   for _,word in ipairs(v) do
    if not seen[word] then seen[word]=true;words[#words+1]=word;lengths[#lengths+1]=n end
   end
  end
 end
 return words,lengths[1] or 0,stem,tail,lengths
end
function P.choose(text,index)
 local words,n,stem,tail,lengths=P.lookup(text)
 if not words[index] then return text end
 return stem..words[index]..tail:sub((lengths[index] or n)+1)
end
function P.commit(text)
 local words,n,_,tail=P.lookup(text)
 if n>0 and n==#tail and words[1] then return P.choose(text,1) end
 return text
end
return P
