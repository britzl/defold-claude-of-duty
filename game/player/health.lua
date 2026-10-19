-- Fixed-tick health feedback. Damage and regeneration remain in game.combat.
local events = require "game.events"
local camera = require "game.player.camera"
local T = require "game.player.health_tuning"
local V = require "game.weapons.math"
local M = {}
local function active(ctx)
    return not ctx.paused and ctx.world.ready and ctx.player.enabled and ctx.player.actor.alive
end
local function direction(ctx, from)
    local p = ctx.player.position
    return from and {x=from.x-p.x,y=from.y-p.y,z=from.z-p.z}
end
local function eye(ctx)
    local p, m = ctx.player.position, ctx.player.motion
    return {x=p.x,y=p.y+m.eye,z=p.z}
end
local function visible(ctx, from, to)
    local q = ctx.services.capsule
    if not q then return false end
    -- The travelled endpoint can be inside a wall where Bullet's rays have no
    -- entry hit. Cast from the clear player eye toward that endpoint instead.
    return not q:ray(to,from.x-to.x,from.y-to.y,from.z-to.z)
end
local function add(ctx, amount, token, kind, from)
    local state = ctx.player.health_state
    local previous = token and state.pressure[token] or 0
    if amount <= previous then return end
    if token then state.pressure[token] = amount end
    local delta = amount-previous
    state.suppression = math.min(1,state.suppression+delta)
    if previous == 0 then state.stimuli = state.stimuli+1 end
    camera.impulse(ctx.player.camera,kind,delta,direction(ctx,from),ctx.player.motion.yaw)
end

function M.reset(ctx)
    ctx.player.health_state = {suppression=0,hit_flash=0,effect=0,pulse=0,phase=0,
        heartbeat_hz=0,stimuli=0,emit_timer=0,was_regenerating=false,
        pressure=setmetatable({},{__mode="k"})}
end

function M.snapshot(ctx)
    local actor, s = ctx.player.actor, ctx.player.health_state
    local fraction = actor.health/actor.max_health
    return {health=actor.health,max_health=actor.max_health,fraction=fraction,
        low=actor.alive and fraction<T.low,critical=actor.alive and fraction<T.critical,
        dead=not actor.alive,regenerating=actor.regenerating,since_damage=actor.since_damage,
        suppression=s.suppression,effect=s.effect,pulse=s.pulse,hit_flash=s.hit_flash,
        heartbeat_hz=s.heartbeat_hz,stimuli=s.stimuli}
end

function M.observe(ctx, cue, impact)
    if not active(ctx) or not cue.source or cue.source=="player" or not cue.round
        or (impact and cue.exit) then return end
    local at = eye(ctx)
    local point = cue.point
    if not impact then
        local a,b = cue.from,cue.to
        local dx,dy,dz = b.x-a.x,b.y-a.y,b.z-a.z
        local length = dx*dx+dy*dy+dz*dz
        if length<1e-12 then return end
        local t = V.clamp(((at.x-a.x)*dx+(at.y-a.y)*dy+(at.z-a.z)*dz)/length,0,1)
        point = {x=a.x+dx*t,y=a.y+dy*t,z=a.z+dz*t}
    end
    local distance = V.length({x=point.x-at.x,y=point.y-at.y,z=point.z-at.z})
    if distance>=T.suppression.radius then return end
    local origin = impact and cue.normal and V.point(point,cue.normal,0.025) or point
    if not visible(ctx,origin,at) then return end
    add(ctx,T.suppression.near_miss*(1-distance/T.suppression.radius),cue.round,"suppression",point)
end

function M.explosion(ctx, cue)
    if not active(ctx) or not cue.position then return end
    local radius = cue.radius or 5
    if type(radius)~="number" or not (radius>0 and radius<math.huge) then return end
    local at = eye(ctx)
    local distance = V.length({x=cue.position.x-at.x,y=cue.position.y-at.y,z=cue.position.z-at.z})
    local falloff = math.max(0,1-distance/radius)^1.6
    -- Blast damage/occlusion belongs to the grenade owner (step 12). An
    -- occluded blast still supplies feedback and must not apply damage twice.
    add(ctx,T.suppression.explosion*falloff,cue.token or cue,"explosion",cue.position)
end

function M.init(ctx)
    M.reset(ctx)
    local owner = ctx.player
    events.on(ctx.events,events.BULLET_SEGMENT,owner,function(_,cue) M.observe(ctx,cue,false) end)
    events.on(ctx.events,events.BULLET_IMPACT,owner,function(_,cue) M.observe(ctx,cue,true) end)
    events.on(ctx.events,events.EXPLOSION,owner,function(_,cue) M.explosion(ctx,cue) end)
    events.on(ctx.events,events.DAMAGE_TAKEN,owner,function(_,hit)
        local s = ctx.player.health_state
        if hit.killed then
            s.suppression,s.pulse,s.phase,s.heartbeat_hz,s.hit_flash,s.effect = 0,0,0,0,0,1
            s.pressure=setmetatable({},{__mode="k"})
        elseif active(ctx) then
            local source = ctx.ai and ctx.ai.actors[hit.source]
            local from = hit.from or (source and source.position)
            local severity = math.min(1,hit.amount/45)
            s.hit_flash = math.min(1,s.hit_flash+T.flash*(0.4+severity))
            add(ctx,T.suppression.hit*(0.5+severity),hit.round,"damage",from)
        end
        events.emit(ctx.events,events.PLAYER_HEALTH,M.snapshot(ctx))
    end)
end

function M.fixed_update(ctx, dt)
    if not active(ctx) then return end
    local s, actor = ctx.player.health_state,ctx.player.actor
    s.suppression = math.max(0,s.suppression-T.suppression.decay*dt)
    s.hit_flash = s.hit_flash*math.exp(-dt/T.flash_tau)
    local fraction = actor.health/actor.max_health
    local target = math.max(0,(T.low-fraction)/T.low)
    s.effect = s.effect+(target-s.effect)*(1-math.exp(-dt/T.effect_tau))
    if s.effect>0.02 then
        s.heartbeat_hz = T.heartbeat_min+(T.heartbeat_max-T.heartbeat_min)*target
        s.phase = s.phase+dt*s.heartbeat_hz
        if s.phase>=1 then
            s.phase = s.phase%1
            events.emit(ctx.events,events.PLAYER_HEARTBEAT,{strength=s.effect,fraction=fraction})
        end
        s.pulse = (math.exp(-((s.phase-0.06)/0.035)^2/2)
            +0.62*math.exp(-((s.phase-0.22)/0.045)^2/2))*s.effect
    else s.phase,s.pulse,s.heartbeat_hz = 0,0,0 end
    s.emit_timer = s.emit_timer-dt
    if s.emit_timer<=0 or s.was_regenerating~=actor.regenerating then
        s.emit_timer,s.was_regenerating = 0.1,actor.regenerating
        events.emit(ctx.events,events.PLAYER_HEALTH,M.snapshot(ctx))
    end
end
return M
