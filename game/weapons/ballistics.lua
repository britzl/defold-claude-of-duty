local V = require "game.weapons.math"
local surfaces = require "game.weapons.surfaces"
local events = require "game.events"
local combat = require "game.combat"
local rng = require "game.rng"
local M = {}
local MAX_LIVE, MAX_LAYERS, EPS = 128, 6, 1e-7
function M.new(seed,stream)
    return {live={}, fired=0, impacts=0, exits=0, retired=0, deflections=0, seed=seed or 1337, stream=stream or "ballistics"}
end
function M.spawn(sim, def, origin, direction, source, tracer)
    if #sim.live==MAX_LIVE then table.remove(sim.live,1);sim.retired=sim.retired+1 end
    sim.fired=sim.fired+1
    local p={position=V.copy(origin), origin=V.copy(origin), velocity=V.point({x=0,y=0,z=0},direction,def.muzzleVelocity),
        damage=def.damage,power=def.penetration,travelled=0,age=0,
        def=def,source=source or "player",tracer=tracer,inside={},hit_actors={},layers=0,alive=true,token={},
        random=rng.new(sim.seed,sim.stream..":"..(source or "player")..":"..sim.fired)}
    sim.live[#sim.live+1]=p
    return p
end
local function damage(p) return p.damage*(1-(1-p.def.dropoff)*math.min(1,p.travelled/p.def.maxRange)^2) end
local function impact(ctx,sim,p,hit,point,exiting)
    local props=surfaces[hit.surface] or surfaces.concrete
    local headshot=hit.region=="head" or hit.headshot==true
    sim.impacts=sim.impacts+1
    if exiting then sim.exits=sim.exits+1 end
    events.emit(ctx.events,events.BULLET_IMPACT,{point=V.copy(point),normal=exiting and hit.exit_normal or hit.normal,
        surface=hit.surface or "concrete",effect=props.fx,audio=props.audio,exit=exiting,
        weapon=p.def.id,source=p.source,round=p.token,damage=damage(p),distance=p.travelled,collider=hit.id,
        dynamic=hit.dynamic or hit.actor~=nil,region=hit.region,part=hit.part,incident=V.normalize(p.velocity)})
    if not exiting and hit.actor and not p.hit_actors[hit.actor] then
        p.hit_actors[hit.actor]=true
        local scale=hit.damage_scale or (headshot and 4 or 1)
        combat.request(ctx.combat,{target=hit.actor,source=p.source,amount=damage(p)*scale*(p.damage_scale or 1),
            headshot=headshot,region=hit.region,part=hit.part,point=V.copy(point),from=p.origin,kind="bullet",round=p.token,
            impulse=V.point({x=0,y=0,z=0},V.normalize(p.velocity),math.min(10,damage(p)*.12))})
    end
end
local function ordered(inside)
    local out={}
    for id in pairs(inside) do out[#out+1]=id end
    table.sort(out,function(a,b) return tostring(a)<tostring(b) end)
    return out
end
local function travel(p, length)
    local ids,cost=ordered(p.inside),0
    for _,id in ipairs(ids) do cost=cost+1/p.inside[id].props.depth end
    local step=cost>0 and math.min(length,p.power/cost) or length
    p.power=math.max(0,p.power-step*cost)
    for _,id in ipairs(ids) do
        local layer=p.inside[id]
        layer.distance=layer.distance+step
        -- Reference linear loss per layer, using its entry budget. Ratios keep
        -- exactly the same attenuation when flight spans multiple fixed ticks.
        -- Overlapping solids consume budget together and retain their own loss.
        local retention=math.max(.05,1-layer.props.loss*layer.distance/layer.budget)
        p.damage=p.damage*retention/layer.retention
        layer.retention=retention
    end
    p.travelled=p.travelled+step
    if step<length-1e-9 then p.alive=false end
    return step
end
local function deflect(sim,p,layer,speed)
    local spread=layer.props.deflect*math.min(1,layer.distance/layer.budget)
    if spread<=0 then return end
    -- A private stream per round: hits never consume weapon spread, AI, world
    -- or presentation randomness. Box-Muller supplies reference Gaussian yaw/pitch.
    local radius=math.sqrt(-2*math.log(math.max(1e-12,p.random())))
    local angle=p.random()*2*math.pi
    local a,b=radius*math.cos(angle)*spread,radius*math.sin(angle)*spread
    local d=V.normalize(p.velocity)
    local r=math.abs(d.y)>.9 and V.normalize({x=0,y=-d.z,z=d.y}) or V.normalize({x=d.z,y=0,z=-d.x})
    local s={x=d.y*r.z-d.z*r.y,y=d.z*r.x-d.x*r.z,z=d.x*r.y-d.y*r.x}
    d=V.normalize(V.point(V.point(d,r,a),s,b))
    p.velocity=V.point({x=0,y=0,z=0},d,speed)
    sim.deflections=sim.deflections+1
end
local function segment(ctx,p,from,speed,distance)
    if distance<=0 then return end
    events.emit(ctx.events,events.BULLET_SEGMENT,{from=from,to=V.copy(p.position),source=p.source,round=p.token})
    if p.tracer then
        events.emit(ctx.events,events.BULLET_TRACER,{from=from,to=V.copy(p.position),weapon=p.def.id,speed=speed})
    end
end
function M.update(ctx,sim,dt,query)
    for i=#sim.live,1,-1 do
        local p=sim.live[i]
        p.age=p.age+dt
        p.velocity.y=p.velocity.y-9.81*dt
        local decay=math.max(0,1-p.def.dragK*dt)
        for _,axis in ipairs({"x","y","z"}) do p.velocity[axis]=p.velocity[axis]*decay end
        local speed=V.length(p.velocity)
        local remaining=math.max(0,math.min(speed*dt,p.def.maxRange-p.travelled))
        local queries=0
        while p.alive and remaining>1e-9 do
            queries=queries+1
            -- At most six layer exits plus the final free-flight query. The
            -- guard also bounds malformed external query implementations.
            if queries>MAX_LAYERS+2 then p.alive=false;break end
            local from,dir=V.copy(p.position),V.normalize(p.velocity)
            local hits=query and query:segment(from,dir,remaining) or {}
            local timeline,previous={},p.inside
            p.inside={}
            for _,h in ipairs(hits) do
                if h.enter<=EPS and previous[h.id] then p.inside[h.id]=previous[h.id]
                else timeline[#timeline+1]={at=h.enter,hit=h,exit=false} end
                if h.leave and h.leave<=remaining+1e-9 then
                    timeline[#timeline+1]={at=math.min(h.leave,remaining),hit=h,exit=true}
                end
            end
            table.sort(timeline,function(a,b)
                if a.at==b.at then
                    if a.exit~=b.exit then return a.exit end
                    return tostring(a.hit.id)<tostring(b.hit.id)
                end
                return a.at<b.at
            end)
            local cursor,requery=0,false
            local at=1
            while at<=#timeline and p.alive do
                local event=timeline[at]
                cursor=cursor+travel(p,math.max(0,event.at-cursor))
                if not p.alive then break end
                local point,h=V.point(from,dir,cursor),event.hit
                if event.exit then
                    -- Process coincident exits in stable order before changing
                    -- course. Entries at that boundary are re-queried afterwards.
                    local exits={}
                    repeat
                        h=timeline[at].hit
                        local layer=p.inside[h.id]
                        if layer then
                            impact(ctx,sim,p,h,point,true)
                            exits[#exits+1]=layer;p.inside[h.id]=nil
                        end
                        at=at+1
                    until not timeline[at] or not timeline[at].exit or timeline[at].at~=event.at
                    if p.power<.02 or p.damage<1 then p.alive=false
                    else for _,layer in ipairs(exits) do deflect(sim,p,layer,speed) end end
                    requery=true;break
                else
                    p.layers=p.layers+1
                    if p.layers>MAX_LAYERS then p.alive=false;break end
                    impact(ctx,sim,p,h,point,false)
                    if not h.leave or p.power<=1e-8 then p.alive=false;break end
                    local props=surfaces[h.surface] or surfaces.concrete
                    p.inside[h.id]={props=props,distance=0,budget=props.depth*p.power,retention=1}
                    at=at+1
                end
            end
            if p.alive and not requery then cursor=cursor+travel(p,math.max(0,remaining-cursor)) end
            p.position=V.point(from,dir,cursor)
            segment(ctx,p,from,speed,cursor)
            remaining=math.max(0,remaining-cursor)
            if next(p.inside) and p.power<=1e-8 then p.alive=false end
            if not requery then break end
        end
        if p.travelled>=p.def.maxRange-EPS or p.age>=5 or p.position.y< -80 or p.damage<1 then p.alive=false end
        if not p.alive then table.remove(sim.live,i);sim.retired=sim.retired+1 end
    end
end
return M
