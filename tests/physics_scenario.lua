-- Shared native/release-WebGL tests of real Bullet bodies, not a mock solver.
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local combat=require "game.combat"
local events=require "game.events"
local rig=require "game.ai.rig"
local dynamics=require "game.physics.defold"
local world=require "game.world.defold"
local mesh=require "game.world.mesh"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local M={}
local function report(kind,data)
    local line="PHYSICS "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    local test={checks=0,shots=0}
    if automation_bridge then automation_bridge.command("physics.capture_ack",function(data)
        assert(data.id==test.waiting_capture);test.capture_ack=data.id;return {id=data.id}
    end) end
    report("START",sys.get_engine_info());return test
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold then runtime.set_paused(ctx,false);self.focused=true end
    ctx.ai.enabled=false
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function seconds(n) local until_time=ctx.time.elapsed+n;repeat frames(1) until ctx.time.elapsed>=until_time end
        local function check(name,detail) test.checks=test.checks+1;report("CHECK",{name=name,detail=detail}) end
        local function capture(name)
            test.hold=true;runtime.set_paused(ctx,true);msg.post("/hud#gui","disable");frames(8)
            test.waiting_capture=name;test.capture_ack=nil;test.shots=test.shots+1;report("SHOT",{id=name})
            local deadline=ctx.time.frame_elapsed+25
            while test.capture_ack~=name do
                if html5 and html5.run("window.__physicsCaptureAck || ''")==name then test.capture_ack=name end
                assert(ctx.time.frame_elapsed<deadline,"Capture timeout: "..name);frames(1)
            end
            test.waiting_capture=nil;test.hold=false;runtime.set_paused(ctx,false)
        end
        restart(self);ctx.ai.enabled=false;frames(8)
        local a=ctx.services.dynamics
        local baseline=dynamics.snapshot(a)
        assert(baseline.bodies==0 and baseline.objects==76 and baseline.buffers==2,json.encode(baseline))
        check("bounded_initial_resources",baseline)
        local stage=world.new("#world_mesh","#world_collision")
        local shapes={{id="physics_floor",x=70,y=-.1,z=0,w=15,h=.4,d=12,surface="concrete",material="concrete"},
            {id="physics_wall",x=74.3,y=1.6,z=0,w=.3,h=3,d=5,surface="concrete",material="concrete"}}
        for i=1,4 do shapes[#shapes+1]={id="physics_stair_"..i,x=67,y=.1+i*.11,z=1.2-i*.65,
            w=1.8,h=i*.22,d=.65,surface="concrete",material="concrete"} end
        local batch=mesh.new("physics_stage","concrete",0,0)
        for _,s in ipairs(shapes) do world.add_collision(stage,s);mesh.box(batch,s,1) end
        world.add_batch(stage,batch);frames(6)
        ctx.world.views.physics_fixture={position={x=72,y=3.4,z=6},yaw=.30,pitch=-.34,title="PHYSICS FIXTURE"}
        self.view="physics_fixture"
        local positions={{x=70,y=.1,z=0},{x=67,y=.76,z=-.5},{x=73.7,y=.1,z=0},
            {x=69,y=.1,z=-2.5},{x=71,y=.1,z=-2.5},{x=73,y=.1,z=-2.5}}
        for i,id in ipairs(ctx.ai.order) do
            local e=ctx.ai.actors[id];e.position=V.copy(positions[i]);e.previous=V.copy(e.position)
            e.yaw=math.pi;e.previous_yaw=e.yaw;e.motion.position=e.position
            e.palette,e.joints=rig.pose(ai.pose_state(e))
        end
        frames(5);capture("live_poses")
        for i,id in ipairs(ctx.ai.order) do
            local e=ctx.ai.actors[id]
            local point=T.point(T.root(e.position,e.yaw),T.origin(e.joints[rig.index.Spine2]))
            assert(combat.request(ctx.combat,{target=id,amount=200,source="player",point=point,
                part=i==2 and "leg_l" or "chest",region=i==2 and "leg" or "torso",impulse={x=i==3 and 6 or 1,y=.3,z=-5}}))
        end
        seconds(.15)
        local snap=dynamics.snapshot(a)
        assert(snap.ragdolls==6 and snap.bodies==108 and snap.constraints==102,json.encode(snap))
        for _,id in ipairs(ctx.ai.order) do
            local e=ctx.ai.actors[id];assert(e.ragdoll.ready and not e.actor.alive)
            assert(not combat.request(ctx.combat,{target=id,amount=1}))
        end
        assert(ctx.services.soldiers.api.snapshot(ctx.services.soldiers).active_hitboxes==0)
        check("six_regional_deaths_and_dead_damage_rules",snap)
        capture("falling")
        test.hold=true;runtime.set_paused(ctx,true)
        local item=a.ragdolls[1].bodies[1]
        local frozen=bullet3d.collision_object.get_position(item.object);local age=a.ragdolls[1].age
        frames(25)
        assert(vmath.length(bullet3d.collision_object.get_position(item.object)-frozen)<1e-7)
        assert(a.ragdolls[1].age==age)
        test.hold=false;runtime.set_paused(ctx,false);seconds(.25)
        assert(vmath.length(bullet3d.collision_object.get_position(item.object)-frozen)>.001)
        check("native_pause_and_resume_preserve_motion")
        seconds(8)
        local max_anchor_error,max_height,min_height=0,-math.huge,math.huge
        for _,doll in ipairs(a.ragdolls) do
            for j,b in ipairs(doll.bodies) do
                local p=b.position;assert(p.x==p.x and p.y==p.y and p.z==p.z)
                max_height=math.max(max_height,p.y);min_height=math.min(min_height,p.y)
                assert(p.x<74.2,"Body crossed wall")
                local spec=doll.spec.bodies[j]
                if spec.parent then
                    local left=T.point(doll.bodies[spec.parent].shape.transform,T.origin(spec.frame_a))
                    local right=T.point(b.shape.transform,T.origin(spec.frame_b))
                    max_anchor_error=math.max(max_anchor_error,V.length({x=left.x-right.x,y=left.y-right.y,z=left.z-right.z}))
                end
            end
        end
        assert(min_height>.08 and max_height<1.4 and max_anchor_error<.10,json.encode({min=min_height,max=max_height,error=max_anchor_error}))
        check("floor_stairs_wall_and_joint_settling",{min=min_height,max=max_height,anchor_error=max_anchor_error})
        capture("settled")
        snap=dynamics.snapshot(a);assert(snap.awake==0,json.encode(snap))
        check("native_island_sleep",snap)
        local before=V.copy(item.position)
        events.emit(ctx.events,events.EXPLOSION,{position={x=before.x-.4,y=before.y+.3,z=before.z+.4},radius=2,impulse=4})
        seconds(.3)
        assert(V.length({x=item.position.x-before.x,y=item.position.y-before.y,z=item.position.z-before.z})>.03)
        local doll=a.ragdolls[1]
        local pose,position=dynamics.palette(doll,.5)
        local body=doll.bodies[1]
        local anchor=vmath.lerp(.5,body.previous,body.position)
        local initial=doll.spec.bodies[1].world
        assert(math.abs(position.x-(doll.spec.root[4]+anchor.x-initial[4]))<1e-5)
        local raw=require("game.physics.rig").palette(doll.spec,doll.transforms)
        local rendered,root_position=dynamics.palette(doll,1)
        local root=T.root(root_position,doll.actor.yaw)
        for i=1,25 do
            local actual=T.mul(root,rendered[i]);local expected=T.mul(doll.spec.root,raw[i])
            for j=1,12 do assert(math.abs(actual[j]-expected[j])<1e-5) end
        end
        check("blast_wakes_sleeping_corpses_and_rebases_render_bounds",dynamics.snapshot(a))
        -- Actual native ray through a dead body produces a physics-only impact.
        local target=a.ragdolls[6].bodies[6];local p=target.position
        local query=require("game.weapons.defold").query({a.by_id},{groups={hash("debris")}})
        local hits=query:segment({x=p.x,y=p.y,z=p.z+1},{x=0,y=0,z=-1},2)
        assert(#hits>0 and not hits[1].actor)
        local count=a.impulses
        local sim=require("game.weapons.ballistics").new(1337,"corpse")
        require("game.weapons.ballistics").spawn(sim,{id="fixture",muzzleVelocity=400,damage=25,penetration=.45,dropoff=1,maxRange=5,dragK=0},
            {x=p.x,y=p.y,z=p.z+1},{x=0,y=0,z=-1},"player",false)
        require("game.weapons.ballistics").update(ctx,sim,1/120,query)
        assert(a.impulses>count)
        check("corpse_round_impulse_without_damage",{impulses=a.impulses})
        -- Production shell/reload notifications own the spawn timing.
        local spawned=a.spawned
        events.emit(ctx.events,events.WEAPON_SHELL,{weapon="rifle",velocity={x=1,y=1,z=0}})
        events.emit(ctx.events,events.WEAPON_RELOAD,{weapon="rifle",phase="magdrop"})
        frames(3);assert(a.spawned==spawned+2)
        check("shell_and_reload_event_wiring")
        for i=1,80 do dynamics.spawn(a,i%3==0 and "magazine" or (i%3==1 and "casing" or "debris"),
            {x=69+(i%6)*.3,y=1.5,z=2+(i%4)*.2},{x=.4,y=.2,z=.3},"wood") end
        frames(8);snap=dynamics.snapshot(a)
        assert(snap.debris==32 and snap.bodies==140 and snap.recycled>=48 and snap.objects==184,json.encode(snap))
        check("bounded_pool_recycling",snap)
        seconds(5)
        for _,b in ipairs(a.debris) do
            assert(b.active and b.position.y>.10 and b.position.y<.4,"Debris failed floor collision")
        end
        for _,b in ipairs(a.debris) do assert(b.sleeping,"Debris failed to sleep") end
        check("debris_collision_and_sleep",dynamics.snapshot(a))
        capture("debris")
        -- Blocked radial impulses do not wake bodies behind the fixture wall.
        local blocked=dynamics.spawn(a,"magazine",{x=75,y=.3,z=0},{x=0,y=0,z=0},"rifle")
        frames(5);local velocity=bullet3d.rigid_body.get_linear_velocity(blocked.body)
        events.emit(ctx.events,events.EXPLOSION,{position={x=73.6,y=.3,z=0},radius=2,impulse=10})
        assert(vmath.length(bullet3d.rigid_body.get_linear_velocity(blocked.body)-velocity)<1e-7)
        check("world_occludes_blast_impulses")
        seconds(31)
        snap=dynamics.snapshot(a);assert(snap.bodies==0 and snap.constraints==0 and snap.ragdolls==0 and snap.objects==76,json.encode(snap))
        capture("cleanup");check("simulation_lifetime_cleanup",snap)
        for cycle=1,10 do
            restart(self);ctx.ai.enabled=false;frames(5)
            for _,id in ipairs(ctx.ai.order) do assert(combat.request(ctx.combat,{target=id,amount=200})) end
            seconds(.15);assert(dynamics.snapshot(a).constraints==102)
            restart(self);ctx.ai.enabled=false;frames(6)
            snap=dynamics.snapshot(a);assert(snap.bodies==0 and snap.constraints==0 and snap.objects==76 and snap.registry_entries<=32 and snap.retired==0)
            assert(ctx.services.soldiers.api.snapshot(ctx.services.soldiers).objects==78)
        end
        check("repeated_death_restart_resource_bounds",snap)
        world.final(stage);self.view=nil;test.done=true
        msg.post("/hud#gui","enable");report("PASS",{checks=test.checks,shots=test.shots,physics=dynamics.snapshot(a)})
    end) end
    local ok,err=coroutine.resume(test.job)
    if not ok then test.done=true;report("FAIL",{error=tostring(err)});error(err) end
end
return M
