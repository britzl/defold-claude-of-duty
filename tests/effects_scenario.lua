-- Shared native/WebGL acceptance fixture. Production events, rays and shaders.
local runtime=require "game.runtime"
local events=require "game.events"
local fx=require "game.render.combat_fx"
local visual=require "game.render.combat_fx_defold"
local world=require "game.world.defold"
local mesh=require "game.world.mesh"
local player=require "game.systems.player"
local ai=require "game.systems.ai"
local combat=require "game.combat"
local ballistics=require "game.weapons.ballistics"
local weapon_adapter=require "game.weapons.defold"
local grenades=require "game.systems.grenades"
local settings=require "game.render.settings"
local M={}
local function report(kind,data)
    local line="EFFECTS "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    local t={checks=0,shots=0}
    if automation_bridge then automation_bridge.command("effects.capture_ack",function(data)
        assert(data.id==t.waiting_capture);t.capture_ack=data.id;return {id=data.id}
    end) end
    report("START",sys.get_engine_info());return t
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold then runtime.set_paused(ctx,false);self.focused=true end
    ctx.ai.enabled=false
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function seconds(n) local deadline=ctx.time.elapsed+n;repeat frames(1) until ctx.time.elapsed>=deadline end
        local function check(name,detail) test.checks=test.checks+1;report("CHECK",{name=name,detail=detail}) end
        local function configure(values)
            self.renderer_settings=settings.configure(self.renderer_settings,values)
            msg.post("@render:","renderer_configure",self.renderer_settings)
        end
        local function capture(name)
            test.hold=true;runtime.set_paused(ctx,true);msg.post("/hud#gui","disable");frames(8)
            test.waiting_capture=name;test.capture_ack=nil;test.shots=test.shots+1;report("SHOT",{id=name})
            local deadline=ctx.time.frame_elapsed+30
            while test.capture_ack~=name do
                if html5 and html5.run("window.__effectsCaptureAck || ''")==name then test.capture_ack=name end
                assert(ctx.time.frame_elapsed<deadline,"Capture timeout: "..name);frames(1)
            end
            test.waiting_capture=nil
        end
        local function resume() test.hold=false;runtime.set_paused(ctx,false) end
        local function clean() visual.reset(self.combat_visuals);self.combat_visuals.state.emitters={} end
        restart(self);ctx.ai.enabled=false;frames(8)
        configure({auto_exposure=false,motion_blur=0,grain=0,ads_dof=0,temporal_aa=false})
        local a=self.combat_visuals
        local initial=visual.snapshot(a)
        assert(initial.meshes==220 and initial.buffers==1 and initial.emitters==3,json.encode(initial))
        check("reserved_effects_and_wreck_emitters",initial)
        local stage=world.new("#world_mesh","#world_collision")
        local shapes={{id="effects_floor",x=70,y=-.1,z=0,w=16,h=.4,d=16,surface="concrete",material="concrete"}}
        local surfaces={"concrete","metal","wood","glass","flesh","sand"}
        local materials={"concrete","metal","wood","concrete","concrete","sand"}
        for i,surface in ipairs(surfaces) do shapes[#shapes+1]={id="effects_"..surface,x=65.5+i*1.3,y=1.3,z=-1,w=1.1,h=2.6,d=.35,surface=surface,material=materials[i]} end
        for _,s in ipairs(shapes) do
            world.add_collision(stage,s)
            local batch=mesh.new(s.id,s.material,0,0);mesh.box(batch,s,1);world.add_batch(stage,batch)
        end
        local glass=require("game.render.glass").pane("effects_pane",70,1.3,1,2.5,2.6,"z");world.add_batch(stage,glass)
        ctx.world.views.effects_fixture={position={x=70,y=2.5,z=7},yaw=0,pitch=-.13,title="EFFECTS"}
        self.view="effects_fixture";player.reset(ctx,{x=70,y=.01,z=6},0);frames(6)
        msg.post("@render:","renderer_reset_history",{reason="effects_stage"});frames(2)
        clean()
        local sim=ballistics.new(1337,"effects/acceptance")
        local def={id="rifle",muzzleVelocity=900,damage=30,penetration=1,maxRange=100,dropoff=.5,dragK=.0001}
        local query=weapon_adapter.query({stage.by_id,ctx.services.world.by_id})
        for i,surface in ipairs(surfaces) do
            ballistics.spawn(sim,def,{x=65.5+i*1.3,y=1.3,z=.4},{x=0,y=0,z=-1},"player",false)
        end
        ballistics.update(ctx,sim,1/120,query)
        assert(a.state.impacts>=6 and a.state.by_kind[fx.kind.spark] and a.state.by_kind[fx.kind.splinter] and a.state.by_kind[fx.kind.glass] and a.state.by_kind[fx.kind.blood])
        fx.update(a.state,1/60,a.query)
        check("real_ballistics_drive_surface_recipes",{impacts=a.state.impacts,by_kind=a.state.by_kind})
        capture("surface_impacts")
        configure({combat_effects=false});capture("surface_impacts_off")
        configure({combat_effects=true});capture("surface_impacts_return")
        configure({soft_particles=false});capture("surface_no_soft");configure({soft_particles=true})
        clean()
        -- Completely occluded sprites must not change the image.
        fx.fire(a.state,{x=66.8,y=1.3,z=-1.4},{x=0,y=0,z=1},false)
        a.state.particles[1].size=.4;a.state.particles[1].life=.3
        fx.haze(a.state,{x=66.8,y=1.3,z=-1.4},.5,1,1)
        capture("occluded_effects")
        configure({combat_effects=false});capture("occluded_effects_off");configure({combat_effects=true})
        check("opaque_depth_clips_smoke_and_distortion")
        clean()
        -- A flesh hit in front of concrete projects blood onto the wall behind.
        events.emit(ctx.events,events.BULLET_IMPACT,{surface="flesh",point={x=66.8,y=1.3,z=-.5},normal={x=0,y=0,z=1},incident={x=0,y=0,z=-1},damage=30})
        assert(a.state.by_kind[fx.kind.stain])
        for _,e in ipairs(a.state.decals) do if e.life>0 then assert(e.position.z>-.83 and e.position.z<-.81) end end
        check("blood_projects_only_on_world_receivers")
        clean()
        grenades.detonate(ctx,{id=900,source="enemy_1",position={x=70,y=.15,z=2},damage_scale=0})
        fx.update(a.state,.1,a.query)
        assert(a.state.explosions==1 and a.state.by_kind[fx.kind.scorch] and #ctx.fx.flashes>0)
        check("detonation_drives_full_explosion_and_light",visual.snapshot(a))
        capture("explosion")
        configure({heat_distortion=false});capture("explosion_no_heat")
        configure({heat_distortion=true});capture("explosion_heat_return")
        local frozen=json.encode(visual.snapshot(a));frames(25);assert(json.encode(visual.snapshot(a))==frozen)
        require("game.ui.controller").focus(self,false);frames(20)
        assert(ctx.paused and json.encode(visual.snapshot(a))==frozen)
        require("game.ui.controller").focus(self,true)
        check("pause_and_focus_freeze_particles_columns_and_heat")
        resume();seconds(.8);capture("smoke_column")
        assert(a.state.collisions>0 and a.state.rays>0)
        check("native_fragment_sweeps_and_bounces",{collisions=a.state.collisions,rays=a.state.rays})
        resume();seconds(5);capture("scorch")
        assert(#a.state.emitters==0 and fx.snapshot(a.state).particles==0)
        check("finite_explosion_column_expires")
        configure({impact_decals=false});capture("scorch_off");configure({impact_decals=true})
        clean()
        fx.fire(a.state,{x=69.6,y=1.4,z=.6},{x=0,y=0,z=1},false)
        fx.fire(a.state,{x=70.4,y=1.2,z=1.4},{x=0,y=0,z=1},false)
        for _,e in ipairs(a.state.particles) do if e.life>0 then e.size=1.2;e.life=e.duration*.7 end end
        capture("glass_smoke")
        configure({glass=false});capture("glass_smoke_no_glass");configure({glass=true})
        check("sorted_transparent_pass",{mode=self.renderer_stats.combat_transparency})
        clean();resume()
        -- Real movement emits footsteps and a real fall emits landing dust.
        self.view=nil;player.reset(ctx,{x=70,y=2.8,z=4},0)
        seconds(1.3);assert(a.state.steps>0)
        local steps=a.state.steps
        ctx.player.drive=require("game.player.driver").new({{ticks=150,move_z=1}})
        seconds(1.5);assert(a.state.steps>steps)
        check("landing_event_has_position_and_drives_dust",{landings=steps,steps=a.state.steps})
        local e=ai.reset(ctx,{x=70,y=.01,z=1},0);ctx.ai.enabled=false;frames(4)
        assert(combat.request(ctx.combat,{target=e.id,amount=200,source="player",point={x=70,y=1,z=1}}))
        seconds(.1);assert(a.state.deaths==1)
        check("actor_death_drives_dust_and_existing_ragdoll")
        visual.reset(a);self.view="effects_fixture"
        ctx.world.views.effects_fixture.position={x=0,y=3.8,z=5.5};ctx.world.views.effects_fixture.yaw=-.55;ctx.world.views.effects_fixture.pitch=-.4
        seconds(3);assert(fx.snapshot(a.state).ambient>0)
        capture("ambient_wreck")
        check("persistent_world_smoke_motes_and_heat",visual.snapshot(a))
        resume()
        -- More than a minute of simulated combat presentation at fixed steps.
        clean()
        local p={x=70,y=.15,z=2}
        for frame=1,3600 do
            if frame%6==0 then events.emit(ctx.events,events.BULLET_IMPACT,{point=p,normal={x=0,y=1,z=0},surface=surfaces[frame/6%6+1],damage=30,incident={x=0,y=-1,z=0}}) end
            if frame%120==0 then events.emit(ctx.events,events.EXPLOSION,{position=p,id=frame}) end
            fx.update(a.state,1/60,a.query)
            if frame%120==0 then frames(1) end
        end
        local stressed=visual.snapshot(a)
        assert(stressed.particles<=128 and stressed.ambient<=32 and stressed.decals<=48 and stressed.haze<=12 and stressed.emitters<=8 and stressed.meshes==220)
        for _=1,3 do
            restart(self);ctx.ai.enabled=false;test.hold=true;runtime.set_paused(ctx,true);frames(3)
            local snap=visual.snapshot(a)
            assert(snap.particles==0 and snap.decals==0 and snap.haze==0 and snap.ambient==0 and snap.emitters==3 and snap.meshes==220)
        end
        check("sixty_seconds_pool_pressure_and_three_restarts",stressed)
        world.final(stage);ctx.world.views.effects_fixture=nil;self.view=nil
        -- The complete renderer snapshot exceeds the native logger's line
        -- limit. Keep the acceptance receipt small enough to parse intact.
        test.done=true;report("PASS",{checks=test.checks,shots=test.shots,
            renderer={combat_transparency=self.renderer_stats.combat_transparency,pipeline=self.renderer_stats.pipeline,
                output_width=self.renderer_stats.output_width,output_height=self.renderer_stats.output_height},
            effects=visual.snapshot(a)})
    end) end
    local ok,message=coroutine.resume(test.job);assert(ok,message)
end
return M
