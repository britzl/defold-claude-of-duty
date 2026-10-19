-- Shared native/WebGL fixture: generated variants, real terrain and hit volumes.
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local animation=require "game.ai.animation"
local rig=require "game.ai.rig"
local variants=require "game.ai.variants"
local soldiers=require "game.ai.defold"
local weapons=require "game.weapons.defold"
local world=require "game.world.defold"
local mesh=require "game.world.mesh"
local combat=require "game.combat"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local M={}
local function report(kind,data)
    local line="SOLDIER "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
local function near(a,b,t) assert(math.abs(a-b)<(t or 1e-5),a.." != "..b) end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    local test={checks=0,shots=0}
    if automation_bridge then
        automation_bridge.command("soldier.capture_ack",function(data)
            assert(data.id==test.waiting_capture,"Unexpected capture acknowledgement")
            test.capture_ack=data.id;return {id=data.id}
        end)
    end
    report("START",sys.get_engine_info());return test
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold then runtime.set_paused(ctx,false);self.focused=true end
    if not test.live then ctx.ai.enabled=false end
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function check(name,detail) test.checks=test.checks+1;report("CHECK",{name=name,detail=detail}) end
        local function capture(name)
            test.hold=true;runtime.set_paused(ctx,true);msg.post("/hud#gui","disable");frames(8)
            test.waiting_capture=name;test.capture_ack=nil
            test.shots=test.shots+1;report("SHOT",{id=name})
            local deadline=ctx.time.frame_elapsed+25
            while test.capture_ack~=name do
                if html5 and html5.run("window.__soldierCaptureAck || ''")==name then test.capture_ack=name end
                assert(ctx.time.frame_elapsed<deadline,"Screenshot acknowledgement timed out: "..name)
                frames(1)
            end
            test.waiting_capture=nil
            test.hold=false;runtime.set_paused(ctx,false)
        end
        restart(self);ctx.ai.enabled=false;frames(8)
        local service=ctx.services.soldiers
        local resources=soldiers.snapshot(service)
        assert(resources.buffers==3 and resources.objects==78 and resources.active_hitboxes==66,json.encode(resources))
        assert(resources.vertices==30096 and resources.mesh_bytes==2166912,json.encode(resources))
        check("three_shared_variant_buffers_and_66_volumes",resources)
        local stage=world.new("#world_mesh","#world_collision")
        local shapes={
            {id="soldier_floor",x=70,y=-.1,z=0,w=12,h=.4,d=12,surface="concrete",material="concrete"},
            {id="soldier_step",x=73,y=.19,z=0,w=1,h=.18,d=2,surface="concrete",material="concrete"},
        }
        for i=1,4 do shapes[#shapes+1]={id="soldier_stair_"..i,x=67,y=.10+i*.09,z=1.3-i*.6,
            w=1.8,h=i*.18,d=.6,surface="concrete",material="concrete"} end
        local batch=mesh.new("soldier_stage","concrete",0,0)
        for _,shape in ipairs(shapes) do world.add_collision(stage,shape);mesh.box(batch,shape,1) end
        world.add_batch(stage,batch);frames(5)
        ctx.world.views.soldier_fixture={position={x=72.7,y=1.7,z=4.0},yaw=.594,pitch=-.16,title="SOLDIER FIXTURE"}
        self.view="soldier_fixture"
        local function place(e,x,z,yaw)
            e.position.x,e.position.y,e.position.z=x,.10,z or 0;e.yaw=yaw or math.pi
            e.previous=V.copy(e.position);e.previous_yaw=e.yaw
            e.motion.position=e.position;animation.init(e)
        end
        local function evaluate(e)
            local state=ai.pose_state(e);e.previous_pose=state
            e.palette,e.joints=rig.pose(state,e.simulation_pose)
            soldiers.sync(service,e);return state
        end
        for i,id in ipairs(ctx.ai.order) do place(ctx.ai.actors[id],i<=3 and 68+(i-1)*1.5 or 85,0,math.pi+.2) end
        frames(3);capture("variants")
        local native=weapons.query({service.by_id},{groups={hash("enemy")}})
        local clips={"idle","run","crouch","reload","vault","hit"}
        for i,name in ipairs(variants.order) do
            local e=ctx.ai.actors[ctx.ai.order[i]];assert(e.variant==name)
            for j,id in ipairs(ctx.ai.order) do if i~=j then place(ctx.ai.actors[id],85+j,0) end end
            place(e,70,0,math.pi+.25);frames(3)
            for _,clip in ipairs(clips) do
                animation.init(e);e.walk=0;e.run=0;e.crouch=0;e.phase=1.4;e.aim=1;e.pitch=.2;e.aim_yaw=.15
                if clip=="run" then e.walk=1;e.run=1 end
                if clip=="crouch" then e.crouch=1 end
                if clip=="reload" then animation.reload(e,2.4);e.animation.reload_time=1.008 end
                if clip=="vault" then animation.vault(e,.85);e.animation.vault_time=.34 end
                if clip=="hit" then
                    combat.request(ctx.combat,{target=e.id,amount=16,source="fixture",region="arm",part="forearm_l"})
                    combat.fixed_update(ctx,1/120);e.animation.hit_time=.08
                end
                local state=evaluate(e)
                local volumes=rig.volumes(e.palette,e.position,e.yaw,e.id,e.variant)
                for _,volume in ipairs(volumes) do
                    local origin=T.point(volume.transform,{x=0,y=0,z=volume.d/2+.02})
                    local direction=T.direction(volume.transform,{x=0,y=0,z=-1})
                    local found=false
                    for _,hit in ipairs(native:segment(origin,direction,.1)) do
                        if hit.id==volume.id then found=true;near(hit.enter,.02) end
                    end
                    assert(found,"Missing native volume "..name.."/"..clip.."/"..volume.part)
                end
                assert(e.simulation_pose.support_error<1e-5,name.."/"..clip.." support error "..e.simulation_pose.support_error)
                frames(4)
                if clip=="idle" or clip=="reload" or i==1 then capture(name.."_"..clip) end
            end
            check(name.."_six_poses_native_volumes_and_hand_ik",{poses=6,volumes=66})
        end
        local e=ctx.ai.actors[ctx.ai.order[1]]
        place(e,72.5,0,0);e.walk=0;e.run=0;e.crouch=0;e.aim=0;e.aim_yaw=0;e.pitch=0
        local query=soldiers.query(service,e)
        for _=1,120 do animation.step(e,1/120,query) end
        evaluate(e)
        near(e.joints[rig.index.FootR][8],.18+.088);near(e.joints[rig.index.FootL][8],.088)
        check("native_step_foot_and_pelvis_ik")
        ctx.world.views.soldier_fixture={position={x=74.6,y=1.45,z=3.4},yaw=.553,pitch=-.12,title="STEP IK"}
        frames(4);capture("step_ik")
        place(e,70,2,0);e.walk=1;e.run=1
        local prior={};local planted=0
        for tick=1,240 do
            e.position.z=e.position.z-2.2/120;e.phase=e.phase+2.2/120*2*math.pi/1.7
            animation.step(e,1/120,query);local s=evaluate(e)
            for _,side in ipairs({"R","L"}) do
                local p=T.point(T.root(e.position,e.yaw),T.origin(e.joints[rig.index["Foot"..side]]))
                if s.feet[side].stance and prior[side] and prior[side].stance then
                    near(p.x,prior[side].p.x);near(p.y,prior[side].p.y);near(p.z,prior[side].p.z);planted=planted+1
                end
                prior[side]={p=p,stance=s.feet[side].stance}
            end
        end
        assert(planted>100);check("native_running_stance_locks",{samples=planted})
        place(e,67,2,0);e.walk=0;e.run=0;e.phase=0;e.think=100;e.memory=0;e.notice=0;e.route={}
        for i=1,4 do e.route[#e.route+1]={x=67,y=.104+i*.18,z=1.3-i*.6} end
        e.state="patrol";test.live=true;ctx.ai.enabled=true
        local deadline=ctx.time.frame_elapsed+12
        while e.position.y<.80 or e.position.z>-.80 do
            assert(ctx.time.frame_elapsed<deadline,"Stair traversal timed out: "..json.encode(e.position));frames(1)
        end
        test.live=false;ctx.ai.enabled=false
        assert(not e.motion.recovery_failed and e.animation.targets.R.weight==1 and e.animation.targets.L.weight==1)
        check("production_capsule_climbs_four_stairs_with_foot_ik",{position=V.copy(e.position)})
        ctx.world.views.soldier_fixture={position={x=69.4,y=2.1,z=2.3},yaw=.615,pitch=-.15,title="STAIRS"}
        frames(4);capture("stairs")
        place(e,70,0,math.pi);e.walk=0;e.run=0;animation.turn(e,1)
        for _=1,25 do e.yaw=e.yaw+.008;animation.step(e,1/120,query) end
        evaluate(e);assert(e.joints[rig.index.FootR][8]>.14);check("native_turning_step")
        ctx.world.views.soldier_fixture={position={x=72.7,y=1.7,z=4.0},yaw=.594,pitch=-.16,title="TURNING"}
        frames(4);capture("turn_step")
        animation.reload(e,2.35);test.live=true;ctx.ai.enabled=true
        frames(5);assert(e.animation.reload_time>0)
        test.hold=true;runtime.set_paused(ctx,true)
        local frozen=json.encode(ai.pose_state(e));frames(15);assert(frozen==json.encode(ai.pose_state(e)))
        test.hold=false;runtime.set_paused(ctx,false);frames(4)
        assert(frozen~=json.encode(ai.pose_state(e)));test.live=false;ctx.ai.enabled=false
        check("production_animation_clocks_pause_and_resume")
        local before=e.animation.hit_time
        combat.request(ctx.combat,{target=e.id,amount=60,source="fixture",region="leg",part="shin_r"});combat.fixed_update(ctx,1/120)
        assert(e.animation.hit_region=="leg" and e.animation.hit_side==1 and e.animation.hit_time==0)
        assert(animation.sample(e).wounded>0);check("production_damage_reaction_and_wounded_layer")
        evaluate(e);frames(4);capture("wounded")
        world.final(stage);self.view=nil;ctx.world.views.soldier_fixture=nil
        for _=1,3 do
            restart(self);ctx.ai.enabled=false;frames(6)
            local r=soldiers.snapshot(ctx.services.soldiers)
            assert(r.buffers==3 and r.objects==78 and r.active_hitboxes==66)
            for _,id in ipairs(ctx.ai.order) do
                local actor=ctx.ai.actors[id];assert(actor.animation.hit_time==1 and actor.animation.reload_time==-1)
            end
        end
        check("three_resets_preserve_bounded_resources_and_clear_animation")
        msg.post("/hud#gui","enable");test.done=true
        report("PASS",{checks=test.checks,shots=test.shots,platform=sys.get_sys_info().system_name})
    end) end
    local ok,err=coroutine.resume(test.job)
    if not ok then test.done=true;error(err) end
end
return M
