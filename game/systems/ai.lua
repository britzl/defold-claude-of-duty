local combat = require "game.combat"
local events = require "game.events"
local capsule = require "game.player.capsule"
local tuning = require "game.player.tuning"
local rig = require "game.ai.rig"
local transform = require "game.ai.transform"
local nav = require "game.ai.navigation"
local V = require "game.weapons.math"
local rng = require "game.rng"
local ballistics = require "game.weapons.ballistics"
local M = {}
local SHOT={id="enemy_rifle",muzzleVelocity=400,damage=10,penetration=.45,dropoff=.6,maxRange=60,dragK=.01}
local function eye(enemy) return {x=enemy.position.x,y=enemy.position.y+1.665,z=enemy.position.z} end
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
    return {time=e.age,phase=e.phase,walk=e.walk,aim=e.aim,pitch=e.pitch,recoil=e.recoil,death=e.death}
end
local function spawn(ctx,position,yaw)
    local e={id="enemy_1",actor=combat.register(ctx.combat,"enemy_1",100),
        position=V.copy(position),previous=V.copy(position),yaw=yaw or math.pi,previous_yaw=yaw or math.pi,
        state="patrol",age=0,phase=0,walk=0,aim=0,pitch=0,recoil=0,death=0,
        think=0,notice=0,memory=0,cooldown=1,route=nil,route_age=0,patrol=2,shots=0,travel=0,
        random=rng.new(ctx.world.seed,"enemy_1"),
        patrol_points={V.copy(position),{x=0,y=0,z=-5}}}
    e.motion=capsule.new(e.position);e.motion.yaw=e.yaw
    e.previous_pose=sample(e)
    e.palette=rig.pose(e.previous_pose)
    ctx.ai.actors[e.id]=e
    local service=ctx.services.soldiers
    if service then service.api.create(service,e) end
    return e
end
function M.init(ctx)
    ctx.ai={actors={},enabled=true,spawned=false,sim=ballistics.new(),work_seconds=0,peak_tick=0}
    events.on(ctx.events,events.DAMAGE_DEALT,ctx.ai,function(_,hit)
        local e=ctx.ai.actors[hit.target]
        if e and hit.source=="player" and e.actor.alive then
            e.memory=5;e.last_seen=V.copy(ctx.player.position);e.notice=1;e.think=0
        end
    end)
end
local function think(ctx,e,query)
    local target=player_target(ctx)
    local distance=nav.distance(eye(e),target)
    local delta=wrap(angle(target.x-e.position.x,target.z-e.position.z)-e.yaw)
    local aware=e.memory>0
    local sees=ctx.player.actor.alive and ctx.player.enabled and distance<=(aware and 24 or 14)
        and (aware or math.abs(delta)<math.rad(65)) and query:visible(eye(e),target)
    e.visible=sees
    e.notice=sees and math.min(1,e.notice+.25) or math.max(0,e.notice-.2)
    if sees and e.notice>=1 then e.memory=5;e.last_seen=V.copy(ctx.player.position) end
    local goal
    if e.memory>0 and e.last_seen and ctx.player.actor.alive then
        local origin=muzzle(e)
        e.state=sees and distance<10 and query:visible(eye(e),origin)
            and query:visible(origin,target) and "fire" or "pursuit"
        if e.state~="fire" then goal=e.last_seen end
    else
        e.state="patrol"
        goal=e.patrol_points[e.patrol]
        if nav.distance(e.position,goal)<.4 then
            e.patrol=e.patrol%#e.patrol_points+1;goal=e.patrol_points[e.patrol]
        end
    end
    if goal and (not e.route_goal or nav.distance(goal,e.route_goal)>.65 or e.route_age>1) then
        e.route=nav.route(ctx.world.navigation,e.position,goal,query)
        e.route_goal=V.copy(goal);e.route_age=0
    elseif not goal then e.route=nil;e.route_goal=nil end
end
local function fire(ctx,e,query)
    if e.state~="fire" or not e.visible or e.cooldown>0 or e.aim<.85 then return end
    local target=player_target(ctx)
    if math.abs(wrap(angle(target.x-e.position.x,target.z-e.position.z)-e.yaw))>.10 then return end
    -- Trace from the animated rifle's muzzle and confirm that the muzzle itself
    -- is reachable from the chest. A barrel pushed through a wall cannot shoot.
    local origin=muzzle(e)
    if not query:visible(eye(e),origin) or not query:visible(origin,target) then return end
    local offset=(e.random()-.5)*.32
    local direction=V.normalize({x=target.x-origin.x+offset,y=target.y-origin.y+(e.random()-.5)*.22,z=target.z-origin.z})
    ballistics.spawn(ctx.ai.sim,SHOT,origin,direction,e.id,true)
    events.emit(ctx.events,events.WEAPON_FIRE,{weapon=SHOT.id,source=e.id,position=origin,direction=direction})
    e.shots=e.shots+1;e.cooldown=.55;e.recoil=1
end
function M.fixed_update(ctx,dt)
    local ai=ctx.ai
    if not ctx.world.ready then return end
    local service=ctx.services.soldiers
    if not ai.spawned and service then
        for _,point in ipairs(ctx.world.spawn_points) do
            if point.id=="enemy" then spawn(ctx,point.position);break end
        end
        ai.spawned=true
    end
    local started=os.clock()
    for _,e in pairs(ai.actors) do
        e.previous=V.copy(e.position);e.previous_yaw=e.yaw;e.previous_pose=sample(e)
        local query=service and service.api.query(service,e) or e.query
        if query then
            if not e.actor.alive then
                if e.state~="dead" then
                    e.state="dead";e.route=nil;e.walk=0;e.aim=0
                    if service then service.api.disable(service,e) end
                end
                e.death=math.min(1,e.death+dt/.85);e.age=e.age+dt
            elseif ai.enabled and ctx.player.enabled then
                e.age=e.age+dt;e.memory=math.max(0,e.memory-dt)
                e.cooldown=math.max(0,e.cooldown-dt);e.route_age=e.route_age+dt
                e.think=e.think-dt
                if e.think<=0 then think(ctx,e,query);e.think=.1 end
                local waypoint=e.route and e.route[1]
                while waypoint and nav.distance(e.position,waypoint)<.28 do
                    table.remove(e.route,1);waypoint=e.route[1]
                end
                local facing=(e.state=="fire" and ctx.player.position) or waypoint
                if facing then
                    local desired=angle(facing.x-e.position.x,facing.z-e.position.z)
                    e.yaw=e.yaw+V.clamp(wrap(desired-e.yaw),-dt*4,dt*4)
                end
                e.motion.yaw=e.yaw
                local intent={enabled=true,move_x=0,move_z=0}
                if waypoint then
                    local dx,dz=waypoint.x-e.position.x,waypoint.z-e.position.z
                    local distance=math.sqrt(dx*dx+dz*dz)
                    local speed=e.state=="patrol" and 1.1 or 2.2
                    if distance>.001 then
                        dx,dz=dx/distance,dz/distance
                        local c,s=math.cos(e.yaw),math.sin(e.yaw)
                        intent.move_x=(c*dx-s*dz)*speed/(tuning.stances.stand.speed*tuning.strafe_scale)
                        local z=s*dx+c*dz
                        intent.move_z=z*speed/(tuning.stances.stand.speed*(z>0 and tuning.back_scale or 1))
                    end
                end
                capsule.update(e.motion,intent,dt,query)
                e.travel=e.travel+e.motion.travel;e.phase=e.phase+e.motion.travel*2*math.pi/1.25
                local speed=e.motion.travel/dt
                e.walk=e.walk+(math.min(1,speed/1.1)-e.walk)*math.min(1,dt*9)
                e.aim=e.aim+((e.state=="fire" and 1 or 0)-e.aim)*math.min(1,dt*8)
                local target=player_target(ctx)
                local d=math.sqrt((target.x-e.position.x)^2+(target.z-e.position.z)^2)
                e.pitch=V.clamp(math.atan2(target.y-(e.position.y+1.4),math.max(.01,d)),-.5,.5)
                e.recoil=math.max(0,e.recoil-dt*8)
            end
            e.palette=rig.pose(sample(e))
            if service and e.actor.alive then service.api.sync(service,e) end
            if ai.enabled and ctx.player.enabled and ctx.player.actor.alive and e.actor.alive then fire(ctx,e,query) end
        end
    end
    if ai.enabled and ctx.player.enabled then ballistics.update(ctx,ai.sim,dt,ctx.services.enemy_bullets) end
    local elapsed=os.clock()-started
    ai.work_seconds=ai.work_seconds+elapsed;ai.peak_tick=math.max(ai.peak_tick,elapsed)
end
function M.present(ctx)
    local service=ctx.services.soldiers
    if not service then return end
    local alpha=ctx.time.alpha
    for _,e in pairs(ctx.ai.actors) do
        local state=sample(e)
        for key,value in pairs(state) do state[key]=V.lerp(e.previous_pose[key],value,alpha) end
        local p={x=V.lerp(e.previous.x,e.position.x,alpha),y=V.lerp(e.previous.y,e.position.y,alpha),z=V.lerp(e.previous.z,e.position.z,alpha)}
        service.api.present(service,e,rig.pose(state),p,V.lerp(e.previous_yaw,e.yaw,alpha))
    end
end
function M.reset(ctx,position,yaw)
    local service=ctx.services.soldiers
    for id,e in pairs(ctx.ai.actors) do
        if service then service.api.remove(service,e) end
        combat.remove(ctx.combat,id)
    end
    ctx.ai.actors={};ctx.ai.sim=ballistics.new();ctx.ai.spawned=true
    return spawn(ctx,position or ctx.world.spawn_points[2].position,yaw)
end
function M.snapshot(ctx)
    local out={enabled=ctx.ai.enabled,actors={},fired=ctx.ai.sim.fired,live=#ctx.ai.sim.live,peak_tick_ms=ctx.ai.peak_tick*1000}
    for _,e in pairs(ctx.ai.actors) do
        out.actors[#out.actors+1]={id=e.id,health=e.actor.health,alive=e.actor.alive,state=e.state,
            x=e.position.x,y=e.position.y,z=e.position.z,yaw=e.yaw,visible=e.visible or false,
            phase=e.phase,aim=e.aim,death=e.death,shots=e.shots,travel=e.travel,route=e.route and #e.route or 0,
            bones=rig.count,hitboxes=#rig.hitboxes,recovery_failed=e.motion.recovery_failed}
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
