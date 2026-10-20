package.path="./?.lua;"..package.path
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local tactics=require "game.ai.grenades"
local grenades=require "game.systems.grenades"
local animation=require "game.ai.animation"
local rig=require "game.ai.rig"
local V=require "game.weapons.math"
local events=require "game.events"
local combat=require "game.combat"
local hud=require "game.ui.hud"
local fx=require "game.render.combat_fx"
local h,count=1/120,0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." != "..tostring(b)) end
local function context()
    local ctx=runtime.new();ctx.world.ready=true;ctx.ai.enabled=false
    local e=ai.reset(ctx,{x=0,y=0,z=0},0)
    e.palette,e.joints=rig.pose(ai.pose_state(e))
    e.state="fire";e.grenade_cooldown=0;e.contact_age=0;e.memory=5;e.last_seen={x=0,y=0,z=-16}
    local q={}
    function q:visible() return not self.blocked end
    function q:ray() return self.blocked and {} or nil end
    ctx.services.capsule=q
    local d={api={},items={}}
    function d.api.grenade(a,p,v)
        local b={position=V.copy(p),velocity=V.copy(v),active=true};a.items[#a.items+1]=b;return b
    end
    function d.api.remove_grenade(_,b) b.active=false end
    function d.api.fixed_update() end
    function d.api.remove_actor() end
    function d.api.suspend(a,p) a.paused=p end
    ctx.services.dynamics=d
    ctx.player.position={x=100,y=0,z=100}
    return ctx,e,q
end
local function pose(e) e.palette,e.joints=rig.pose(ai.pose_state(e)) end
local function finish(ctx,e,q)
    for i=1,110 do animation.step(e,h);pose(e);tactics.tick(ctx,e,h);tactics.act(ctx,e,q) end
end

test("source launch ranges, fresh evidence and cooldowns gate throws",function()
    for _,field in ipairs({"range_near","range_far","stale","cooldown","suppressed","reload","vault","walking","duck"}) do
        local ctx,e,q=context()
        if field=="range_near" then e.last_seen.z=-8
        elseif field=="range_far" then e.last_seen.z=-26
        elseif field=="stale" then e.contact_age=1.5
        elseif field=="cooldown" then e.grenade_cooldown=.1
        elseif field=="suppressed" then e.suppressed=true
        elseif field=="reload" then e.animation.reload_time=0
        elseif field=="vault" then e.animation.vault_time=0
        elseif field=="walking" then e.motion.travel=.03
        elseif field=="duck" then e.duck=true end
        assert(not tactics.act(ctx,e,q),field)
        assert(not e.throw_target and ctx.grenades.launched==0,field)
    end
end)
test("one grant per squad, consumed inventory and delayed animated hand release",function()
    local ctx,e,q=context();e.squad="alpha";ctx.ai.squads.alpha={members={e.id},grenade_cooldown=0}
    assert(tactics.act(ctx,e,q));assert(ctx.ai.squads.alpha.grenade_owner==e.id)
    assert(e.has_grenade and ctx.grenades.launched==0)
    local emitted
    events.on(ctx.events,events.GRENADE_THROW,ctx,function(_,ev) emitted=ev end)
    for i=1,57 do animation.step(e,h);pose(e);tactics.act(ctx,e,q) end
    assert(ctx.grenades.launched==0)
    animation.step(e,h);pose(e);local origin=tactics.origin(e);tactics.act(ctx,e,q)
    assert(emitted and not e.has_grenade and e.grenades_thrown==1)
    near(emitted.position.x,origin.x);near(emitted.position.y,origin.y);near(emitted.position.z,origin.z)
    assert(ctx.ai.squads.alpha.grenade_cooldown>=14 and ctx.ai.squads.alpha.grenade_cooldown<=26)
    finish(ctx,e,q);assert(ctx.grenades.launched==1 and not ctx.ai.squads.alpha.grenade_owner)
end)
test("another squad member cannot steal an active grant or bypass squad cooldown",function()
    local ctx,e,q=context();e.squad="alpha"
    ctx.ai.squads.alpha={grenade_owner="enemy_2",grenade_cooldown=0}
    assert(not tactics.act(ctx,e,q));ctx.ai.squads.alpha.grenade_owner=nil;ctx.ai.squads.alpha.grenade_cooldown=1
    assert(not tactics.act(ctx,e,q));tactics.squads(ctx,1);assert(tactics.act(ctx,e,q))
end)
test("failed clearance or capacity never consumes inventory or a squad cooldown",function()
    local ctx,e,q=context();q.blocked=true;assert(not tactics.act(ctx,e,q));assert(e.has_grenade)
    q.blocked=false;e.grenade_retry=0;assert(tactics.act(ctx,e,q));q.blocked=true;finish(ctx,e,q)
    assert(ctx.grenades.launched==0 and e.has_grenade and not e.throw_target)
    q.blocked=false;e.grenade_retry=0
    for i=1,grenades.limit do assert(grenades.launch(ctx,e.id,{x=40,y=2,z=0},{x=0,y=0,z=0})) end
    assert(not tactics.act(ctx,e,q));assert(not grenades.launch(ctx,e.id,e.position,{x=0,y=0,z=0}))
    assert(#ctx.grenades.live==grenades.limit)
end)
test("death, suppression and player death cancel windup and release grants",function()
    for _,why in ipairs({"dead","suppressed","player"}) do
        local ctx,e,q=context();e.squad="alpha";ctx.ai.squads.alpha={grenade_cooldown=0}
        assert(tactics.act(ctx,e,q))
        if why=="dead" then e.actor.alive=false elseif why=="suppressed" then e.suppressed=true else ctx.player.actor.alive=false end
        tactics.tick(ctx,e,h)
        assert(not e.throw_target and not ctx.ai.squads.alpha.grenade_owner and e.has_grenade)
        assert(ctx.grenades.launched==0)
    end
end)
test("ballistic solve handles elevation and rejects unreachable arcs",function()
    for _,height in ipairs({-.5,0,2}) do
        local from={x=0,y=1.8,z=0};local target={x=3,y=height,z=-16}
        local v,t=tactics.solve(from,target);assert(v and t<grenades.fuse)
        near(from.x+v.x*t,target.x);near(from.z+v.z*t,target.z)
        near(from.y+v.y*t-20.6*t*t*.5,target.y)
    end
    assert(not tactics.solve({x=0,y=1,z=0},{x=0,y=30,z=-16}))
    local q={};function q:camera_fraction(p,dx,dy,dz,r) assert(r>grenades.body_radius);return p.z< -4 and 0 or 1 end
    local v,t=tactics.solve({x=0,y=2,z=0},{x=0,y=.15,z=-16})
    assert(not tactics.clear_arc(q,{x=0,y=2,z=0},v,t))
end)
test("allies at blast destination suppress throws and moving targets are not tracked after windup",function()
    local ctx,e,q=context();local ally={id="ally",actor={alive=true},position={x=0,y=0,z=-16}}
    ctx.ai.order[2]="ally";ctx.ai.actors.ally=ally
    assert(not tactics.act(ctx,e,q));ally.position.z=-30;assert(tactics.act(ctx,e,q))
    e.last_seen.z=-100;assert(e.throw_target.z==-16)
    finish(ctx,e,q);assert(ctx.grenades.launched==1)
end)
test("grenade timing RNG is isolated from soldier fire decisions",function()
    local a,e=context();local b,f=context();for i=1,30 do e.grenade_random() end
    for i=1,20 do near(e.random(),f.random()) end
end)
test("fixed fuses ignore rendering, wait for bodies, freeze on pause and detonate once",function()
    local ctx,e=context();ctx.player.enabled=false;ctx.services.capsule=nil
    local g=assert(grenades.launch(ctx,e.id,{x=40,y=2,z=0},{x=1,y=4,z=0}))
    g.body.active=false
    for i=1,10 do runtime.fixed_update(ctx,h) end;near(g.fuse,2.35)
    g.body.active=true
    for i=1,80 do runtime.update(ctx,1/60) end;near(g.fuse,2.35)
    runtime.set_paused(ctx,true);for i=1,120 do runtime.fixed_update(ctx,h) end;near(g.fuse,2.35)
    runtime.set_paused(ctx,false)
    local n=0;events.on(ctx.events,events.EXPLOSION,ctx,function() n=n+1 end)
    for i=1,281 do runtime.fixed_update(ctx,h) end;assert(#ctx.grenades.live==1)
    runtime.fixed_update(ctx,h);assert(#ctx.grenades.live==0 and n==1 and not g.body.active)
    grenades.detonate(ctx,g);assert(n==1)
end)
test("blast applies once per actor including thrower; damage remains combat-owned",function()
    local ctx,e=context();ctx.player.position={x=2,y=0,z=0}
    local g=grenades.launch(ctx,e.id,{x=0,y=.5,z=0},{x=0,y=0,z=0})
    local n=0;events.on(ctx.events,events.DAMAGE_DEALT,ctx,function(_,hit) n=n+1;assert(hit.kind=="explosion" and hit.from.y==.5) end)
    grenades.detonate(ctx,g);grenades.detonate(ctx,g)
    assert(#ctx.combat.pending==2 and ctx.player.actor.health==100 and e.actor.health==100)
    combat.fixed_update(ctx,h);assert(n==2 and ctx.player.actor.health<100 and not e.actor.alive)
end)
test("wall/floor obstruction blocks wounds but keeps player blast suppression",function()
    local ctx,e,q=context();ctx.player.position={x=1,y=0,z=0};q.blocked=true
    local g=grenades.launch(ctx,e.id,{x=0,y=.5,z=0},{x=0,y=0,z=0})
    grenades.detonate(ctx,g);assert(#ctx.combat.pending==0)
    assert(ctx.player.health_state.suppression>0)
    assert(ctx.player.actor.health==100 and e.actor.health==100)
end)
test("range, dead actors and zero damage scale cannot enqueue wounds",function()
    local ctx,e=context();ctx.ai.damage_scale=0
    local g=grenades.launch(ctx,e.id,{x=0,y=.5,z=0},{x=0,y=0,z=0})
    grenades.detonate(ctx,g);assert(#ctx.combat.pending==0)
    ctx.ai.damage_scale=1;e.actor.alive=false
    g=grenades.launch(ctx,e.id,{x=0,y=.5,z=0},{x=0,y=0,z=0});grenades.detonate(ctx,g);assert(#ctx.combat.pending==0)
end)
test("reset removes airborne bodies, pending blast damage and HUD warnings",function()
    local ctx,e=context();ctx.player.position={x=1,y=0,z=0};ctx.presentation.position=ctx.player.position
    local g=grenades.launch(ctx,e.id,{x=0,y=.5,z=0},{x=0,y=0,z=0})
    assert(hud.grenade_warning(ctx)~="");grenades.detonate(ctx,g);assert(#ctx.combat.pending>0)
    grenades.reset(ctx);assert(#ctx.grenades.live==0 and not g.body.active and #ctx.combat.pending==0)
    assert(hud.grenade_warning(ctx)=="")
end)
test("warning reports behind/above threats and bounds multiple grenades to one string",function()
    local ctx,e=context();ctx.presentation.position={x=0,y=0,z=0};ctx.presentation.yaw=0
    grenades.launch(ctx,e.id,{x=0,y=3,z=2},{x=0,y=0,z=0})
    grenades.launch(ctx,e.id,{x=0,y=3,z=4},{x=0,y=0,z=0})
    local text,n=hud.grenade_warning(ctx);assert(n==2 and text:find("BEHIND ABOVE") and text:find("+1",1,true),text)
end)
test("explosion presentation uses bounded pools and expires",function()
    local s=fx.new();for i=1,30 do fx.explosion(s,{position={x=0,y=0,z=0}}) end
    assert(fx.snapshot(s).particles==fx.particle_limit)
    for _=1,360 do fx.update(s,1/60) end;assert(fx.snapshot(s).particles==0 and #s.emitters==0)
end)
test("throw layer fades to the support socket without an end-of-clip hand jump",function()
    for _,variant in ipairs({"vanguard","irregular","breacher"}) do
        local base={variant=variant,throw=1,throw_weight=0}
        local scratch={};rig.pose(base,scratch);local rest=V.copy(scratch.support_target)
        for _,weight in ipairs({.01,.25,.5,.75,1}) do
            base.throw_weight=weight;rig.pose(base,scratch)
            near(scratch.support_target.x,rest.x);near(scratch.support_target.y,rest.y);near(scratch.support_target.z,rest.z)
        end
    end
end)
print(count.." grenade tests passed")
