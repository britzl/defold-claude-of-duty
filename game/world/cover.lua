-- Ground-floor wall ends provide tall cover without changing visible geometry.
local M={limit=32}
local function supported(world,p)
    local ground
    for _,s in ipairs(world.colliders) do
        local top=s.y+s.h/2
        if math.abs(p.x-s.x)<=s.w/2 and math.abs(p.z-s.z)<=s.d/2
            and top<=p.y+.43 and top>=p.y-.45 then ground=math.max(ground or -100,top) end
    end
    if not ground then return false end
    p.y=ground
    for _,s in ipairs(world.colliders) do
        if math.abs(p.x-s.x)<s.w/2+.34 and math.abs(p.z-s.z)<s.d/2+.34
            and s.y+s.h/2>p.y+.43 and s.y-s.h/2<p.y+1.78 then return false end
    end
    return true
end
function M.add(world,s)
    if (world.tall_cover_count or 0)>=M.limit or s.cover or s.rotation_y then return end
    local bottom=s.y-s.h/2
    if bottom<-.05 or bottom>.2 or s.h<1.8 or s.h>4 then return end
    local nx,nz,half
    if s.w<=.65 and s.d>=.8 and s.d<=5 then nx,nz,half=s.x<0 and 1 or -1,0,s.d/2
    elseif s.d<=.65 and s.w>=.8 and s.w<=5 then nx,nz,half=0,s.z<0 and 1 or -1,s.w/2
    else return end
    local p={id=s.id,x=s.x+nx*(s.w/2+.44),y=bottom,z=s.z+nz*(s.d/2+.44),normal_x=nx,normal_z=nz,half_width=half}
    if supported(world,p) then
        p.height=s.y+s.h/2-p.y
        world.cover[#world.cover+1]=p;world.tall_cover_count=(world.tall_cover_count or 0)+1
    end
end
return M
