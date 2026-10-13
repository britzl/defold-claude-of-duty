-- Analytic thickness for the same boxes supplied to Bullet. Entries in the
-- native adapter are confirmed by Bullet; this also detects origins in solids.
local V = require "game.weapons.math"
local T = require "game.ai.transform"
local M = {}
local axes = {"x","y","z"}
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
        enter=math.max(0,enter), leave=leave,
        normal=shape.transform and T.direction(shape.transform,ni) or V.rotate(ni,angle,0,0),
        exit_normal=shape.transform and T.direction(shape.transform,no) or V.rotate(no,angle,0,0) }
end
function M.boxes(shapes)
    return { segment=function(_,from,dir,length)
        local hits={}
        for _,shape in ipairs(shapes) do
            local hit=M.box(shape,from,dir,length)
            if hit then hits[#hits+1]=hit end
        end
        return hits
    end }
end
return M
