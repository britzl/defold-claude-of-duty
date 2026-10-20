-- Analytic thickness for the same boxes supplied to Bullet. Entries in the
-- native adapter are confirmed by Bullet; this also detects origins in solids.
local V = require "game.weapons.math"
local T = require "game.ai.transform"
local M = {}
local axes = {"x","y","z"}
-- Conservative rejection for the native ray's starting-inside fallback. The
-- full slab test below still decides entries/exits and their normals. Include
-- entries up to its 1e-7 threshold, including origins just outside a face.
function M.contains_origin(shape, origin, direction)
    local x,y,z=origin.x-shape.x,origin.y-shape.y,origin.z-shape.z
    local dx,dy,dz=direction.x,direction.y,direction.z
    if shape.transform then
        local m=shape.transform
        x=m[1]*origin.x+m[5]*origin.y+m[9]*origin.z-(m[1]*m[4]+m[5]*m[8]+m[9]*m[12])
        y=m[2]*origin.x+m[6]*origin.y+m[10]*origin.z-(m[2]*m[4]+m[6]*m[8]+m[10]*m[12])
        z=m[3]*origin.x+m[7]*origin.y+m[11]*origin.z-(m[3]*m[4]+m[7]*m[8]+m[11]*m[12])
        dx,dy,dz=m[1]*dx+m[5]*dy+m[9]*dz,m[2]*dx+m[6]*dy+m[10]*dz,m[3]*dx+m[7]*dy+m[11]*dz
    elseif shape.rotation_x and shape.rotation_x~=0 then
        local c,s=math.cos(-shape.rotation_x),math.sin(-shape.rotation_x)
        y,z=y*c-z*s,z*c+y*s
        dy,dz=dy*c-dz*s,dz*c+dy*s
    end
    return math.abs(x)<=shape.w*.5+math.abs(dx)*1e-7+1e-9
        and math.abs(y)<=shape.h*.5+math.abs(dy)*1e-7+1e-9
        and math.abs(z)<=shape.d*.5+math.abs(dz)*1e-7+1e-9
end
function M.box(shape, origin, direction, length)
    local angle=shape.rotation_x or 0
    local p=V.rotate({x=origin.x-shape.x,y=origin.y-shape.y,z=origin.z-shape.z},-angle,0,0)
    local d=V.rotate(direction,-angle,0,0)
    if shape.transform then
        local inverse=T.inverse(shape.transform)
        p,d=T.point(inverse,origin),T.direction(inverse,direction)
    end
    local half={x=shape.w/2,y=shape.h/2,z=shape.d/2}
    local enter,leave=-math.huge,math.huge
    local ni,no={x=0,y=0,z=0},{x=0,y=0,z=0}
    for _,axis in ipairs(axes) do
        if math.abs(d[axis])<1e-10 then
            if math.abs(p[axis])>half[axis] then return end
        else
            local a,b=(-half[axis]-p[axis])/d[axis],(half[axis]-p[axis])/d[axis]
            local sign=-1
            if a>b then a,b=b,a;sign=1 end
            if a>enter then enter=a;ni={x=0,y=0,z=0};ni[axis]=sign end
            if b<leave then leave=b;no={x=0,y=0,z=0};no[axis]=-sign end
            if enter>leave then return end
        end
    end
    if leave<=1e-7 or enter>length or leave-enter<1e-7 then return end
    return { id=shape.id, surface=shape.surface, actor=shape.actor, headshot=shape.headshot,
        dynamic=shape.dynamic or shape.actor~=nil, region=shape.region, part=shape.part, damage_scale=shape.damage_scale,
        enter=math.max(0,enter), leave=leave,
        normal=shape.transform and T.direction(shape.transform,ni) or V.rotate(ni,angle,0,0),
        exit_normal=shape.transform and T.direction(shape.transform,no) or V.rotate(no,angle,0,0) }
end
function M.boxes(shapes)
    return { segment=function(_,from,dir,length)
        local hits={}
        for _,shape in ipairs(shapes) do
            local hit=not shape.disabled and M.box(shape,from,dir,length)
            if hit then hits[#hits+1]=hit end
        end
        return hits
    end }
end
return M
