-- Animation clocks and planted contacts advance only with fixed simulation.
local V=require "game.weapons.math"
local T=require "game.ai.transform"
local variants=require "game.ai.variants"
local M={}
local function wrap(v) return (v+math.pi)%(2*math.pi)-math.pi end
local clips={"turn","reload","vault","throw"}
local function clone(value,out)
    if type(value)~="table" then return value end
    out=type(out)=="table" and out or {}
    for k in pairs(out) do if value[k]==nil then out[k]=nil end end
    for k,v in pairs(value) do out[k]=clone(v,out[k]) end
    return out
end
function M.init(e)
    e.animation={feet={},pelvis=0,turn_time=-1,turn_direction=1,reload_time=-1,reload_duration=2.4,
        vault_time=-1,vault_duration=.85,throw_time=-1,throw_duration=.9,hit_time=1,hit_region="torso",hit_side=1,hit_strength=0,
        previous=V.copy(e.position),previous_yaw=e.yaw}
end
function M.reload(e,duration)
    if not e.actor.alive then return false end
    local a=e.animation;if a.reload_time>=0 or a.vault_time>=0 or a.throw_time>=0 then return false end
    a.reload_time=0;a.reload_duration=math.max(.1,duration or (e.variant=="irregular" and 2.9 or 2.35));return true
end
function M.throw(e,duration)
    local a=e.animation
    if not e.actor.alive or a.reload_time>=0 or a.vault_time>=0 or a.throw_time>=0 then return false end
    a.throw_time=0;a.throw_duration=duration;return true
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
local function ground_ray(foot,query,x,y,z,length,planted)
    -- Only adapters restricted to versioned static geometry can retain a hit.
    -- Consume the proof on every call: swings, misses and pending world edits
    -- must not leave an old contact available when the foot plants again.
    local cached=foot.ground;foot.ground=nil
    local revision
    if planted and query and query.clearance_revision then revision=query:clearance_revision() end
    if revision~=nil and cached and cached.query==query
        and cached.ray==query.ray and cached.revision_fn==query.clearance_revision
        and cached.revision==revision and cached.x==x and cached.z==z and cached.length==length
        -- The original ray proved this vertical span clear above the hit.
        -- Lowering its origin is safe while it still contains that first hit;
        -- raising it needs a fresh query for the newly exposed space.
        and y<=cached.y and y>=cached.hit.y and y-length<=cached.hit.y then
        foot.ground=cached
        if profiler then profiler.scope_begin("animation.ground_reuse");profiler.scope_end() end
        return cached.hit
    end
    local hit=query and query.ray and query:ray({x=x,y=y,z=z},0,-length,0)
    -- Copy the hit because query adapters may return a mutable scratch object.
    if hit and revision~=nil and query:clearance_revision()==revision then
        cached=cached or {}
        cached.query,cached.ray,cached.revision_fn,cached.revision=query,query.ray,query.clearance_revision,revision
        cached.x,cached.y,cached.z,cached.length=x,y,z,length
        cached.hit=clone(hit,cached.hit);foot.ground=cached
    end
    return hit
end
function M.step(e,dt,query)
    local a=e.animation
    if not e.actor.alive then
        a.feet={};a.reload_time=-1;a.vault_time=-1;a.turn_time=-1;a.throw_time=-1;return
    end
    a.hit_time=math.min(1,a.hit_time+dt)
    advance(a,"reload_time",a.reload_duration,dt);advance(a,"vault_time",a.vault_duration,dt);advance(a,"turn_time",.42,dt)
    advance(a,"throw_time",a.throw_duration,dt)
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
        if profiler then profiler.scope_begin("animation.ground_ray") end
        local ground=ground_ray(foot,query,target.x,e.position.y+.62*scale,target.z,1.1*scale,
            not swing and a.vault_time<0)
        if profiler then profiler.scope_end() end
        local supported=ground and ground.ny>=.707 and math.abs(ground.y-e.position.y)<.46*scale
        if not supported then foot.ground=nil end
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
-- Optional destinations are caller-owned snapshots, never the live animation.
function M.sample(e,out)
    out=out or {}
    local a=e.animation
    if not a then for k in pairs(out) do out[k]=nil end;return out end
    local hit=a.hit_time<=.5 and math.exp(-a.hit_time*7.5)*math.min(1,a.hit_time*22)*a.hit_strength or 0
    out.variant,out.run,out.wounded=e.variant or "vanguard",e.run or 0,V.clamp((.45-e.actor.health/e.actor.max_health)/.25,0,1)
    out.aim_yaw,out.feet,out.pelvis=e.aim_yaw or 0,clone(a.targets,out.feet),a.pelvis
    out.hit,out.hit_region,out.hit_side=hit,a.hit_region,a.hit_side
    out.turn,out.turn_weight,out.turn_direction=math.max(0,a.turn_time)/.42,a.turn_time>=0 and 1 or 0,a.turn_direction
    out.reload,out.reload_weight=math.max(0,a.reload_time)/a.reload_duration,a.reload_time>=0 and 1 or 0
    out.throw,out.throw_weight=math.max(0,a.throw_time)/a.throw_duration,a.throw_time>=0 and 1 or 0
    out.vault,out.vault_weight,out.vault_hand=math.max(0,a.vault_time)/a.vault_duration,a.vault_time>=0 and 1 or 0,clone(a.vault_hand,out.vault_hand)
    return out
end
function M.interpolate(previous,current,alpha,out)
    out=type(out)=="table" and out or {}
    for key in pairs(out) do if current[key]==nil then out[key]=nil end end
    for key,value in pairs(current) do
        local from=previous and previous[key]
        if type(value)=="number" and type(from)=="number" then out[key]=V.lerp(from,value,alpha)
        elseif type(value)=="table" then out[key]=M.interpolate(from,value,alpha,out[key])
        else out[key]=value end
    end
    -- A completed one-shot blends toward its end, never backwards to frame 0.
    for _,clip in ipairs(clips) do
        if previous and previous[clip.."_weight"]==1 and current[clip.."_weight"]==0 then
            out[clip]=V.lerp(previous[clip],1,alpha)
        end
    end
    return out
end
return M
