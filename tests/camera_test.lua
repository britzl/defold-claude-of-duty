package.path = "./?.lua;"..package.path
local runtime = require "game.runtime"
local input = require "game.input"
local player = require "game.systems.player"
local camera = require "game.player.camera"
local events = require "game.events"
local combat = require "game.combat"
local T = require "game.player.tuning"
local h, count = 1/120, 0
local function near(a,b,e) assert(math.abs(a-b)<(e or 1e-8), a.." != "..b) end
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function query()
    local q = {}
    function q:sync() end
    function q:ray() end
    function q:contacts(p) return p.y<0 and {{distance=p.y,nx=0,ny=1,nz=0}} or {} end
    function q:fits(p) return p.y>=-0.0001 end
    function q:camera_fraction() return 1 end
    function q:sweep(p,_,_,dy)
        if dy<0 and p.y+dy<=0 then return {fraction=-p.y/dy,nx=0,ny=1,nz=0} end
    end
    return q
end
local function new()
    local ctx=runtime.new({capsule=query()})
    ctx.world.ready=true;ctx.ai.enabled=false
    player.reset(ctx,{x=0,y=T.skin,z=0},0)
    runtime.fixed_update(ctx,h)
    return ctx
end
local function ticks(ctx,n) for _=1,n do runtime.fixed_update(ctx,h) end end
local function button(ctx,key,down) input.button(ctx.input,key,{pressed=down,released=not down}) end
local function snap(ctx) return camera.compose(ctx,1,{}) end

test("breathing moves only the eye and never integrates on render frames",function()
    local ctx=new();ticks(ctx,120)
    local before=snap(ctx)
    assert(math.abs(before.pitch)>1e-5 and math.abs(before.camera.y-ctx.player.position.y-1.66)>1e-5)
    local state=ctx.player.camera.current
    local y,pitch,phase=state.y,state.pitch,ctx.player.camera.breath
    for _=1,300 do runtime.update(ctx,1/144) end
    near(state.y,y);near(state.pitch,pitch);near(ctx.player.camera.breath,phase)
    near(ctx.player.position.x,0);near(ctx.player.position.z,0)
    runtime.final(ctx)
end)

test("bob phase and footfall springs follow distance, including stance and landing resets",function()
    local ctx=new();button(ctx,"forward",true)
    local steps=0
    events.on(ctx.events,events.PLAYER_FOOTSTEP,ctx,function() steps=steps+1 end)
    ticks(ctx,240)
    local r=ctx.player.camera
    local phase=(steps+ctx.player.footstep_distance/T.stances.stand.stride)*math.pi%(math.pi*4)
    near(r.phase,phase,1e-7)
    assert(steps>=5 and r.weight>0.99 and math.abs(r.step.x)>1e-7)
    button(ctx,"jump",true);runtime.fixed_update(ctx,h);button(ctx,"jump",false)
    ticks(ctx,20);assert(r.weight<0.3)
    ticks(ctx,80)
    assert(ctx.player.motion.grounded and math.abs(r.phase)>0)
    runtime.final(ctx)
end)

test("landing dip, pitch and roll scale with impact and recover",function()
    local soft,hard=camera.new(),camera.new()
    camera.land(soft,2);near(soft.dip.v,0)
    camera.land(soft,4);camera.land(hard,12.5)
    assert(hard.dip.v<soft.dip.v and hard.pitch.x>soft.pitch.x and hard.roll.x>soft.roll.x)
    local ctx=new();ctx.player.camera=hard
    ticks(ctx,10);assert(hard.dip.x < -0.03)
    ticks(ctx,350)
    assert(math.abs(hard.dip.x)<1e-7 and math.abs(hard.pitch.x)<1e-7 and hard.trauma==0)
    runtime.final(ctx)
end)

test("strafe and turn banking have the reference sign and stay bounded",function()
    local ctx=new();button(ctx,"right",true);ticks(ctx,90)
    assert(ctx.player.camera.strafe < -math.rad(1))
    for _=1,150 do input.look(ctx.input,-10,0);runtime.fixed_update(ctx,h) end
    near(ctx.player.camera.turn,T.camera.roll.turn_max,0.0001)
    button(ctx,"right",false);ticks(ctx,240)
    assert(math.abs(ctx.player.camera.strafe)<1e-7 and math.abs(ctx.player.camera.turn)<1e-6)
    runtime.final(ctx)
end)

test("sprint, tactical sprint, slide and weapon ADS compose a smooth bounded FOV",function()
    local ctx=new();button(ctx,"forward",true);button(ctx,"sprint",true)
    ticks(ctx,150);near(snap(ctx).fov,math.rad(70)*1.055,0.0001)
    button(ctx,"sprint",false);ticks(ctx,1);button(ctx,"sprint",true);ticks(ctx,8)
    button(ctx,"sprint",false);ticks(ctx,1);button(ctx,"sprint",true);ticks(ctx,120)
    assert(ctx.player.motion.tactical);near(snap(ctx).fov,math.rad(77),0.0002)
    button(ctx,"crouch",true);ticks(ctx,40)
    assert(ctx.player.motion.sliding and ctx.player.camera.slide>0.7)
    assert(snap(ctx).fov>math.rad(75) and ctx.player.camera.current.y<0)
    input.reset(ctx.input);ticks(ctx,180)
    button(ctx,"aim",true);ticks(ctx,180)
    local defs=require "game.weapons.defs"
    near(snap(ctx).fov,math.rad(70)*defs.rifle.adsFov,1e-7)
    button(ctx,"aim",false)
    local old=snap(ctx).fov;runtime.fixed_update(ctx,h)
    assert(snap(ctx).fov>old and snap(ctx).fov<math.rad(70))
    ticks(ctx,240);near(snap(ctx).fov,math.rad(70),1e-7)
    runtime.final(ctx)
end)

test("directional channels are bounded, independent of damage, and do not consume weapon RNG",function()
    local a,b=new(),new()
    for _,kind in ipairs({"damage","suppression","explosion"}) do
        player.camera_impulse(a,kind,1,{x=1,y=0,z=0})
    end
    assert(a.player.camera.yaw.x<0 and a.player.camera.roll.x<0 and a.player.camera.suppression==1)
    near(a.player.actor.health,100);near(a.weapons.random(),b.weapons.random())
    for _=1,100 do player.camera_impulse(a,"explosion",1,{x=1,z=-1}) end
    assert(math.abs(a.player.camera.pitch.x)<=0.25 and a.player.camera.trauma==1)
    ticks(a,600);near(a.player.camera.yaw.x,0);near(a.player.camera.roll.x,0)
    assert(not pcall(camera.impulse,a.player.camera,"damage",0/0,nil,0))
    runtime.final(a);runtime.final(b)
end)

test("damage events feed the rig; pause freezes it; death and reset clear it",function()
    local ctx=new()
    combat.request(ctx.combat,{target="player",amount=10});runtime.fixed_update(ctx,h)
    assert(ctx.player.camera.pitch.x>0)
    runtime.update(ctx,h)
    local r=ctx.player.camera;local pitch,breath=r.pitch.x,r.breath
    local p=ctx.presentation.pitch
    runtime.set_paused(ctx,true)
    for _=1,120 do runtime.fixed_update(ctx,h);runtime.update(ctx,h) end
    near(r.pitch.x,pitch);near(r.breath,breath);near(ctx.presentation.pitch,p)
    assert(not player.camera_impulse(ctx,"explosion",1))
    player.reset(ctx,{x=2,y=T.skin,z=1},1)
    near(ctx.presentation.camera.x,2);near(ctx.presentation.yaw,1);near(ctx.presentation.fov,math.rad(70))
    near(r.trauma,0);near(r.breath,0)
    breath=0
    runtime.set_paused(ctx,false);runtime.fixed_update(ctx,h);assert(r.breath>breath)
    combat.request(ctx.combat,{target="player",amount=1000});runtime.fixed_update(ctx,h)
    near(r.pitch.x,0);near(r.current.roll,0);near(r.breath,0)
    player.reset(ctx,{x=2,y=T.skin,z=1},1)
    local eye=snap(ctx);near(eye.yaw,1);near(eye.fov,math.rad(70));near(eye.camera.x,2)
    runtime.final(ctx)
end)

test("camera offsets are swept and keep headroom, including interpolated lean",function()
    local ctx=new();local r=ctx.player.camera
    r.current.x,r.current.y,r.current.z=0.2,0.5,0.2
    ctx.player.motion.height=1.12;ctx.player.motion.eye=1.02
    local probes=0
    function ctx.services.capsule:camera_fraction(_,dx,dy,dz,radius)
        probes=probes+1;assert(radius==0.09);assert(dy<=1e-8);return 0.25
    end
    local eye=snap(ctx)
    assert(probes==1);near(eye.camera.x,0.05);near(eye.camera.z,-0.05)
    assert(eye.camera.y<=ctx.player.position.y+1.02+1e-8)
    near(ctx.player.position.x,0)
    runtime.final(ctx)
end)

test("camera state and interpolated poses match at 30, 60 and 144 presentation FPS",function()
    local reference
    for _,fps in ipairs({30,60,144}) do
        local ctx=new();local acc=0
        for _=1,fps*3 do
            acc=acc+1/fps
            while acc+1e-10>=h do
                local tick=ctx.time.tick
                if tick==1 then button(ctx,"forward",true);button(ctx,"sprint",true) end
                if tick==60 then button(ctx,"crouch",true) end
                if tick==80 then button(ctx,"jump",true) end
                if tick==81 then button(ctx,"jump",false) end
                if tick==200 then input.reset(ctx.input);button(ctx,"aim",true) end
                if tick==260 then player.camera_impulse(ctx,"suppression",0.6,{x=1,z=-1}) end
                runtime.fixed_update(ctx,h);acc=acc-h
            end
            runtime.update(ctx,1/fps)
        end
        local samples={}
        for _,alpha in ipairs({0,0.25,0.75,1}) do
            local o=camera.compose(ctx,alpha,{})
            for _,value in ipairs({o.camera.x,o.camera.y,o.camera.z,o.pitch,o.yaw,o.roll,o.fov}) do samples[#samples+1]=value end
        end
        if reference then for i,value in ipairs(samples) do near(value,reference[i]) end else reference=samples end
        runtime.final(ctx)
    end
end)

test("zero-spread shots use the composed eye and aim at the pitch limit",function()
    local ctx=new();ticks(ctx,120);local d=require("game.weapons.defs").rifle
    local old_hip,old_ads=d.spreadHip,d.spreadAds
    d.spreadHip,d.spreadAds=0,0;ctx.weapons.spread=0
    ctx.player.motion.pitch=T.pitch_limit
    player.camera_impulse(ctx,"explosion",0.8,{x=1,z=-1})
    local shot
    events.on(ctx.events,events.WEAPON_FIRE,ctx,function(_,event) shot=event end)
    button(ctx,"fire",true);runtime.fixed_update(ctx,h)
    local eye=snap(ctx)
    assert(shot)
    near(shot.origin.x,eye.camera.x);near(shot.origin.y,eye.camera.y);near(shot.origin.z,eye.camera.z)
    local dir=require("game.weapons.math").rotate({x=0,y=0,z=-1},eye.pitch,eye.yaw,0)
    near(shot.dir.x,dir.x);near(shot.dir.y,dir.y);near(shot.dir.z,dir.z)
    d.spreadHip,d.spreadAds=old_hip,old_ads
    runtime.final(ctx)
end)

print(count.." camera tests passed")
