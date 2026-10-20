-- Shared native/WebGL fixture: the production AI, Bullet body, fuse and blast paths.
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local player=require "game.systems.player"
local grenades=require "game.systems.grenades"
local throwing=require "game.ai.grenades"
local tactics=require "game.ai.tactics"
local events=require "game.events"
local hud=require "game.ui.hud"
local dynamics=require "game.physics.defold"
local world=require "game.world.defold"
local mesh=require "game.world.mesh"
local V=require "game.weapons.math"
local M={}
local function report(kind,data)
    local line="GRENADES "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    local t={checks=0,shots=0}
    if automation_bridge then automation_bridge.command("grenades.capture_ack",function(data)
        assert(data.id==t.waiting_capture);t.capture_ack=data.id;return {id=data.id}
    end) end
    report("START",sys.get_engine_info());return t
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold then runtime.set_paused(ctx,false);self.focused=true end
    if not test.live then ctx.ai.enabled=false end
    if test.capturing then
        local display=require("game.ui.controller").snapshot(self);display.paused=false
        msg.post("/hud#gui","menu_state",display)
    end
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function seconds(n) local until_time=ctx.time.elapsed+n;repeat frames(1) until ctx.time.elapsed>=until_time end
        local function until_true(fn,timeout,label)
            local deadline=ctx.time.elapsed+timeout
            while not fn() do assert(ctx.time.elapsed<deadline,label.." "..json.encode(grenades.snapshot(ctx)));frames(1) end
        end
        local function check(name,detail) test.checks=test.checks+1;report("CHECK",{name=name,detail=detail}) end
        local function capture(name)
            test.hold=true;test.capturing=true;runtime.set_paused(ctx,true);frames(8)
            test.waiting_capture=name;test.capture_ack=nil;test.shots=test.shots+1;report("SHOT",{id=name})
            local deadline=ctx.time.frame_elapsed+25
            while test.capture_ack~=name do
                if html5 and html5.run("window.__grenadesCaptureAck || ''")==name then test.capture_ack=name end
                assert(ctx.time.frame_elapsed<deadline,"Capture timeout");frames(1)
            end
            test.waiting_capture=nil;test.capturing=false;test.hold=false;runtime.set_paused(ctx,false)
        end
        restart(self);ctx.ai.enabled=false;frames(8)
        local a=ctx.services.dynamics
        local baseline=dynamics.snapshot(a)
        assert(baseline.bodies==0 and baseline.objects==76 and baseline.buffers==2,json.encode(baseline))
        assert(ctx.audio.loaded==77 and ctx.audio.bytes==1698124 and ctx.audio.verified==77)
        check("reserved_pool_and_generated_blast_sample",{physics=baseline,audio_bytes=ctx.audio.bytes})
        local stage=world.new("#world_mesh","#world_collision")
        local shapes={
            {id="grenade_floor",x=70,y=-.1,z=0,w=36,h=.4,d=36,surface="concrete",material="concrete"},
            {id="grenade_slab",x=80,y=2,z=0,w=4,h=.2,d=4,surface="concrete",material="concrete"},
            {id="grenade_wall",x=74.3,y=1.6,z=0,w=.3,h=3,d=12,surface="concrete",material="concrete"},
        }
        local batch=mesh.new("grenade_stage","concrete",0,0)
        for _,s in ipairs(shapes) do world.add_collision(stage,s);mesh.box(batch,s,1) end
        world.add_batch(stage,batch);frames(6)
        local old_graph,old_cover=ctx.world.navigation,ctx.world.cover
        ctx.world.navigation={nodes={},edges={}};ctx.world.cover={}
        ctx.world.views.grenade_fixture={position={x=67,y=3,z=12},yaw=.35,pitch=-.15,title="GRENADE THROW"}
        local e=ai.reset(ctx,{x=64,y=.104,z=8},0)
        player.reset(ctx,{x=64,y=.104,z=-8},math.pi)
        frames(8)
        e.grenade_cooldown=0;e.state="fire";e.think=0;tactics.alert(ctx,e,ctx.player.position)
        ctx.ai.damage_scale=0;test.live=true;ctx.ai.enabled=true;self.view="grenade_fixture"
        until_true(function() return e.animation.throw_time>.18 end,8,"AI never started throw")
        assert(e.has_grenade and #ctx.grenades.live==0)
        capture("windup")
        until_true(function() return e.grenades_thrown==1 end,3,"AI never released")
        local g=assert(ctx.grenades.live[1]);assert(not e.has_grenade)
        test.live=false;ctx.ai.enabled=false
        check("production_ai_animated_release",{actor=e.id,position=g.position,velocity=g.body.pending and g.body.pending.velocity})
        seconds(.25);self.view=nil
        player.reset(ctx,{x=64,y=.104,z=-3},math.pi)
        frames(2);assert(hud.grenade_warning(ctx)~="")
        capture("airborne_warning")
        local before=V.copy(g.body.position);local fuse=g.fuse
        test.hold=true;require("game.ui.controller").focus(self,false)
        local frozen=bullet3d.collision_object.get_position(g.body.object);frames(20)
        assert(ctx.paused and ctx.audio.suspended and g.fuse==fuse)
        assert(vmath.length(bullet3d.collision_object.get_position(g.body.object)-frozen)<1e-7)
        require("game.ui.controller").focus(self,true);assert(ctx.paused)
        test.hold=false;runtime.set_paused(ctx,false);seconds(.1)
        assert(g.fuse<fuse and V.length({x=g.position.x-before.x,y=g.position.y-before.y,z=g.position.z-before.z})>.01)
        check("focus_pause_freezes_body_fuse_and_audio")
        -- Face the landing area for the detonation capture (the airborne shot
        -- looked back toward the thrower).
        player.reset(ctx,{x=64,y=.104,z=-3},0)
        until_true(function() return g.detonated end,3,"Fuse did not expire")
        seconds(.03)
        assert(#ctx.grenades.live==0 and ctx.player.actor.health==100)
        assert(require("game.render.combat_fx_defold").snapshot(self.combat_visuals).particles>0)
        assert(ctx.fx.flashes[1] and ctx.fx.flashes[1].radius==8)
        -- HTML5 audio needs a trusted canvas gesture; routing is also verified
        -- by standalone mixer tests. Native confirms actual voice admission.
        if not html5 then assert((ctx.audio.by_kind.explosion or 0)>0) end
        check("fuse_drives_fx_audio_and_suppression",{suppression=ctx.player.health_state.suppression,audio=ctx.audio.by_kind})
        capture("explosion")
        grenades.reset(ctx);dynamics.reset(a)
        player.reset(ctx,{x=70,y=.104,z=7},0)
        g=assert(grenades.launch(ctx,e.id,{x=72,y=1,z=2},{x=5,y=4,z=-2}))
        local bounced=false;local min_y,max_x=math.huge,-math.huge
        while not g.detonated do
            if g.body.active then
                local p=g.body.position;local velocity=bullet3d.rigid_body.get_linear_velocity(g.body.body)
                min_y=math.min(min_y,p.y);max_x=math.max(max_x,p.x)
                if p.y<.35 and velocity.y>.25 then bounced=true end
            end
            frames(1)
        end
        assert(bounced and min_y>.10 and max_x<74.13,json.encode({bounced=bounced,min_y=min_y,max_x=max_x}))
        check("native_sphere_floor_bounce_and_wall_collision",{min_y=min_y,max_x=max_x})
        local query=ctx.services.soldiers.api.query(ctx.services.soldiers,e)
        local from={x=73,y=1,z=2};local v,time=throwing.solve(from,{x=76,y=.25,z=-4})
        assert(not throwing.clear_arc(query,from,v,time))
        check("throw_clearance_rejects_real_wall")
        e=ai.reset(ctx,{x=80,y=2.104,z=0},0);ctx.ai.enabled=false;ctx.ai.damage_scale=1
        player.reset(ctx,{x=80,y=2.104,z=1},0);frames(8)
        g=grenades.launch(ctx,e.id,{x=80,y=.2,z=0},{x=0,y=0,z=0});g.fuse=.2
        until_true(function() return g.detonated end,2,"Below-floor blast timed out");seconds(.05)
        assert(ctx.player.actor.health==100 and e.actor.health==100)
        check("upper_floor_blocks_blast_damage")
        -- Blast through the wall: close enough for suppression, no wounds.
        e=ai.reset(ctx,{x=73,y=.104,z=0},0);ctx.ai.enabled=false;ctx.ai.damage_scale=1
        player.reset(ctx,{x=73,y=.104,z=1},0);frames(8)
        g=grenades.launch(ctx,e.id,{x=75.4,y=.2,z=0},{x=0,y=0,z=0});g.fuse=.2
        until_true(function() return g.detonated end,2,"Covered blast timed out");seconds(.05)
        assert(ctx.player.actor.health==100 and e.actor.health==100)
        assert(ctx.player.health_state.suppression>0)
        check("wall_blocks_damage_but_preserves_pressure")
        local hits={};events.on(ctx.events,events.DAMAGE_DEALT,test,function(_,hit)
            if hit.kind=="explosion" then hits[hit.target]=(hits[hit.target] or 0)+1 end
        end)
        dynamics.spawn(a,"debris",{x=73.7,y=.5,z=.3},{x=0,y=0,z=0},"concrete");frames(4)
        g=grenades.launch(ctx,e.id,{x=73.35,y=.2,z=0},{x=0,y=0,z=0});g.fuse=.2
        until_true(function() return g.detonated end,2,"Open blast timed out");seconds(.12)
        assert(hits.player==1 and hits[e.id]==1 and ctx.player.actor.health<100 and not e.actor.alive,json.encode(hits))
        assert(e.ragdoll and e.ragdoll.ready and a.impulses>0)
        check("single_damage_per_actor_and_ragdoll_handoff",{hits=hits,health=ctx.player.actor.health,physics=dynamics.snapshot(a)})
        self.view="grenade_fixture";ctx.world.views.grenade_fixture.position={x=71,y=2.5,z=5};ctx.world.views.grenade_fixture.yaw=-.4;ctx.world.views.grenade_fixture.pitch=-.3
        capture("blast_death")
        for round=1,3 do
            for i=1,grenades.limit do assert(grenades.launch(ctx,"enemy_1",{x=70,y=2,z=i},{x=0,y=3,z=0})) end
            assert(not grenades.launch(ctx,"enemy_1",{x=70,y=2,z=0},{x=0,y=0,z=0}))
            if round%2==0 then seconds(.1) end
            restart(self);ctx.ai.enabled=false;frames(8)
            local snap=dynamics.snapshot(a)
            assert(#ctx.grenades.live==0 and snap.bodies==0 and snap.pending==0 and snap.objects==76 and snap.buffers==2,json.encode(snap))
            assert(hud.grenade_warning(ctx)=="")
        end
        check("three_pending_and_airborne_restarts_keep_resources_bounded",dynamics.snapshot(a))
        events.off_owner(ctx.events,test)
        ctx.world.navigation,ctx.world.cover=old_graph,old_cover
        world.final(stage);restart(self);ctx.ai.enabled=false
        test.hold=true;runtime.set_paused(ctx,true)
        check("fixture_cleanup_and_encounter_restore")
        test.done=true;report("PASS",{checks=test.checks,shots=test.shots,grenades=grenades.snapshot(ctx),physics=dynamics.snapshot(a)})
    end) end
    local ok,message=coroutine.resume(test.job)
    if not ok then test.done=true;error(message.."\n"..debug.traceback(test.job)) end
end
return M
