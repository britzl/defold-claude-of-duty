local grenades=require "game.systems.grenades"
local V=require "game.weapons.math"
local T=require "game.ai.transform"
local rig=require "game.ai.rig"
local rng=require "game.rng"
local animation=require "game.ai.animation"
local M={release=.48,duration=.9}
function M.init(ctx,e)
    -- Grenade timing never changes patrol, spread or burst random streams.
    e.grenade_random=rng.new(ctx.world.seed,e.id.."/grenades")
    e.grenade_cooldown=9+e.grenade_random()*13;e.has_grenade=true;e.grenades_thrown=0;e.grenade_retry=0
end
function M.cancel(ctx,e)
    local squad=e.squad and ctx.ai.squads[e.squad]
    if squad and squad.grenade_owner==e.id then squad.grenade_owner=nil end
    e.throw_target=nil;e.animation.throw_time=-1
end
function M.squads(ctx,dt)
    for _,s in pairs(ctx.ai.squads) do s.grenade_cooldown=math.max(0,(s.grenade_cooldown or 6)-dt) end
end
function M.origin(e)
    return T.point(T.root(e.position,e.yaw),T.origin(e.joints[rig.index.HandL]))
end
-- Adapt the reference lob to the target's elevation; no tracking after windup.
function M.solve(from,target)
    local dx,dz=target.x-from.x,target.z-from.z
    local distance=math.sqrt(dx*dx+dz*dz);local gravity=-require("game.config").gravity
    local speed=math.min(18,math.sqrt(math.max(4,distance*gravity/.95)))
    local vy=speed*.62;local discriminant=vy*vy+2*gravity*(from.y-target.y)
    if discriminant<=0 then return end
    local time=(vy+math.sqrt(discriminant))/gravity
    if time>=grenades.fuse-.2 or distance/time>18 then return end
    return {x=dx/time,y=vy,z=dz/time},time
end
function M.clear_arc(query,from,velocity,time)
    local previous=from
    for i=1,20 do
        local t=time*i/20
        local p=V.point(from,velocity,t);p.y=p.y+require("game.config").gravity*t*t*.5
        local dx,dy,dz=p.x-previous.x,p.y-previous.y,p.z-previous.z
        if query.camera_fraction then
            if query:camera_fraction(previous,dx,dy,dz,grenades.body_radius+.015)<.999 then return false end
        elseif not query:visible(previous,p) then return false end
        previous=p
    end
    return true
end
local function safe(ctx,e,target)
    for _,id in ipairs(ctx.ai.order) do
        local ally=ctx.ai.actors[id]
        if ally.actor.alive and V.length({x=ally.position.x-target.x,y=ally.position.y-target.y,z=ally.position.z-target.z})<grenades.radius+1 then return false end
    end
    return true
end
function M.tick(ctx,e,dt)
    e.grenade_cooldown=math.max(0,e.grenade_cooldown-dt)
    e.grenade_retry=math.max(0,e.grenade_retry-dt)
    if e.throw_target and (not e.actor.alive or not ctx.player.actor.alive or e.suppressed or e.motion.mantle) then
        M.cancel(ctx,e);e.grenade_retry=1
    end
end
function M.act(ctx,e,query)
    local a=e.animation;local squad=e.squad and ctx.ai.squads[e.squad]
    if e.throw_target then
        if a.throw_time<0 then M.cancel(ctx,e);return end
        if a.throw_time>=M.release and not e.throw_released then
            e.throw_released=true
            local from=M.origin(e);local velocity,time=M.solve(from,e.throw_target)
            if velocity and safe(ctx,e,e.throw_target)
                and query:visible({x=e.position.x,y=e.position.y+1.5,z=e.position.z},from)
                and M.clear_arc(query,from,velocity,time) then
                local g=grenades.launch(ctx,e.id,from,velocity)
                if g then
                    e.has_grenade=false;e.grenades_thrown=e.grenades_thrown+1;e.grenade_cooldown=16+e.grenade_random()*18
                    if squad then squad.grenade_cooldown=14+e.grenade_random()*12 end
                end
            end
            if e.has_grenade then M.cancel(ctx,e);e.grenade_retry=1 end
        end
        return true
    end
    if not e.has_grenade or e.grenade_cooldown>0 or e.grenade_retry>0 or e.contact_age>=1.5
        or not e.last_seen or e.memory<=0 or e.state~="fire" or e.suppressed or e.duck or e.crouch>.08
        or e.motion.mantle or a.reload_time>=0 or a.vault_time>=0 or e.motion.travel>.01
        or not ctx.services.dynamics or #ctx.grenades.live>=grenades.limit
        or (squad and (squad.grenade_owner or (squad.grenade_cooldown or 6)>0)) then return false end
    local target=V.copy(e.last_seen)
    local d=V.length({x=target.x-e.position.x,y=target.y-e.position.y,z=target.z-e.position.z})
    if d<=8 or d>=26 or not safe(ctx,e,target) then return false end
    target.y=target.y+.15
    e.grenade_retry=1
    local from=M.origin(e);local velocity,time=M.solve(from,target)
    if not velocity or not M.clear_arc(query,from,velocity,time) then return false end
    if not animation.throw(e,M.duration) then return false end
    e.throw_target=target;e.throw_released=false
    if squad then squad.grenade_owner=e.id end
    return true
end
return M
