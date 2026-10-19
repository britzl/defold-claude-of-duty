-- Animation clocks and planted contacts advance only with fixed simulation.
local V=require "game.weapons.math"
local T=require "game.ai.transform"
local variants=require "game.ai.variants"
local M={}
local function wrap(v) return (v+math.pi)%(2*math.pi)-math.pi end
local function clone(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=clone(v) end;return out
end
function M.init(e)
    e.animation={feet={},pelvis=0,turn_time=-1,turn_direction=1,reload_time=-1,reload_duration=2.4,
        vault_time=-1,vault_duration=.85,hit_time=1,hit_region="torso",hit_side=1,hit_strength=0,
        previous=V.copy(e.position),previous_yaw=e.yaw}
end
function M.reload(e,duration)
    if not e.actor.alive then return false end
    local a=e.animation;if a.reload_time>=0 or a.vault_time>=0 then return false end
    a.reload_time=0;a.reload_duration=math.max(.1,duration or (e.variant=="irregular" and 2.9 or 2.35));return true
end
function M.vault(e,duration,hand)
    if not e.actor.alive then return false end
    local a=e.animation;if a.vault_time>=0 then return false end
    a.vault_time=0;a.vault_duration=math.max(.1,duration or .85);a.vault_hand=hand and V.copy(hand)
    a.reload_time=-1;a.feet={};return true
end
function M.turn(e,delta)
    local a=e.animation
    if a.turn_time<0 then a.turn_time=0;a.turn_direction=delta>=0 and 1 or -1 end
end
function M.hit(e,hit)
    local a=e.animation
    a.hit_time=0;a.hit_region=hit.region or (hit.headshot and "head" or "torso")
    local side=hit.part and hit.part:match("_([rl])$")
    if side then a.hit_side=side=="r" and 1 or -1
    elseif hit.from then
        local p=T.point(T.inverse(T.root(e.position,e.yaw)),hit.from);a.hit_side=p.x>=0 and 1 or -1
    end
    a.hit_strength=V.clamp((hit.amount or 20)/25,.3,1.5)
end
local function advance(a,key,duration,dt)
    if a[key]>=0 then a[key]=a[key]+dt;if a[key]>duration then a[key]=-1 end end
end
function M.step(e,dt,query)
    local a=e.animation
    if not e.actor.alive then
        a.feet={};a.reload_time=-1;a.vault_time=-1;a.turn_time=-1;return
    end
    a.hit_time=math.min(1,a.hit_time+dt)
    advance(a,"reload_time",a.reload_duration,dt);advance(a,"vault_time",a.vault_duration,dt);advance(a,"turn_time",.42,dt)
    local definition=variants.get(e.variant);local scale=definition.scale
    local displacement={x=e.position.x-a.previous.x,y=e.position.y-a.previous.y,z=e.position.z-a.previous.z}
    local planar=math.sqrt(displacement.x^2+displacement.z^2)
    local teleport=V.length(displacement)>1 or math.abs(wrap(e.yaw-a.previous_yaw))>1
    if teleport then a.feet={};a.pelvis=0 end
    local velocity={x=displacement.x/dt,y=0,z=displacement.z/dt}
    if teleport then velocity={x=0,y=0,z=0} end
    local speed=V.length(velocity);local moving=speed>.06
    if moving and not a.was_moving then e.phase=0 end
    a.was_moving=moving
    local root=T.root(e.position,e.yaw);local inverse=T.inverse(root)
    local stride=1.25+.45*(e.run or 0)
    local period=stride/math.max(.4,speed)
    local feet={};local drop=0
    for _,side in ipairs({"R","L"}) do
        local foot=a.feet[side] or {};a.feet[side]=foot
        local phase=(e.phase/(2*math.pi)+.30+(side=="R" and 0 or .5))%1
        local turning=a.turn_time>=0 and ((a.turn_direction>0 and side=="R") or (a.turn_direction<0 and side=="L"))
        local swing=moving and phase>=.60 or turning
        local progress=turning and a.turn_time/.42 or V.clamp((phase-.60)/.40,0,1)
        local rest=T.point(root,{x=(side=="R" and .103 or -.103)*scale,y=.088*scale,z=.022*scale})
        local goal=V.point(rest,velocity,math.min(.50/math.max(.01,speed),period*.30))
        if not foot.anchor then foot.anchor=V.copy(rest);foot.yaw=e.yaw end
        if swing and not foot.swing then foot.takeoff=V.copy(foot.anchor) end
        local target=V.copy(foot.anchor)
        if swing then
            local from=foot.takeoff or target;local blend=V.smooth(progress)
            target={x=V.lerp(from.x,goal.x,blend),y=V.lerp(from.y,goal.y,blend),z=V.lerp(from.z,goal.z,blend)}
        elseif foot.swing then
            -- The last swing sample is the actual touchdown, even at low FPS.
            target=V.copy(foot.last or rest);foot.yaw=e.yaw
        elseif not moving and math.abs(wrap(e.yaw-(foot.yaw or e.yaw)))>.23 then
            -- Small turns also step; large turns use the explicit one-shot.
            target.x=target.x+(rest.x-target.x)*math.min(1,dt*8)
            target.z=target.z+(rest.z-target.z)*math.min(1,dt*8)
            target.y=rest.y;foot.yaw=e.yaw
        end
        local local_point=T.point(inverse,target)
        if math.abs(local_point.x)>.40*scale or math.abs(local_point.z)>.66*scale then
            target=rest;foot.takeoff=V.copy(rest);foot.yaw=e.yaw
        end
        local ground=query and query.ray and query:ray({x=target.x,y=e.position.y+.62*scale,z=target.z},0,-1.1*scale,0)
        local supported=ground and ground.ny>=.707 and math.abs(ground.y-e.position.y)<.46*scale
        local normal={x=0,y=1,z=0}
        if supported then
            target.y=ground.y+.088*scale
            normal=T.direction(inverse,{x=ground.nx,y=ground.ny,z=ground.nz})
        else
            target.y=e.position.y+.088*scale;foot.takeoff=nil
        end
        local lift=swing and math.sin(math.pi*progress)*(.075+.08*(e.run or 0))*scale or 0
        foot.anchor=V.copy(target);foot.last=V.copy(target);foot.swing=swing
        target.y=target.y+lift
        local local_target=T.point(inverse,target)
        for _,axis in ipairs({"x","y","z"}) do local_target[axis]=local_target[axis]/scale end
        feet[side]={target=local_target,normal=normal,weight=supported and a.vault_time<0 and 1 or 0,stance=not swing}
        if supported and not swing then drop=math.min(drop,(ground.y-e.position.y)/scale) end
    end
    local wanted=V.clamp(drop,-.32,0)
    a.pelvis=a.pelvis+(wanted-a.pelvis)*math.min(1,dt*16)
    a.targets=feet;a.previous=V.copy(e.position);a.previous_yaw=e.yaw
end
function M.sample(e)
    local a=e.animation
    if not a then return {} end
    local hit=a.hit_time<=.5 and math.exp(-a.hit_time*7.5)*math.min(1,a.hit_time*22)*a.hit_strength or 0
    return {variant=e.variant or "vanguard",run=e.run or 0,wounded=V.clamp((.45-e.actor.health/e.actor.max_health)/.25,0,1),
        aim_yaw=e.aim_yaw or 0,feet=clone(a.targets),pelvis=a.pelvis,hit=hit,hit_region=a.hit_region,hit_side=a.hit_side,
        turn=math.max(0,a.turn_time)/.42,turn_weight=a.turn_time>=0 and 1 or 0,turn_direction=a.turn_direction,
        reload=math.max(0,a.reload_time)/a.reload_duration,reload_weight=a.reload_time>=0 and 1 or 0,
        vault=math.max(0,a.vault_time)/a.vault_duration,vault_weight=a.vault_time>=0 and 1 or 0,vault_hand=clone(a.vault_hand)}
end
function M.interpolate(previous,current,alpha)
    local out={}
    for key,value in pairs(current) do
        local from=previous and previous[key]
        if type(value)=="number" and type(from)=="number" then out[key]=V.lerp(from,value,alpha)
        elseif type(value)=="table" then out[key]=M.interpolate(from,value,alpha)
        else out[key]=value end
    end
    -- A completed one-shot blends toward its end, never backwards to frame 0.
    for _,clip in ipairs({"turn","reload","vault"}) do
        if previous and previous[clip.."_weight"]==1 and current[clip.."_weight"]==0 then
            out[clip]=V.lerp(previous[clip],1,alpha)
        end
    end
    return out
end
return M
