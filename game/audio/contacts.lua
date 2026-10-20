-- Accept audible impacts, rejecting resting contacts and multi-point duplicates.
local M={}
function M.accept(item,now,velocity,normal,impulse)
    local owner=item.doll or item
    local speed=math.abs(velocity.x*normal.x+velocity.y*normal.y+velocity.z*normal.z)
    speed=math.max(speed,(impulse or 0)/math.max(.001,item.spec.mass))
    local threshold=item.corpse and 1.25 or .65
    if speed<threshold or now<(owner.sound_after or 0) or (owner.sound_count or 0)>=(item.corpse and 2 or 4) then return end
    owner.sound_after=now+.12;owner.sound_count=(owner.sound_count or 0)+1
    return speed
end
return M
