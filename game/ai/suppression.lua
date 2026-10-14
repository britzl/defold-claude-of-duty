-- Pressure is local evidence, not knowledge of the shooter's position. Track
-- the strongest stimulus per live round, so segments/entry/exit cannot stack.
local V=require "game.weapons.math"
local rig=require "game.ai.rig"
local T=require "game.ai.transform"
local M={threshold=.9,recovery=.3,decay=.55,maximum=1.6}
function M.init(e)
    e.suppression=0;e.suppressed=false;e.suppression_events=0;e.suppressed_ticks=0
    e.pressure=setmetatable({},{__mode="k"})
end
function M.eye(e)
    local p=T.point(e.palette[rig.index.Head],{x=0,y=1.665,z=-.008})
    return T.point(T.root(e.position,e.yaw),p)
end
local function add(e,amount,round)
    local previous=e.pressure[round] or 0
    if amount<=previous then return end
    e.pressure[round]=amount
    if previous==0 then e.suppression_events=e.suppression_events+1 end
    e.suppression=math.min(M.maximum,e.suppression+amount-previous)
    if e.suppression>=M.threshold then e.suppressed=true end
end
local function closest(a,b,p)
    local dx,dy,dz=b.x-a.x,b.y-a.y,b.z-a.z
    local length=dx*dx+dy*dy+dz*dz
    local t=length>0 and V.clamp(((p.x-a.x)*dx+(p.y-a.y)*dy+(p.z-a.z)*dz)/length,0,1) or 0
    return {x=a.x+dx*t,y=a.y+dy*t,z=a.z+dz*t}
end
function M.observe(ctx,event,impact)
    if ctx.paused or not ctx.ai.enabled or not ctx.player.enabled or not ctx.player.actor.alive
        or event.source~="player" or not event.round or (impact and event.exit) then return end
    local service=ctx.services.soldiers
    for _,id in ipairs(ctx.ai.order) do
        local e=ctx.ai.actors[id]
        if e.actor.alive then
            local eye=M.eye(e)
            local point=impact and event.point or closest(event.from,event.to,eye)
            local distance=V.length({x=eye.x-point.x,y=eye.y-point.y,z=eye.z-point.z})
            local radius=impact and 2.5 or 2.2
            if distance<radius then
                local query=service and service.api.query(service,e) or e.query
                local origin=point
                if impact and event.normal then origin=V.point(point,event.normal,.025) end
                -- Impact sound through nearby cover is attenuated; a distant
                -- wall/floor never extends the radius. Near misses need LOS.
                local visible=query and query:visible(origin,eye)
                if visible or (impact and distance<1.5) then
                    local strength=(impact and .65 or .7)*(1-distance/radius)
                    if not visible then strength=strength*.6 end
                    add(e,strength,event.round)
                end
            end
        end
    end
end
function M.tick(e,dt)
    e.suppression=math.max(0,e.suppression-dt*M.decay)
    if e.suppressed and e.suppression<=M.recovery then e.suppressed=false end
    if e.suppressed then e.suppressed_ticks=e.suppressed_ticks+1 end
end
return M
