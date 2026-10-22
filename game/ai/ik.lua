-- Rigid two-bone solves: no scale/shear in palettes or collision transforms.
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local M={}
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
-- Capture the right-hand operands before writing the bone in place. This avoids
-- a temporary product and a second copy of every descendant's twelve values.
local function premultiply(rotation,m,dx,dy,dz)
    local a,b,c,d,e,f,g,h,i,j,k,l=m[1],m[2],m[3],m[4],m[5],m[6],m[7],m[8],m[9],m[10],m[11],m[12]
    local x,y,z=rotation[1],rotation[2],rotation[3]
    m[1],m[2],m[3],m[4]=x*a+y*e+z*i,x*b+y*f+z*j,x*c+y*g+z*k,x*d+y*h+z*l+dx
    x,y,z=rotation[5],rotation[6],rotation[7]
    m[5],m[6],m[7],m[8]=x*a+y*e+z*i,x*b+y*f+z*j,x*c+y*g+z*k,x*d+y*h+z*l+dy
    x,y,z=rotation[9],rotation[10],rotation[11]
    m[9],m[10],m[11],m[12]=x*a+y*e+z*i,x*b+y*f+z*j,x*c+y*g+z*k,x*d+y*h+z*l+dz
end
function M.rotate(worlds,bones,index,rotation,scratch)
    scratch=scratch or {}
    local pivot=worlds[index];local x,y,z=pivot[4],pivot[8],pivot[12]
    -- Translation of T(pivot) * rotation * T(-pivot), in the same arithmetic
    -- order as the general products, without constructing translation matrices.
    local dx=rotation[1]*(-x)+rotation[2]*(-y)+rotation[3]*(-z)+(rotation[4]+x)
    local dy=rotation[5]*(-x)+rotation[6]*(-y)+rotation[7]*(-z)+(rotation[8]+y)
    local dz=rotation[9]*(-x)+rotation[10]*(-y)+rotation[11]*(-z)+(rotation[12]+z)
    -- Bone hierarchy is immutable for an evaluator. Changing rigs clears the
    -- cached subtrees; animation only changes the world transforms.
    if scratch.bones~=bones then scratch.bones=bones;scratch.subtrees={} end
    local subtree=scratch.subtrees[index]
    if not subtree then
        subtree={};local affected={[index]=true}
        for i=index,#bones do
            if i==index or affected[bones[i].parent] then affected[i]=true;subtree[#subtree+1]=i end
        end
        scratch.subtrees[index]=subtree
    end
    for _,i in ipairs(subtree) do premultiply(rotation,worlds[i],dx,dy,dz) end
end
function M.orient(worlds,bones,index,frame,scratch)
    scratch=scratch or {}
    local current=worlds[index]
    local inverse=T.inverse(current,scratch.inverse);scratch.inverse=inverse;inverse[4],inverse[8],inverse[12]=0,0,0
    local rotation=T.mul(frame,inverse,scratch.rotation);scratch.rotation=rotation;rotation[4],rotation[8],rotation[12]=0,0,0
    M.rotate(worlds,bones,index,rotation,scratch)
end
function M.solve(worlds,bones,upper,lower,last,target,pole,scratch)
    scratch=scratch or {}
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
    M.rotate(worlds,bones,upper,T.between(sub(b,a),sub(bend,a)),scratch)
    b,c=T.origin(worlds[lower]),T.origin(worlds[last])
    M.rotate(worlds,bones,lower,T.between(sub(c,b),sub(endpoint,b)),scratch)
    return V.length(sub(T.origin(worlds[last]),target))
end
return M
