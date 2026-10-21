local defs = require "game.weapons.defs"
local V = require "game.weapons.math"
local clips = require "game.weapons.clips"
local ballistics = require "game.weapons.ballistics"
local events = require "game.events"
local rng = require "game.rng"
local camera = require "game.player.camera"
local player_tuning = require "game.player.tuning"
local view_motion = require "game.weapons.motion"
local M = {}
local ids={"rifle","smg","pistol"}

local function pattern(def)
    local r=def.recoil
    local random=rng.new(r.patternSeed)
    local phase,phase2,bias=random()*math.pi*2,random()*math.pi*2,(random()*2-1)*.35
    local out={}
    for i=0,r.patternLength-1 do
        local pitch=r.pitch*r.climbShape[math.min(i+1,#r.climbShape)]*(.88+random()*.24)
        local t=i/math.max(1,r.patternLength-1)
        local snake=math.sin(phase+t*math.pi*2.6)*.75+math.sin(phase2+t*math.pi*5.1)*.35
        out[i+1]={pitch,r.yaw*(snake*r.drift*3.2+bias+(random()*2-1)*.25)}
    end
    return out
end
local function transition(w)
    if w.clip then w.clip_transition={name=w.clip,progress=w.clip_time/w.clip_duration,age=0} end
end
local function play(w,name)
    w.clip=name;w.clip_time=0;w.clip_duration=clips.duration(name,defs[w.equipped]);w.beat=1
end
local function cancel(ctx)
    local w=ctx.weapons
    transition(w)
    if w.clip=="reloadTac" or w.clip=="reloadEmpty" then
        events.emit(ctx.events,events.WEAPON_RELOAD,{weapon=w.equipped,phase="cancel"})
    end
    w.clip=nil;w.clip_time=0;w.switch_to=nil;w.burst=0
end
function M.init(ctx)
    local w={equipped="rifle",inventory={},intent={},sim=ballistics.new(ctx.world.seed,"player"),
        cooldown=0,burst=0,burst_cooldown=0,since_shot=10,shot_index=0,ads=0,previous_ads=0,
        spread=defs.rifle.spreadHip,random=rng.new(ctx.world.seed,"weapons"),shells={},
        recoil={pitch=V.spring(),yaw=V.spring(),back=V.spring(),up=V.spring(),roll=V.spring()},
        previous_recoil={},dry=0,flash=0,motion=view_motion.new()}
    ctx.weapons=w
    for _,id in ipairs(ids) do
        local d=defs[id]
        w.inventory[id]={mag=d.magSize,chambered=true,reserve=d.reserve,mode=1,pattern=pattern(d)}
    end
    for key in pairs(w.recoil) do w.previous_recoil[key]=0 end
    play(w,"draw")
end
function M.select(ctx,id)
    local w=ctx.weapons
    if not defs[id] or id==w.equipped or w.switch_to or not ctx.player.actor.alive then return false end
    cancel(ctx);w.switch_to=id;play(w,"holster")
    return true
end
local function reload(ctx)
    local w=ctx.weapons
    local s,d=w.inventory[w.equipped],defs[w.equipped]
    if w.switch_to or w.clip=="draw" or w.clip=="reloadTac" or w.clip=="reloadEmpty"
        or (s.chambered and (s.mag>=d.magSize or s.reserve<=0))
        or (not s.chambered and s.mag==0 and s.reserve<=0) then return end
    w.burst=0
    play(w,s.chambered and "reloadTac" or "reloadEmpty")
end
local function advance_clip(ctx,dt)
    local w=ctx.weapons
    if not w.clip then return end
    w.clip_time=w.clip_time+dt
    local beats=clips.beats[w.clip]
    while beats and beats[w.beat] and w.clip_time+1e-9>=beats[w.beat][1]*w.clip_duration do
        local phase=beats[w.beat][2]
        local s,d=w.inventory[w.equipped],defs[w.equipped]
        if phase=="magin" then
            local take=math.min(d.magSize-s.mag,s.reserve)
            s.mag=s.mag+take;s.reserve=s.reserve-take;w.shot_index=0
        elseif phase=="boltrelease" and not s.chambered and s.mag>0 then
            s.mag=s.mag-1;s.chambered=true
        end
        events.emit(ctx.events,events.WEAPON_RELOAD,{weapon=w.equipped,phase=phase})
        w.beat=w.beat+1
    end
    if w.clip_time+1e-9>=w.clip_duration then
        if w.clip=="holster" and w.switch_to then
            w.equipped=w.switch_to;w.switch_to=nil;w.shot_index=0;w.spread=defs[w.equipped].spreadHip
            w.clip_transition=nil
            w.cooldown=0;w.burst_cooldown=0;play(w,"draw")
        else w.clip=nil;w.clip_time=0 end
    end
end
local function fire(ctx)
    local w=ctx.weapons
    local s,d=w.inventory[w.equipped],defs[w.equipped]
    if w.cooldown>1e-9 or (w.clip and w.clip~="inspect") then return false end
    if not s.chambered then
        w.cooldown=.25;w.dry=w.dry+1
        events.emit(ctx.events,events.WEAPON_DRY,{weapon=w.equipped})
        return false
    end
    if w.clip=="inspect" then transition(w) end
    w.clip=nil;w.clip_time=0
    s.chambered=s.mag>0
    if s.chambered then s.mag=s.mag-1 end
    local motion=ctx.player.motion
    local eye=camera.compose(ctx,1,{})
    local pitch=V.clamp(eye.pitch+w.recoil.pitch.x,-player_tuning.pitch_limit,player_tuning.pitch_limit)
    local yaw=eye.yaw+w.recoil.yaw.x
    local radius=math.sqrt(w.random())*math.tan(math.rad(w.spread))
    local angle=w.random()*2*math.pi
    local dir=V.normalize(V.rotate({x=radius*math.cos(angle),y=radius*math.sin(angle),z=-1},pitch,yaw,0))
    local origin=eye.camera
    -- Eye-origin rule: all cover on the aim ray is tested, including cover before
    -- the rendered muzzle. Muzzle-only overlap does not block a clear eye ray.
    -- Flash uses the independent viewmodel; presentation never moves the round.
    ballistics.spawn(w.sim,d,origin,dir,"player",w.sim.fired%d.tracerEvery==0)
    local recoil=s.pattern[math.min(w.shot_index+1,#s.pattern)]
    local scale=V.lerp(1,.7,w.ads)
    w.recoil.pitch.x=w.recoil.pitch.x+recoil[1]*scale
    w.recoil.yaw.x=w.recoil.yaw.x+recoil[2]*scale
    w.recoil.back.v=w.recoil.back.v+d.recoil.kickBack*2*math.pi*d.recoil.freq
    w.recoil.up.v=w.recoil.up.v+d.recoil.kickUp*2*math.pi*d.recoil.freq
    w.recoil.roll.v=w.recoil.roll.v+d.recoil.roll*2*math.pi*d.recoil.freq
    w.shot_index=w.shot_index+1;w.since_shot=0;w.flash=.045
    w.spread=math.min(math.max(w.spread,d.spreadMax),w.spread+d.spreadPerShot)
    w.cooldown=w.cooldown+60/d.rpm
    w.shells[#w.shells+1]={time=math.min(.05,60/d.rpm*.45),weapon=d.id,position=V.copy(origin),yaw=yaw}
    events.emit(ctx.events,events.WEAPON_FIRE,{weapon=d.id,origin=origin,dir=dir,shot=w.sim.fired})
    return true
end
function M.fixed_update(ctx,dt)
    local w=ctx.weapons
    w.previous_clip,w.previous_clip_time=w.clip,w.clip_time
    w.previous_since_shot=w.since_shot
    if w.clip_transition then
        w.clip_transition.age=w.clip_transition.age+dt
        if w.clip_transition.age>=.12 then w.clip_transition=nil end
    end
    local b,intent=ctx.input.buttons,w.intent
    local live=ctx.player.actor.alive and ctx.player.enabled
    intent.fire=live and (b.fire.held or b.fire.pressed)
    intent.aim=live and b.aim.held
    intent.reload=live and b.reload.pressed
    intent.inspect=live and b.inspect.pressed
    local ready=live and ctx.world.ready
    w.previous_ads=w.ads
    for key,spring in pairs(w.recoil) do
        w.previous_recoil[key]=spring.x
        local r=defs[w.equipped].recoil
        V.step(spring,dt,(key=="pitch" or key=="yaw") and 2.5 or r.freq,r.damping)
    end
    w.since_shot=w.since_shot+dt
    w.cooldown=w.cooldown>0 and w.cooldown-dt or 0
    w.burst_cooldown=math.max(0,w.burst_cooldown-dt)
    w.flash=math.max(0,w.flash-dt)
    if w.since_shot>.6 then w.shot_index=0 end
    if not ready then
        w.burst=0
        if not live then cancel(ctx) end
    else
        advance_clip(ctx,dt)
        if b.weapon_rifle.pressed then M.select(ctx,"rifle") end
        if b.weapon_smg.pressed then M.select(ctx,"smg") end
        if b.weapon_pistol.pressed then M.select(ctx,"pistol") end
        if b.next_weapon.pressed or b.previous_weapon.pressed then
            local direction=b.previous_weapon.pressed and -1 or 1
            for i,id in ipairs(ids) do if id==(w.switch_to or w.equipped) then M.select(ctx,ids[(i-1+direction)%#ids+1]);break end end
        end
        local s,d=w.inventory[w.equipped],defs[w.equipped]
        if b.fire_mode.pressed and not w.switch_to then s.mode=s.mode%#d.modes+1;w.burst=0 end
        if intent.reload then reload(ctx) end
        if intent.inspect and not w.clip then play(w,"inspect") end
    end
    local d,s=defs[w.equipped],w.inventory[w.equipped]
    local motion=ctx.player.motion
    local usable=ready and not motion.mantle and not motion.sprinting
    local aim=usable and intent.aim and not w.clip
    local ads_target=aim and 1 or 0
    w.ads=w.ads+V.clamp(ads_target-w.ads,-dt/d.adsTime,dt/d.adsTime)
    -- Resolve the fixed camera after ADS and before any round samples its aim.
    if ready then camera.update(ctx,dt) end
    local speed=math.sqrt(motion.velocity.x^2+motion.velocity.z^2)
    local rest=V.lerp(d.spreadHip,d.spreadAds,V.smooth(w.ads))
    rest=rest*(motion.stance=="crouch" and .78 or motion.stance=="prone" and .6 or 1)
    rest=rest*(speed<.4 and .82 or speed>3.2 and 1.15 or 1)
    rest=rest*(motion.sprinting and 2.2 or 1)*(motion.grounded and 1 or 2)
    w.spread=math.max(rest,w.spread-d.spreadDecay*dt*(1+w.ads))
    if usable then
        local dry_press = b.fire.pressed and not s.chambered
        local mode=d.modes[s.mode]
        if mode=="burst" then
            if b.fire.pressed and w.burst==0 and w.burst_cooldown<=0 and (not w.clip or w.clip=="inspect") then w.burst=d.burstCount end
            if w.burst>0 and w.cooldown<=1e-9 then
                if fire(ctx) then
                    w.burst=w.burst-1;w.cooldown=w.cooldown-60/d.rpm+60/d.burstRpm
                    if w.burst==0 then w.burst_cooldown=d.burstDelay end
                else w.burst=0 end
            end
        elseif (mode=="auto" and intent.fire) or (mode=="semi" and b.fire.pressed) then fire(ctx) end
        if dry_press then reload(ctx) end
    else w.burst=0 end
    -- No accumulated fire debt while idle or blocked; fractional intervals are
    -- retained only while firing, keeping 950 rpm accurate on a 120 Hz clock.
    w.cooldown=math.max(0,w.cooldown)
    for i=#w.shells,1,-1 do
        local shell=w.shells[i];shell.time=shell.time-dt
        if shell.time<=0 then
            shell.velocity=V.rotate({x=2.6,y=1.1,z=.25},0,shell.yaw,0)
            events.emit(ctx.events,events.WEAPON_SHELL,shell);table.remove(w.shells,i)
        end
    end
    view_motion.update(ctx,dt,d)
    ballistics.update(ctx,w.sim,dt,ctx.services.bullets)
end
function M.snapshot(ctx)
    local w=ctx.weapons
    local d,s=defs[w.equipped],w.inventory[w.equipped]
    return {weapon=w.equipped,label=d.label,mode=d.modes[s.mode],mag=s.mag,chambered=s.chambered,
        ammo=s.mag+(s.chambered and 1 or 0),reserve=s.reserve,clip=w.clip or "idle",
        progress=w.clip and w.clip_time/w.clip_duration or 0,ads=w.ads,spread=w.spread,
        fired=w.sim.fired,impacts=w.sim.impacts,exits=w.sim.exits,deflections=w.sim.deflections,live=#w.sim.live,dry=w.dry,
        recoil_pitch=w.recoil.pitch.x,recoil_back=w.recoil.back.x}
end
function M.final(ctx) ctx.weapons=nil end
return M
