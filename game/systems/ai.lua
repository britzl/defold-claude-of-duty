local combat = require "game.combat"
local events = require "game.events"
local capsule = require "game.player.capsule"
local tuning = require "game.player.tuning"
local rig = require "game.ai.rig"
local transform = require "game.ai.transform"
local nav = require "game.ai.navigation"
local planner = require "game.ai.planner"
local V = require "game.weapons.math"
local rng = require "game.rng"
local ballistics = require "game.weapons.ballistics"
local tactics = require "game.ai.tactics"
local suppression = require "game.ai.suppression"
local M = {}
local SHOT={id="enemy_rifle",muzzleVelocity=400,damage=10,penetration=.45,dropoff=.6,maxRange=60,dragK=.01}
local eye=suppression.eye
local function player_target(ctx)
    local p=ctx.player.position
    return {x=p.x,y=p.y+ctx.player.motion.height*.72,z=p.z}
end
local function angle(dx,dz) return math.atan2(-dx,-dz) end
local function wrap(v) return (v+math.pi)%(math.pi*2)-math.pi end
local function muzzle(e)
    local local_point=transform.point(e.palette[rig.index.HandR],rig.muzzle)
    return transform.point(transform.root(e.position,e.yaw),local_point)
end
local function sample(e)
    return {time=e.age,phase=e.phase,walk=e.walk,aim=e.aim,pitch=e.pitch,recoil=e.recoil,death=e.death,crouch=e.crouch}
end
local function spawn(ctx,point)
    local position,yaw,id=point.position,point.yaw or math.pi,point.id
    local index=#ctx.ai.order+1
    local e={id=id,actor=combat.register(ctx.combat,id,100),index=index,squad=point.squad,role="patrol",
        flanks_completed=0,stuck=0,replans=0,
        position=V.copy(position),previous=V.copy(position),yaw=yaw or math.pi,previous_yaw=yaw or math.pi,
        state="patrol",age=0,phase=0,walk=0,aim=0,pitch=0,recoil=0,death=0,crouch=0,duck=false,peeks=0,peek_timer=0,
        think=(index-1)/60,notice=0,memory=0,cooldown=1,route=nil,route_age=0,patrol=2,shots=0,travel=0,
        random=rng.new(ctx.world.seed,id),
        patrol_points={V.copy(position),V.copy(point.patrol or {x=0,y=0,z=-5})}}
    e.motion=capsule.new(e.position);e.motion.yaw=e.yaw
    suppression.init(e)
    e.previous_pose=sample(e)
    e.palette=rig.pose(e.previous_pose)
    ctx.ai.actors[e.id]=e
    ctx.ai.order[#ctx.ai.order+1]=e.id
    if e.squad then
        local squad=ctx.ai.squads[e.squad] or {members={}}
        ctx.ai.squads[e.squad]=squad;squad.members[#squad.members+1]=e.id
    end
    local service=ctx.services.soldiers
    if service then service.api.create(service,e) end
    return e
end
function M.init(ctx)
    ctx.ai={actors={},order={},squads={},cover_claims={},flank_claims={},nav_cache={},enabled=true,spawned=false,
        planner=planner.new(),sim=ballistics.new(),damage_scale=1,work_seconds=0,peak_tick=0,ticks=0}
    events.on(ctx.events,events.BULLET_SEGMENT,ctx.ai,function(_,segment) suppression.observe(ctx,segment,false) end)
    events.on(ctx.events,events.BULLET_IMPACT,ctx.ai,function(_,hit) suppression.observe(ctx,hit,true) end)
    events.on(ctx.events,events.DAMAGE_DEALT,ctx.ai,function(_,hit)
        local e=ctx.ai.actors[hit.target]
        if e and hit.source=="player" and e.actor.alive then
            tactics.alert(ctx,e,ctx.player.position)
        end
    end)
    events.on(ctx.events,events.ACTOR_DEATH,ctx.ai,function(_,hit)
        local e=ctx.ai.actors[hit.actor]
        if e then tactics.release(ctx.ai,e);e.nav_job=nil end
        if hit.actor=="player" then
            for _,id in ipairs(ctx.ai.order) do
                local ally=ctx.ai.actors[id]
                tactics.release(ctx.ai,ally);ally.memory=0;ally.visible=false;ally.nav_job=nil
            end
        end
    end)
end
local function think(ctx,e,query,options)
    local target=player_target(ctx)
    local distance=nav.distance(eye(e),target)
    local delta=wrap(angle(target.x-e.position.x,target.z-e.position.z)-e.yaw)
    local aware=e.memory>0
    local sees=ctx.player.actor.alive and ctx.player.enabled and distance<=(aware and 24 or 14)
        and (aware or math.abs(delta)<math.rad(65)) and query:visible(eye(e),target)
    e.visible=sees
    e.notice=sees and math.min(1,e.notice+.25) or math.max(0,e.notice-.2)
    if sees and e.notice>=1 then tactics.alert(ctx,e,ctx.player.position) end
    local goal
    if e.memory>0 and e.last_seen and ctx.player.actor.alive then
        local origin=muzzle(e)
        local can_fire=sees and distance<10 and query:visible(eye(e),origin) and query:visible(origin,target)
        if e.suppressed and e.flank then tactics.release_flank(ctx.ai,e);e.flank_retry=e.age+5 end
        goal=not e.suppressed and tactics.flank(ctx,e) or nil
        if goal then e.state="flank";e.role="flank"
        else
            local cover=e.squad and tactics.cover(ctx,e,query,options)
            if cover and nav.distance(e.position,cover)>.32 then
                goal=cover;e.state="cover";e.role="cover"
            elseif cover then
                e.state=e.suppressed and "suppressed" or (e.cover_phase=="peek" and can_fire and "fire" or "hide")
                e.role="cover"
            elseif can_fire then e.state="fire";e.role="engage"
            else
                -- Without usable cover or a clear shot, close on the last
                -- observed position rather than following an unseen player.
                tactics.release_cover(ctx.ai,e)
                goal=e.last_seen;e.state="pursuit";e.role="engage"
            end
        end
    else
        tactics.release(ctx.ai,e)
        e.state="patrol"
        goal=e.patrol_points[e.patrol]
        if nav.distance(e.position,goal)<.4 then
            e.patrol=e.patrol%#e.patrol_points+1;goal=e.patrol_points[e.patrol]
        end
    end
    if goal and (not e.route_goal or nav.distance(goal,e.route_goal)>.25
        or (not e.route and e.route_age>1) or e.stuck>1.5) then
        if e.stuck>1.5 then
            if e.cover then
                e.bad_cover=e.cover.id;e.bad_cover_until=e.age+6
                tactics.release_cover(ctx.ai,e);e.cover_retry=e.age+2
            end
            if e.flank then tactics.release_flank(ctx.ai,e);e.flank_retry=e.age+6 end
            e.stuck=0
        end
        e.route=nav.route(ctx.world.navigation,e.position,goal,query,ctx.ai.nav_cache,options)
        e.route_goal=V.copy(goal);e.route_age=0;e.replans=e.replans+1
        if not e.route then
            -- A failed approach must not reserve the only flank indefinitely
            -- while another squad member keeps renewing the radio report.
            if e.flank then tactics.release_flank(ctx.ai,e);e.flank_retry=e.age+6 end
            if e.cover then tactics.release_cover(ctx.ai,e);e.cover_retry=e.age+2 end
        end
    elseif not goal then e.route=nil;e.route_goal=nil;e.stuck=0 end
end
local function fire(ctx,e,query)
    if e.state~="fire" or e.suppressed or e.duck or e.crouch>.08 or e.motion.stance~="stand"
        or not e.visible or e.cooldown>0 or e.aim<.85 then return end
    local target=player_target(ctx)
    if math.abs(wrap(angle(target.x-e.position.x,target.z-e.position.z)-e.yaw))>.10 then return end
    -- Trace from the animated rifle's muzzle and confirm that the muzzle itself
    -- is reachable from the chest. A barrel pushed through a wall cannot shoot.
    local origin=muzzle(e)
    if not query:visible(eye(e),origin) or not query:visible(origin,target)
        or not tactics.clear_shot(ctx.ai,e,origin,target) then return end
    local offset=(e.random()-.5)*.32
    local direction=V.normalize({x=target.x-origin.x+offset,y=target.y-origin.y+(e.random()-.5)*.22,z=target.z-origin.z})
    local round=ballistics.spawn(ctx.ai.sim,SHOT,origin,direction,e.id,true)
    round.damage_scale=ctx.ai.damage_scale
    events.emit(ctx.events,events.WEAPON_FIRE,{weapon=SHOT.id,source=e.id,position=origin,direction=direction})
    e.shots=e.shots+1;e.cooldown=.55;e.recoil=1
end
function M.fixed_update(ctx,dt)
    local ai=ctx.ai
    if not ctx.world.ready then return end
    local service=ctx.services.soldiers
    if not ai.spawned and service then
        for _,point in ipairs(ctx.world.spawn_points) do
            if point.id~="player" then spawn(ctx,point) end
        end
        ai.spawned=true
    end
    local started=os.clock()
    for _,id in ipairs(ai.order) do
        local e=ai.actors[id]
        e.previous=V.copy(e.position);e.previous_yaw=e.yaw;e.previous_pose=sample(e)
        local query=service and service.api.query(service,e) or e.query
        if query then
            if not e.actor.alive then
                if e.state~="dead" then
                    tactics.release(ai,e)
                    e.state="dead";e.route=nil;e.walk=0;e.aim=0
                    if service then service.api.disable(service,e) end
                end
                e.death=math.min(1,e.death+dt/.85);e.age=e.age+dt
            elseif ai.enabled and ctx.player.enabled then
                e.age=e.age+dt;e.memory=math.max(0,e.memory-dt)
                suppression.tick(e,dt)
                e.cooldown=math.max(0,e.cooldown-dt);e.route_age=e.route_age+dt
                e.think=e.think-dt
                if e.think<=0 and not e.nav_job then
                    e.nav_job=planner.add(ai.planner,e,function()
                        think(ctx,e,query,{checkpoint=planner.checkpoint})
                        e.nav_job=nil;e.think=.1
                    end)
                end
                tactics.posture(e,dt)
                local waypoint=e.route and e.route[1]
                while waypoint and nav.distance(e.position,waypoint)<.28 do
                    table.remove(e.route,1);waypoint=e.route[1]
                end
                local facing=(e.cover_phase and e.last_seen) or (e.state=="fire" and ctx.player.position) or waypoint
                if facing then
                    local desired=angle(facing.x-e.position.x,facing.z-e.position.z)
                    e.yaw=e.yaw+V.clamp(wrap(desired-e.yaw),-dt*4,dt*4)
                end
                e.motion.yaw=e.yaw
                -- AI vault decisions and animation belong to the later tactics increment.
                local intent={enabled=true,move_x=0,move_z=0,crouch=e.duck,auto_vault=false}
                if waypoint then
                    local dx,dz=waypoint.x-e.position.x,waypoint.z-e.position.z
                    local distance=math.sqrt(dx*dx+dz*dz)
                    local speed=e.state=="patrol" and 1.1 or 2.2
                    if distance>.001 then
                        -- Brake at the goal and keep neighbouring capsules apart.
                        speed=math.min(speed,distance*4)
                        dx,dz=tactics.steer(ai,e,dx/distance*speed,dz/distance*speed)
                        local c,s=math.cos(e.yaw),math.sin(e.yaw)
                        intent.move_x=(c*dx-s*dz)/(tuning.stances.stand.speed*tuning.strafe_scale)
                        local z=s*dx+c*dz
                        intent.move_z=z/(tuning.stances.stand.speed*(z>0 and tuning.back_scale or 1))
                    end
                end
                if profiler then profiler.scope_begin("ai.movement") end
                capsule.update(e.motion,intent,dt,query)
                if profiler then profiler.scope_end() end
                -- The mover expands only after a real headroom check. Skinning,
                -- muzzle, perception and hit volumes all use this same blend.
                local target_crouch=e.motion.stance=="crouch" and 1 or 0
                e.crouch=e.crouch+V.clamp(target_crouch-e.crouch,-dt*5,dt*7)
                e.travel=e.travel+e.motion.travel;e.phase=e.phase+e.motion.travel*2*math.pi/1.25
                e.stuck=waypoint and (e.motion.travel<dt*.15 and e.stuck+dt or 0) or 0
                local speed=e.motion.travel/dt
                e.walk=e.walk+(math.min(1,speed/1.1)-e.walk)*math.min(1,dt*9)
                local aiming=not e.duck and (e.state=="fire" or e.cover_phase=="peek")
                e.aim=e.aim+((aiming and 1 or 0)-e.aim)*math.min(1,dt*8)
                local target=player_target(ctx)
                local d=math.sqrt((target.x-e.position.x)^2+(target.z-e.position.z)^2)
                e.pitch=V.clamp(math.atan2(target.y-(e.position.y+1.4),math.max(.01,d)),-.5,.5)
                e.recoil=math.max(0,e.recoil-dt*8)
            end
            if profiler then profiler.scope_begin("ai.simulation_pose") end
            -- Simulation owns this scratch independently of interpolated
            -- presentation. Hit volumes copy the transforms they retain.
            e.simulation_pose=e.simulation_pose or {}
            e.palette=rig.pose(sample(e),e.simulation_pose)
            if profiler then profiler.scope_end();profiler.scope_begin("ai.hitboxes") end
            if service and e.actor.alive then service.api.sync(service,e) end
            if profiler then profiler.scope_end() end
            if ai.enabled and ctx.player.enabled and ctx.player.actor.alive and e.actor.alive then
                if profiler then profiler.scope_begin("ai.fire") end
                fire(ctx,e,query)
                if profiler then profiler.scope_end() end
            end
        end
    end
    planner.step(ai.planner,ctx.time.frame,function(job)
        local e=job.owner
        local valid=e.nav_job==job and ai.actors[e.id]==e and e.actor.alive and ai.enabled and ctx.player.enabled
        if not valid and e.nav_job==job then e.nav_job=nil end
        return valid
    end)
    if profiler then profiler.scope_begin("ai.ballistics") end
    if ai.enabled and ctx.player.enabled then ballistics.update(ctx,ai.sim,dt,ctx.services.enemy_bullets) end
    if profiler then profiler.scope_end() end
    local elapsed=os.clock()-started
    ai.work_seconds=ai.work_seconds+elapsed;ai.peak_tick=math.max(ai.peak_tick,elapsed);ai.ticks=ai.ticks+1
end
function M.present(ctx)
    local service=ctx.services.soldiers
    if not service then return end
    local alpha=ctx.time.alpha
    for _,id in ipairs(ctx.ai.order) do
        local e=ctx.ai.actors[id]
        if profiler then profiler.scope_begin("soldiers.pose") end
        local state=sample(e)
        for key,value in pairs(state) do state[key]=V.lerp(e.previous_pose[key],value,alpha) end
        local p={x=V.lerp(e.previous.x,e.position.x,alpha),y=V.lerp(e.previous.y,e.position.y,alpha),z=V.lerp(e.previous.z,e.position.z,alpha)}
        e.presentation_pose=e.presentation_pose or {}
        local palette=rig.pose(state,e.presentation_pose)
        if profiler then profiler.scope_end();profiler.scope_begin("soldiers.upload") end
        service.api.present(service,e,palette,p,V.lerp(e.previous_yaw,e.yaw,alpha))
        if profiler then profiler.scope_end() end
    end
end
function M.reset(ctx,position,yaw)
    local service=ctx.services.soldiers
    for id,e in pairs(ctx.ai.actors) do
        if service then service.api.remove(service,e) end
        combat.remove(ctx.combat,id)
    end
    local ai=ctx.ai
    ai.actors={};ai.order={};ai.squads={};ai.cover_claims={};ai.flank_claims={};ai.nav_cache={}
    ai.planner=planner.new();ai.sim=ballistics.new();ai.spawned=true;ai.work_seconds=0;ai.peak_tick=0;ai.ticks=0
    if position then return spawn(ctx,{id="enemy_1",position=position,yaw=yaw}) end
    for _,point in ipairs(ctx.world.spawn_points) do
        if point.id~="player" then spawn(ctx,point) end
    end
    return ai.actors[ai.order[1]]
end
function M.snapshot(ctx)
    local out={enabled=ctx.ai.enabled,damage_scale=ctx.ai.damage_scale,actors={},squads=ctx.ai.squads,cover_claims=ctx.ai.cover_claims,
        flank_claims=ctx.ai.flank_claims,fired=ctx.ai.sim.fired,live=#ctx.ai.sim.live,
        planning=#ctx.ai.planner.jobs,planning_ms=ctx.ai.planner.used*1000,planning_steps=ctx.ai.planner.steps,
        peak_tick_ms=ctx.ai.peak_tick*1000,mean_tick_ms=ctx.ai.work_seconds*1000/math.max(1,ctx.ai.ticks)}
    for _,id in ipairs(ctx.ai.order) do
        local e=ctx.ai.actors[id]
        out.actors[#out.actors+1]={id=e.id,health=e.actor.health,alive=e.actor.alive,state=e.state,
            x=e.position.x,y=e.position.y,z=e.position.z,yaw=e.yaw,visible=e.visible or false,
            phase=e.phase,aim=e.aim,death=e.death,shots=e.shots,travel=e.travel,route=e.route and #e.route or 0,
            suppression=e.suppression,suppressed=e.suppressed,suppression_events=e.suppression_events,
            suppressed_ticks=e.suppressed_ticks,crouch=e.crouch,stance=e.motion.stance,
            cover_phase=e.cover_phase,peek_timer=e.peek_timer,peeks=e.peeks,
            bones=rig.count,hitboxes=#rig.hitboxes,recovery_failed=e.motion.recovery_failed,
            squad=e.squad,role=e.role,cover=e.cover and e.cover.id,flank=e.flank and e.flank.id,
            flank_index=e.flank and e.flank.index,flanks_completed=e.flanks_completed,
            memory=e.memory,last_seen=e.last_seen,replans=e.replans,stuck=e.stuck}
    end
    local service=ctx.services.soldiers
    if service then out.render=service.api.snapshot(service) end
    return out
end
function M.final(ctx)
    events.off_owner(ctx.events,ctx.ai)
    local service=ctx.services.soldiers
    for id,e in pairs(ctx.ai.actors) do
        if service then service.api.remove(service,e) end
        combat.remove(ctx.combat,id)
    end
    if service then service.api.final(service) end
    ctx.ai=nil
end
return M
