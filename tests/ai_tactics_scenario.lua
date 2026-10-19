-- Shared Mac/release-WebGL behavior checks using the actual capsule and hit queries.
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local player=require "game.systems.player"
local tactics=require "game.ai.tactics"
local guns=require "game.ai.weapons"
local combat=require "game.combat"
local events=require "game.events"
local world=require "game.world.defold"
local mesh=require "game.world.mesh"
local V=require "game.weapons.math"
local M={}
local function report(kind,data)
    local line="AI_TACTICS "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    local t={checks=0,shots=0}
    if automation_bridge then automation_bridge.command("ai_tactics.capture_ack",function(data)
        assert(data.id==t.waiting_capture);t.capture_ack=data.id;return {id=data.id}
    end) end
    report("START",sys.get_engine_info());return t
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold then runtime.set_paused(ctx,false);self.focused=true end
    if not test.live then ctx.ai.enabled=false end
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function seconds(n) local until_time=ctx.time.elapsed+n;repeat frames(1) until ctx.time.elapsed>=until_time end
        local function until_true(fn,timeout,label)
            local deadline=ctx.time.elapsed+timeout
            while not fn() do assert(ctx.time.elapsed<deadline,label.." "..json.encode(ai.snapshot(ctx)));frames(1) end
        end
        local function check(name,detail) test.checks=test.checks+1;report("CHECK",{name=name,detail=detail}) end
        local function capture(name,actor)
            if actor then
                local p=actor.position
                ctx.world.views.ai_tactics_fixture.position={x=p.x+3,y=p.y+2.4,z=p.z+5}
                ctx.world.views.ai_tactics_fixture.yaw=.54;ctx.world.views.ai_tactics_fixture.pitch=-.25
            end
            test.hold=true;runtime.set_paused(ctx,true);msg.post("/hud#gui","disable");frames(8)
            test.waiting_capture=name;test.capture_ack=nil;test.shots=test.shots+1;report("SHOT",{id=name})
            local deadline=ctx.time.frame_elapsed+25
            while test.capture_ack~=name do
                if html5 and html5.run("window.__ai_tacticsCaptureAck || ''")==name then test.capture_ack=name end
                assert(ctx.time.frame_elapsed<deadline,"Capture timeout");frames(1)
            end
            test.waiting_capture=nil;test.hold=false;runtime.set_paused(ctx,false)
        end
        restart(self);ctx.ai.enabled=false;frames(8)
        local graph,covers=ctx.world.navigation,ctx.world.cover
        local tall=0
        for _,c in ipairs(covers) do if c.height>=1.8 and c.half_width then tall=tall+1 end end
        assert(tall>0 and tall<=32);check("full_market_tall_cover_metadata",{total=#covers,tall=tall})
        local stage=world.new("#world_mesh","#world_collision")
        local shapes={
            {id="tactics_floor",x=70,y=-.1,z=0,w=24,h=.4,d=32,surface="concrete",material="concrete"},
            {id="tactics_hidden_floor",x=200,y=-.1,z=20,w=8,h=.4,d=8,surface="concrete",material="concrete"},
            {id="tactics_wall",x=70,y=1.3,z=-3,w=2,h=2.4,d=.3,surface="concrete",material="concrete"},
            {id="tactics_vault",x=76,y=.425,z=0,w=3,h=.65,d=.2,surface="wood",material="wood"},
        }
        local batch=mesh.new("tactics_stage","concrete",0,0)
        for _,s in ipairs(shapes) do world.add_collision(stage,s);mesh.box(batch,s,1) end
        world.add_batch(stage,batch);frames(6)
        ctx.world.views.ai_tactics_fixture={position={x=73.5,y=3,z=5},yaw=.42,pitch=-.30,title="AI TACTICS"}
        self.view="ai_tactics_fixture"
        ctx.world.navigation={nodes={},edges={}};ctx.world.cover={}
        local function single(x,z,yaw)
            ctx.ai.enabled=false;test.live=false
            local e=ai.reset(ctx,{x=x,y=.104,z=z},yaw or 0)
            e.patrol_points={V.copy(e.position),V.copy(e.position)}
            player.reset(ctx,{x=200,y=.104,z=20},0)
            ctx.ai.damage_scale=0;frames(5)
            ctx.ai.enabled=true;test.live=true
            return e
        end
        local e=single(64,0)
        events.emit(ctx.events,events.WEAPON_FIRE,{origin={x=64,y=1.4,z=-3},weapon="rifle"})
        assert(e.heard and e.memory==0 and not e.target_point)
        until_true(function() return e.state=="search" end,8,"No investigation/search")
        assert(e.shots==0 and math.abs(e.position.z+3)<.7)
        capture("investigation",e)
        until_true(function() return not e.heard and e.state=="patrol" end,5,"Search did not expire")
        check("hearing_investigation_search_without_omniscience",{investigations=e.investigations,searches=e.searches,shots=e.shots})
        e=single(70,-2.4)
        events.emit(ctx.events,events.PLAYER_FOOTSTEP,{position={x=70,y=.104,z=-9},running=false})
        assert(not e.heard,"Blocked quiet footsteps exceeded attenuated range")
        events.emit(ctx.events,events.EXPLOSION,{position={x=70,y=.104,z=-9},radius=2})
        assert(e.heard and e.heard.kind=="explosion" and e.actor.health==100 and not e.target_point)
        check("real_wall_attenuates_steps_but_explosion_is_heard")
        local profiles={}
        for _,variant in ipairs({"vanguard","irregular","breacher"}) do
            e=single(64,0);e.variant=variant;guns.init(e)
            -- Start with three remaining rounds; reload must still use the complete clip.
            e.ammo=3
            player.reset(ctx,{x=64,y=.104,z=-9},math.pi)
            until_true(function() return e.reload_left>0 end,10,"No magazine depletion")
            assert(e.shots==3 and e.ammo==0)
            if variant=="vanguard" then
                local before=e.reload_left
                test.hold=true;runtime.set_paused(ctx,true);frames(20)
                assert(e.reload_left==before and e.ammo==0)
                test.hold=false;runtime.set_paused(ctx,false);capture("reload",e)
            end
            until_true(function() return e.reloads==1 end,5,"Reload did not complete")
            assert(e.reload_beats==3 and e.ammo>0)
            profiles[#profiles+1]={variant=variant,shots=e.shots,ammo=e.ammo,reload=guns.profile(e).reload,rate=guns.profile(e).rate}
        end
        check("three_variant_magazines_reload_clips_beats_and_pause",profiles)
        e=single(64,0);player.reset(ctx,{x=64,y=.104,z=-9},math.pi)
        until_true(function() return e.shots>=2 end,8,"No visual acquisition")
        local seen=V.copy(e.target_point)
        player.reset(ctx,{x=200,y=.104,z=20},math.pi)
        until_true(function() return e.suppressive_shots>0 end,2,"No recent-position suppression")
        assert(e.target_point.x==seen.x and e.target_point.z==seen.z)
        seconds(2.4);local shots=e.shots;seconds(.6);assert(e.shots==shots)
        check("recent_visual_suppressive_fire_expires_at_observed_position",{suppressive=e.suppressive_shots,shots=e.shots})
        e=single(70,-2.4)
        e.squad="alpha";ctx.ai.squads.alpha={members={e.id}}
        ctx.world.cover={{id="wall",x=70,y=.104,z=-2.4,height=2.4,normal_x=0,normal_z=1,half_width=1}}
        player.reset(ctx,{x=70,y=.104,z=-9},math.pi)
        tactics.alert(ctx,e,ctx.player.position)
        until_true(function() return e.shots>0 end,12,"Tall side peek never fired")
        assert(e.cover and e.cover_phase=="peek" and math.abs(e.position.x-70)>1.2)
        assert(ctx.ai.squads.alpha.peek_owner==e.id)
        capture("tall_cover_peek",e)
        e.suppression=1.6;e.suppressed=true;shots=e.shots
        until_true(function() return e.cover_phase=="hide" and math.abs(e.position.x-70)<.25 end,3,"No side-peek withdrawal")
        assert(e.shots==shots and not ctx.ai.squads.alpha.peek_owner)
        check("native_tall_cover_peek_and_suppressed_withdrawal",{peeks=e.peeks,x=e.position.x})
        ctx.world.cover={}
        e=single(64,0);ctx.world.navigation={nodes={{id="rear",x=64,y=.104,z=5}},edges={}}
        player.reset(ctx,{x=64,y=.104,z=-8},math.pi)
        combat.request(ctx.combat,{target=e.id,amount=75,source="player",from={x=64,y=1.5,z=-8}})
        until_true(function() return e.retreats>0 and e.position.z>2 end,10,"No wounded retreat")
        assert(e.actor.health==25 and e.state=="retreat");capture("wounded_retreat",e)
        check("native_wounded_retreat_to_reachable_rear_position",{retreats=e.retreats,z=e.position.z})
        ctx.world.navigation={nodes={},edges={}}
        e=single(76,2);e.patrol_points={{x=76,y=.104,z=-2},{x=76,y=.104,z=2}};e.patrol=1;e.think=0
        until_true(function() return e.vaults>0 end,10,"No low-obstacle vault")
        seconds(.1);capture("vault",e)
        until_true(function() return e.position.z<-.8 and not e.motion.mantle end,4,"Vault did not land")
        assert(e.position.y>.09 and e.position.y<.12 and not e.motion.recovery_failed)
        check("native_capsule_vault_lands_beyond_low_obstacle",{vaults=e.vaults,z=e.position.z,y=e.position.y})
        local obstruction=world.new("#world_mesh","#world_collision")
        world.add_collision(obstruction,{id="tactics_roof",x=76,y=1.85,z=0,w=3,h=.2,d=2,surface="concrete"})
        e=single(76,1.2);e.patrol_points={{x=76,y=.104,z=-2},{x=76,y=.104,z=1.2}};e.patrol=1;e.think=0
        seconds(3)
        assert(e.vaults==0 and e.position.z>0,"Vault accepted blocked overhead clearance")
        check("low_obstacle_rejected_under_blocked_clearance",{vaults=e.vaults,z=e.position.z})
        world.final(obstruction)
        ctx.ai.enabled=false;test.live=false
        ctx.world.navigation=graph;ctx.world.cover=covers
        restart(self);ctx.ai.enabled=false;frames(6)
        ctx.ai.damage_scale=0;ctx.ai.enabled=true;test.live=true
        local total=0;local roles={}
        for _,p in ipairs({{x=0,y=.01,z=8},{x=4,y=.01,z=-14},{x=23,y=.01,z=-21},{x=-26,y=.01,z=0}}) do
            player.reset(ctx,p,0);seconds(6)
            for _,id in ipairs(ctx.ai.order) do
                local actor=ctx.ai.actors[id];total=total+actor.shots;roles[actor.state]=true
                assert(not actor.motion.recovery_failed,"Full-map capsule recovery failed: "..id)
            end
            for _,squad in pairs(ctx.ai.squads) do
                local peeks=0
                for _,id in ipairs(squad.members) do if ctx.ai.actors[id].cover_phase=="peek" then peeks=peeks+1 end end
                assert(peeks<=1,"Squad overcommitted peeks")
            end
        end
        local movements={}
        for _,id in ipairs(ctx.ai.order) do
            local actor=ctx.ai.actors[id]
            assert(actor.travel>.5,"Actor never moved: "..id)
            movements[#movements+1]={id=id,travel=actor.travel,stuck=actor.stuck,replans=actor.replans}
        end
        assert(total>0);check("six_actor_full_map_engagement_and_peek_permissions",{shots=total,states=roles,movements=movements})
        player.reset(ctx,{x=200,y=.104,z=20},0);seconds(11)
        assert(ctx.player.position.x>190 and ctx.player.position.y>.09,"Hidden player left the supported fixture")
        assert(not next(ctx.ai.cover_claims) and not next(ctx.ai.flank_claims) and not next(ctx.ai.position_claims),
            json.encode({cover=ctx.ai.cover_claims,flank=ctx.ai.flank_claims,positions=ctx.ai.position_claims,planning=#ctx.ai.planner.jobs}))
        for _,id in ipairs(ctx.ai.order) do assert(ctx.ai.actors[id].memory==0) end
        check("six_actor_loss_of_contact_releases_all_claims")
        for _=1,5 do
            for _,id in ipairs(ctx.ai.order) do combat.request(ctx.combat,{target=id,amount=999,source="player"}) end
            seconds(.1)
            assert(not next(ctx.ai.cover_claims) and not next(ctx.ai.flank_claims) and not next(ctx.ai.position_claims))
            restart(self);ctx.ai.damage_scale=0;frames(5)
            for _,id in ipairs(ctx.ai.order) do
                local actor=ctx.ai.actors[id]
                assert(actor.actor.health==100 and actor.ammo==30 and not actor.heard and actor.reload_left==0)
            end
        end
        check("five_death_restart_cycles_clear_contacts_ammo_and_claims")
        local snap=ai.snapshot(ctx);assert(snap.render.buffers==3 and snap.render.objects==78 and snap.render.active_hitboxes==66)
        check("bounded_actor_resources",snap.render)
        test.live=false;ctx.ai.enabled=false;world.final(stage);test.done=true
        report("PASS",{checks=test.checks,shots=test.shots})
    end) end
    local ok,err=coroutine.resume(test.job)
    if not ok then test.done=true;error(err) end
end
return M
