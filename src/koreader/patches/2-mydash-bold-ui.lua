-- Keep all KOReader interface text bold, including Chinese fallback glyphs.
local Font=require('ui/font')
local adjustedFace=Font.getAdjustedFace
function Font:getAdjustedFace(face)
 return adjustedFace(self,face,true)
end

-- Run button actions without the extra highlight/repaint/wait cycle.
G_reader_settings:saveSetting('flash_ui',false)
