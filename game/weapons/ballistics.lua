local V = require "game.weapons.math"
local surfaces = require "game.weapons.surfaces"
local events = require "game.events"
local combat = require "game.combat"
local M = {}
local MAX_LIVE, MAX_LAYERS = 128, 6
function M.new() return {live={}, fired=0, impacts=0, exits=0, retired=0} end
function M.spawn(sim, def, origin, direction, source, tracer)
    if #sim.live==MAX_LIVE then table.remove(sim.live,1);sim.retired=sim.retired+1 end
    sim.fired=sim.fired+1
    local p={position=V.copy(origin), origin=V.copy(origin), velocity=V.point({x=0,y=0,z=0},direction,def.muzzleVelocity),
        damage=def.damage,power=def.penetration,initial_power=def.penetration,travelled=0,age=0,
        def=def,source=source or "player",tracer=tracer,inside={},hit_actors={},layers=0,alive=true,token={}}
    sim.live[#sim.live+1]=p
    return p
end
local function damage(p) return p.damage*(1-(1-p.def.dropoff)*math.min(1,p.travelled/p.def.maxRange)^2) end
local function impact(ctx,sim,p,hit,point,exiting)
    local props=surfaces[hit.surface] or surfaces.concrete
    sim.impacts=sim.impacts+1
    if exiting then sim.exits=sim.exits+1 end
    events.emit(ctx.events,events.BULLET_IMPACT,{point=V.copy(point),normal=exiting and hit.exit_normal or hit.normal,
        surface=hit.surface or "concrete",effect=props.fx,audio=props.audio,exit=exiting,
        weapon=p.def.id,source=p.source,round=p.token,damage=damage(p),distance=p.travelled,collider=hit.id})
    if not exiting and hit.actor and not p.hit_actors[hit.actor] then
        p.hit_actors[hit.actor]=true
        combat.request(ctx.combat,{target=hit.actor,source=p.source,amount=damage(p)*(hit.headshot and 2 or 1)*(p.damage_scale or 1),
            headshot=hit.headshot,point=V.copy(point),from=p.origin,kind="bullet",round=p.token})
    end
end
local function travel(p, length)
    local cost,loss=0,0
    for _,h in pairs(p.inside) do
        local props=surfaces[h.surface] or surfaces.concrete
        cost=cost+1/props.depth
        loss=loss+props.loss/(props.depth*p.initial_power)
    end
    local step=cost>0 and math.min(length,p.power/cost) or length
    p.power=math.max(0,p.power-step*cost)
    p.damage=p.damage*math.exp(-step*loss)
    p.travelled=p.travelled+step
    if step<length-1e-9 or (cost>0 and p.power<1e-8) then p.alive=false end
    return step
end
function M.update(ctx,sim,dt,query)
    for i=#sim.live,1,-1 do
        local p=sim.live[i]
        p.age=p.age+dt
        p.velocity.y=p.velocity.y-9.81*dt
        local decay=math.max(0,1-p.def.dragK*dt)
        for _,axis in ipairs({"x","y","z"}) do p.velocity[axis]=p.velocity[axis]*decay end
        local speed=V.length(p.velocity)
        local dir=V.normalize(p.velocity)
        local length=math.min(speed*dt,p.def.maxRange-p.travelled)
        local from=V.copy(p.position)
        local hits=query and query:segment(from,dir,length) or {}
        local timeline={}
        -- Reconstruct active materials from the actual curved segment each tick.
        local previous=p.inside
        p.inside={}
        for _,h in ipairs(hits) do
            if h.enter<=1e-7 and previous[h.id] then
                p.inside[h.id]=h
            else
                timeline[#timeline+1]={at=h.enter,hit=h,exit=false}
            end
            if h.leave and h.leave<=length then timeline[#timeline+1]={at=h.leave,hit=h,exit=true} end
        end
        table.sort(timeline,function(a,b)
            if a.at==b.at then
                if a.exit~=b.exit then return a.exit end
                return tostring(a.hit.id)<tostring(b.hit.id)
            end
            return a.at<b.at
        end)
        local cursor=0
        for _,event in ipairs(timeline) do
            local step=travel(p,math.max(0,event.at-cursor))
            cursor=cursor+step
            if not p.alive then break end
            local h=event.hit
            impact(ctx,sim,p,h,V.point(from,dir,cursor),event.exit)
            if event.exit then p.inside[h.id]=nil else
                p.layers=p.layers+1
                if not h.leave or p.layers>MAX_LAYERS then p.alive=false;break end
                p.inside[h.id]=h
            end
        end
        if p.alive then cursor=cursor+travel(p,math.max(0,length-cursor)) end
        p.position=V.point(from,dir,cursor)
        -- Gameplay observes only the distance actually travelled, including a
        -- stop inside a material. This is independent of optional tracer FX.
        if cursor>0 then
            events.emit(ctx.events,events.BULLET_SEGMENT,{from=from,to=V.copy(p.position),source=p.source,round=p.token})
        end
        if p.tracer and cursor>0 then
            events.emit(ctx.events,events.BULLET_TRACER,{from=from,to=V.copy(p.position),weapon=p.def.id,speed=speed})
        end
        if p.travelled>=p.def.maxRange-1e-7 or p.age>=5 or p.position.y< -80 or p.damage<1 then p.alive=false end
        if not p.alive then table.remove(sim.live,i);sim.retired=sim.retired+1 end
    end
end
return M
