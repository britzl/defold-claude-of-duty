package.path = "./?.lua;"..package.path
local runtime = require "game.runtime"
local combat = require "game.combat"
local events = require "game.events"
local player = require "game.systems.player"
local health = require "game.player.health"
local T = require "game.player.health_tuning"
local ballistics = require "game.weapons.ballistics"
local h,count = 1/120,0
local function near(a,b,e) assert(math.abs(a-b)<(e or 1e-7),a.." != "..b) end
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function ticks(ctx,n) for _=1,n do runtime.fixed_update(ctx,h) end end
local function new()
    local q={}
    function q:sync() end
    function q:ray() return self.blocked and {x=0,y=1,z=0} or nil end
    function q:contacts(p) return p.y<0 and {{distance=p.y,nx=0,ny=1,nz=0}} or {} end
    function q:fits(p) return p.y>=-0.0001 end
    function q:camera_fraction() return 1 end
    function q:sweep(p,_,_,dy)
        if dy<0 and p.y+dy<=0 then return {fraction=-p.y/dy,nx=0,ny=1,nz=0} end
    end
    local ctx=runtime.new({capsule=q})
    ctx.world.ready=true;ctx.ai.enabled=false
    player.reset(ctx,{x=0,y=0.01,z=0},0);ticks(ctx,2)
    return ctx
end
local function hit(ctx,amount,extra)
    local cue=extra or {};cue.target="player";cue.amount=amount
    assert(combat.request(ctx.combat,cue));ticks(ctx,1)
end
local function segment(ctx,round,x)
    local y=ctx.player.position.y+ctx.player.motion.eye
    events.emit(ctx.events,events.BULLET_SEGMENT,{source="enemy_1",round=round,
        from={x=x,y=y,z=-8},to={x=x,y=y,z=8}})
end
test("recovery starts after 4.6 seconds, ramps for .55 seconds and caps at maximum",function()
    local ctx=new();hit(ctx,80);ticks(ctx,552)
    near(ctx.player.actor.health,20);assert(not ctx.player.actor.regenerating)
    ticks(ctx,33)
    local expected=20+34*h*(h/.55)*(33*34/2)
    near(ctx.player.actor.health,expected)
    assert(ctx.player.actor.regenerating)
    ticks(ctx,33);local before=ctx.player.actor.health;ticks(ctx,120)
    near(ctx.player.actor.health-before,34)
    ticks(ctx,200);near(ctx.player.actor.health,100);assert(not ctx.player.actor.regenerating)
    runtime.final(ctx)
end)
test("a new hit cancels recovery and resets its delay; enemies do not regenerate",function()
    local ctx=new();hit(ctx,70);ticks(ctx,620)
    assert(ctx.player.actor.regenerating)
    local before=ctx.player.actor.health;hit(ctx,5)
    near(ctx.player.actor.health,before-5);assert(not ctx.player.actor.regenerating)
    ticks(ctx,552);near(ctx.player.actor.health,before-5)
    local enemy=combat.register(ctx.combat,"dummy",100)
    combat.request(ctx.combat,{target="dummy",amount=50});ticks(ctx,1200)
    near(enemy.health,50);runtime.final(ctx)
end)
test("loading and disabled inspection freeze recovery",function()
    local ctx=new();hit(ctx,60)
    ctx.world.ready=false;ticks(ctx,900);near(ctx.player.actor.health,40)
    near(ctx.player.actor.since_damage,0)
    ctx.world.ready=true;ctx.player.enabled=false;ticks(ctx,900)
    near(ctx.player.actor.since_damage,0);near(ctx.player.actor.health,40)
    runtime.final(ctx)
end)
test("pause and render-only updates freeze pools, pulse, recovery and heartbeat events",function()
    local ctx=new();local beats=0
    events.on(ctx.events,events.PLAYER_HEARTBEAT,ctx,function() beats=beats+1 end)
    hit(ctx,90);ticks(ctx,100)
    local before=health.snapshot(ctx);local phase=ctx.player.health_state.phase;local old_beats=beats
    for _=1,100 do runtime.update(ctx,1/30) end
    near(ctx.player.health_state.phase,phase)
    runtime.set_paused(ctx,true)
    for _=1,900 do runtime.fixed_update(ctx,h);runtime.update(ctx,h) end
    for k,v in pairs(before) do assert(health.snapshot(ctx)[k]==v,k) end
    assert(beats==old_beats)
    runtime.set_paused(ctx,false);ticks(ctx,900);near(ctx.player.actor.health,100)
    runtime.final(ctx)
end)
test("landing damage uses impact speed once, leaving ordinary jumps and small drops safe",function()
    for _,height in ipairs({1,3,9,24}) do
        local ctx=new();local hits,amount,speed=0,0,0
        events.on(ctx.events,events.DAMAGE_TAKEN,ctx,function(_,e)
            if e.kind=="fall" then hits=hits+1;amount=e.amount end
        end)
        events.on(ctx.events,events.PLAYER_LAND,ctx,function(_,e) speed=e.velocity end)
        player.reset(ctx,{x=0,y=height,z=0},0)
        repeat ticks(ctx,1) until ctx.player.motion.grounded
        ticks(ctx,2)
        local expected=math.min(100,math.max(0,speed-15)*7)
        near(amount,expected);near(ctx.player.actor.health,100-expected)
        assert(hits==(expected>0 and 1 or 0));ticks(ctx,120);assert(hits<=1)
        runtime.final(ctx)
    end
end)
test("actual projectile segments suppress without tracers or health damage",function()
    local ctx=new();local sim=ballistics.new();local def=require("game.weapons.defs").rifle
    ballistics.spawn(sim,def,{x=1,y=1.67,z=-4},{x=0,y=0,z=1},"enemy_1",false)
    ballistics.update(ctx,sim,h,nil)
    assert(ctx.player.health_state.suppression>0 and ctx.player.camera.yaw.x<0)
    near(ctx.player.actor.health,100);runtime.final(ctx)
end)
test("one round contributes only its strongest segment, impact or hit",function()
    local ctx=new();local round={}
    segment(ctx,round,1)
    local pressure=ctx.player.health_state.suppression
    for _=1,50 do segment(ctx,round,1) end
    near(ctx.player.health_state.suppression,pressure)
    segment(ctx,round,0.5)
    near(ctx.player.health_state.suppression,.28*(1-.5/3.2))
    hit(ctx,18,{round=round,from={x=1,y=1.7,z=0}})
    near(ctx.player.health_state.suppression,.5*(.5+18/45)-T.suppression.decay*h)
    assert(ctx.player.health_state.stimuli==1)
    local y=ctx.player.position.y+ctx.player.motion.eye
    events.emit(ctx.events,events.BULLET_IMPACT,{source="enemy_1",round=round,point={x=0,y=y,z=0}})
    assert(ctx.player.health_state.stimuli==1)
    ticks(ctx,200);near(ctx.player.health_state.suppression,0);runtime.final(ctx)
end)
test("cover, self-fired rounds, exits, distant and degenerate segments do not suppress",function()
    local ctx=new();ctx.services.capsule.blocked=true;segment(ctx,{},1)
    near(ctx.player.health_state.suppression,0);ctx.services.capsule.blocked=false
    segment(ctx,{},4)
    local p={x=0,y=1.67,z=0}
    events.emit(ctx.events,events.BULLET_SEGMENT,{source="enemy_1",round={},from=p,to=p})
    events.emit(ctx.events,events.BULLET_SEGMENT,{source="player",round={},from=p,to={x=0,y=1.67,z=2}})
    events.emit(ctx.events,events.BULLET_IMPACT,{source="enemy_1",round={},point=p,exit=true})
    near(ctx.player.health_state.suppression,0);runtime.final(ctx)
end)
test("explosions give bounded directional feedback through cover without applying damage",function()
    local ctx=new();ctx.services.capsule.blocked=true
    local cue={position={x=-1,y=1.67,z=0},radius=5,damage=90,token={}}
    events.emit(ctx.events,events.EXPLOSION,cue)
    assert(ctx.player.health_state.suppression>0 and ctx.player.camera.yaw.x>0)
    local before=ctx.player.health_state.suppression
    events.emit(ctx.events,events.EXPLOSION,cue);near(ctx.player.health_state.suppression,before)
    for _=1,20 do events.emit(ctx.events,events.EXPLOSION,{position=cue.position,radius=5}) end
    near(ctx.player.health_state.suppression,1);near(ctx.player.actor.health,100)
    assert(#ctx.combat.pending==0)
    runtime.final(ctx)
end)
test("visibility rays start at the clear eye when a round ends inside solid cover",function()
    local ctx=new();local probes=0
    function ctx.services.capsule:ray(origin,dx,dy,dz)
        probes=probes+1;near(origin.x,ctx.player.position.x);near(dx,1)
        return {x=.9,y=origin.y,z=0}
    end
    segment(ctx,{},1)
    assert(probes==1);near(ctx.player.health_state.suppression,0);runtime.final(ctx)
end)
test("source positions are copied at firing and damage queue time",function()
    local ctx=new();local from={x=3,y=2,z=0}
    combat.request(ctx.combat,{target="player",amount=10,from=from});from.x=-3;ticks(ctx,1)
    assert(ctx.player.camera.yaw.x<0 and ctx.hud.source.x==3)
    runtime.final(ctx)
end)
test("low health publishes pulse/recovery states; death stops beats and cannot heal",function()
    local ctx=new();local beats,states=0,0
    events.on(ctx.events,events.PLAYER_HEARTBEAT,ctx,function() beats=beats+1 end)
    events.on(ctx.events,events.PLAYER_HEALTH,ctx,function() states=states+1 end)
    hit(ctx,90);ticks(ctx,200)
    local s=health.snapshot(ctx);assert(s.low and s.critical and s.effect>.7 and s.heartbeat_hz>1.7)
    assert(beats>0 and states>1)
    hit(ctx,999);local stopped=beats;ticks(ctx,1600)
    s=health.snapshot(ctx)
    assert(s.dead and not s.regenerating and s.health==0 and s.pulse==0 and s.heartbeat_hz==0 and beats==stopped)
    near(s.suppression,0);segment(ctx,{},1);near(s.suppression,0)
    combat.request(ctx.combat,{target="player",amount=1})
    combat.remove(ctx.combat,"player")
    ctx.player.actor=combat.register(ctx.combat,"player",100,T.regeneration)
    health.reset(ctx);player.reset(ctx,{x=0,y=.01,z=0},0);ticks(ctx,1)
    s=health.snapshot(ctx);assert(s.health==100 and not s.low and not s.regenerating and s.effect==0 and s.suppression==0)
    runtime.final(ctx)
end)
test("health and pulse agree at 30, 60 and 144 presentation FPS without consuming weapon RNG",function()
    local reference,random
    for _,fps in ipairs({30,60,144}) do
        local ctx=new();hit(ctx,85);local acc=0
        for _=1,fps*6 do
            acc=acc+1/fps
            while acc+1e-10>=h do runtime.fixed_update(ctx,h);acc=acc-h end
            runtime.update(ctx,1/fps)
        end
        local s=health.snapshot(ctx)
        if reference then
            for _,k in ipairs({"health","effect","pulse","suppression","since_damage"}) do near(s[k],reference[k]) end
            near(ctx.weapons.random(),random)
        else reference=s;random=ctx.weapons.random() end
        runtime.final(ctx)
    end
end)
print(count.." health tests passed")
