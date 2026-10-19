-- Rigid two-bone solves: no scale/shear in palettes or collision transforms.
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local M={}
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
function M.rotate(worlds,bones,index,rotation)
    local pivot=T.origin(worlds[index])
    local delta=T.mul(T.identity(pivot.x,pivot.y,pivot.z),rotation)
    delta=T.mul(delta,T.identity(-pivot.x,-pivot.y,-pivot.z))
    local affected={[index]=true}
    for i=index,#bones do
        if i==index or affected[bones[i].parent] then
            affected[i]=true
            local value=T.mul(delta,worlds[i])
            for k=1,12 do worlds[i][k]=value[k] end
        end
    end
end
function M.orient(worlds,bones,index,frame)
    local current=worlds[index]
    local inverse=T.inverse(current);inverse[4],inverse[8],inverse[12]=0,0,0
    local rotation=T.mul(frame,inverse);rotation[4],rotation[8],rotation[12]=0,0,0
    M.rotate(worlds,bones,index,rotation)
end
function M.solve(worlds,bones,upper,lower,last,target,pole)
    local a,b,c=T.origin(worlds[upper]),T.origin(worlds[lower]),T.origin(worlds[last])
    local l1,l2=V.length(sub(b,a)),V.length(sub(c,b))
    local delta=sub(target,a);local distance=V.length(delta)
    local axis=distance>1e-8 and V.point({x=0,y=0,z=0},delta,1/distance) or V.normalize(sub(c,a))
    if V.length(axis)<.5 then axis={x=0,y=-1,z=0} end
    local d=V.clamp(distance,math.abs(l1-l2)+1e-6,l1+l2-1e-6)
    local along=(l1*l1-l2*l2+d*d)/(2*d)
    local perp=V.point(pole,axis,-T.dot(pole,axis))
    if V.length(perp)<1e-8 then
        local fallback=math.abs(axis.y)<.9 and {x=0,y=1,z=0} or {x=1,y=0,z=0}
        perp=V.point(fallback,axis,-T.dot(fallback,axis))
    end
    perp=V.normalize(perp)
    local bend=V.point(V.point(a,axis,along),perp,math.sqrt(math.max(0,l1*l1-along*along)))
    local endpoint=V.point(a,axis,d)
    M.rotate(worlds,bones,upper,T.between(sub(b,a),sub(bend,a)))
    b,c=T.origin(worlds[lower]),T.origin(worlds[last])
    M.rotate(worlds,bones,lower,T.between(sub(c,b),sub(endpoint,b)))
    return V.length(sub(T.origin(worlds[last]),target))
end
return M
