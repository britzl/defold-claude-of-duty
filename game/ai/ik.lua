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
    if profiler then profiler.scope_begin("ik.rotate_chain") end
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
    if profiler then profiler.scope_end() end
end
function M.orient(worlds,bones,index,frame,scratch)
    if profiler then profiler.scope_begin("ik.orient") end
    scratch=scratch or {}
    local current=worlds[index]
    local inverse=T.inverse(current,scratch.inverse);scratch.inverse=inverse;inverse[4],inverse[8],inverse[12]=0,0,0
    local rotation=T.mul(frame,inverse,scratch.rotation);scratch.rotation=rotation;rotation[4],rotation[8],rotation[12]=0,0,0
    M.rotate(worlds,bones,index,rotation,scratch)
    if profiler then profiler.scope_end() end
end
function M.solve(worlds,bones,upper,lower,last,target,pole,scratch)
    if profiler then profiler.scope_begin("ik.solve") end
    scratch=scratch or {}
    -- A solve depends only on these three origins, the target and the pole.
    -- Cache rotation deltas, not output worlds: FK rebuilds the inputs each
    -- time, and descendants/orientations can change even with identical origins.
    -- Each evaluator owns its cache; simulation and presentation stay separate.
    local aw,bw,cw=worlds[upper],worlds[lower],worlds[last]
    local cached,retain
    if scratch.reuse~=false then
        if scratch.solve_bones~=bones then scratch.solve_bones=bones;scratch.solves={} end
        cached=scratch.solves[upper]
        local same_origin=cached and cached.ax==aw[4] and cached.ay==aw[8] and cached.az==aw[12]
        if same_origin and cached.valid and cached.lower==lower and cached.last==last
            and cached.bx==bw[4] and cached.by==bw[8] and cached.bz==bw[12]
            and cached.cx==cw[4] and cached.cy==cw[8] and cached.cz==cw[12]
            and cached.tx==target.x and cached.ty==target.y and cached.tz==target.z
            and cached.px==pole.x and cached.py==pole.y and cached.pz==pole.z then
            if profiler then profiler.scope_begin("ik.solve_reuse") end
            M.rotate(worlds,bones,upper,cached.upper_rotation,scratch)
            M.rotate(worlds,bones,lower,cached.lower_rotation,scratch)
            if profiler then profiler.scope_end();profiler.scope_end() end
            return cached.error
        end
        -- Moving roots cannot reuse the previous solve. Retain only their origin
        -- until it settles, avoiding fifteen key writes on every animated limb.
        retain=not cached or same_origin
        cached=cached or {};scratch.solves[upper]=cached;cached.valid=false
        cached.ax,cached.ay,cached.az=aw[4],aw[8],aw[12]
        if retain then
            cached.lower,cached.last=lower,last
            cached.bx,cached.by,cached.bz=bw[4],bw[8],bw[12]
            cached.cx,cached.cy,cached.cz=cw[4],cw[8],cw[12]
            cached.tx,cached.ty,cached.tz=target.x,target.y,target.z
            cached.px,cached.py,cached.pz=pole.x,pole.y,pole.z
        end
    end
    local a,b,c=T.origin(aw),T.origin(bw),T.origin(cw)
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
    local upper_rotation=T.between(sub(b,a),sub(bend,a))
    M.rotate(worlds,bones,upper,upper_rotation,scratch)
    b,c=T.origin(worlds[lower]),T.origin(worlds[last])
    local lower_rotation=T.between(sub(c,b),sub(endpoint,b))
    M.rotate(worlds,bones,lower,lower_rotation,scratch)
    local error=V.length(sub(T.origin(worlds[last]),target))
    if retain then
        cached.upper_rotation,cached.lower_rotation,cached.error=upper_rotation,lower_rotation,error
        cached.valid=true
    end
    if profiler then profiler.scope_end() end
    return error
end
return M
