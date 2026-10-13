local M = {}
function M.room(world,p)
    for _,light in ipairs(world.lights or {}) do
        local lo,hi=light.minimum,light.maximum
        if light.kind=="room" and lo and hi and p.x>=lo.x and p.x<=hi.x
            and p.y>=lo.y and p.y<=hi.y and p.z>=lo.z and p.z<=hi.z then return true end
    end
    return false
end
function M.mix(listener,position,near,range)
    if not position then return 1,0,0 end
    local p=listener.position
    local dx,dy,dz=position.x-p.x,position.y-p.y,position.z-p.z
    local d=math.sqrt(dx*dx+dy*dy+dz*dz)
    if d>=range then return 0,0,d end
    local attenuation=1/(1+(d/near)^2)
    local fade=math.min(1,(range-d)/(range*.2))
    local horizontal=math.sqrt(dx*dx+dz*dz)
    local pan=horizontal>.001 and (dx*math.cos(listener.yaw)-dz*math.sin(listener.yaw))/horizontal or 0
    return attenuation*fade,pan*.9,d
end
return M
