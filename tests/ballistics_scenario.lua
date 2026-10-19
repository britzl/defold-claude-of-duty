-- Shared native/release-WebGL fixture: actual Bullet colliders and production
-- projectile, damage, firing, pause and reset paths.
local runtime=require "game.runtime"
local ballistics=require "game.weapons.ballistics"
local trace=require "game.weapons.trace"
local combat=require "game.combat"
local events=require "game.events"
local V=require "game.weapons.math"
local T=require "game.ai.transform"
local rig=require "game.ai.rig"
local soldiers=require "game.ai.defold"
local ai=require "game.systems.ai"
local world=require "game.world.defold"
local weapons=require "game.weapons.defold"
local player=require "game.systems.player"
local driver=require "game.weapons.driver"
local M={}
local function report(kind,data)
    local line="BALLISTICS "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
local function near(a,b,t) assert(math.abs(a-b)<(t or 1e-6),a.." != "..b) end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    report("START",sys.get_engine_info())
    return {checks=0}
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold_pause then runtime.set_paused(ctx,false);self.focused=true end
    ctx.ai.enabled=false
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function wait(fn)
            local deadline=ctx.time.frame_elapsed+20
            while not fn() do assert(ctx.time.frame_elapsed<deadline,"Ballistics fixture timed out");coroutine.yield() end
        end
        local function check(name,data)
            test.checks=test.checks+1;report("CHECK",{name=name,detail=data})
        end
        local fixtures=world.new("#world_mesh","#world_collision")
        local shapes={}
        local function box(id,x,z,d,surface,y,h,actor)
            local s={id=id,x=x,y=y or 10,z=z,w=2,h=h or 2,d=d,surface=surface,actor=actor}
            shapes[#shapes+1]=s;world.add_collision(fixtures,s);return s
        end
        box("thin_wood",70,-1,.1,"wood")
        box("thick_concrete",74,-1,.3,"concrete")
        box("thin_metal",78,-1,.005,"metal")
        box("layer_wood",82,-1,.12,"wood")
        box("layer_glass",82,-2,.08,"glass")
        box("overlap_a",86,-1,.08,"wood")
        box("overlap_b",86,-1,.08,"glass")
        box("inside",90,0,1,"concrete")
        box("vertical",94,-1,.04,"glass")
        local floor={id="fire_floor",x=102,y=-.2,z=-2,w=16,h=.4,d=10,surface="concrete"}
        shapes[#shapes+1]=floor;world.add_collision(fixtures,floor)
        box("eye_cover",100,-.4,.15,"concrete",1,2)
        box("muzzle_only_cover",104,-.4,.15,"concrete",.7,1.4)
        box("blocked_target",100,-3,.15,"flesh",1.7,1,"blocked_target")
        box("clear_target",104,-3,.15,"flesh",1.7,1,"clear_target")
        combat.register(ctx.combat,"blocked_target",1000);combat.register(ctx.combat,"clear_target",1000)
        local query=weapons.query({fixtures.by_id},{groups={hash("world")}})
        self.bullet_registries[#self.bullet_registries+1]=fixtures.by_id
        frames(4)
        local definition={id="fixture",damage=20,muzzleVelocity=1000,penetration=1,dropoff=.6,maxRange=100,dragK=0}
        local function fire(q,x,origin,direction,def)
            local sim=ballistics.new(1337)
            local p=ballistics.spawn(sim,def or definition,origin or {x=x,y=10,z=0},direction or {x=0,y=0,z=-1},"player",false)
            ballistics.update(ctx,sim,.01,q)
            return p,sim
        end
        for _,case in ipairs({{70,1,true},{74,0,false},{78,1,true},{82,2,true},{86,2,true},{90,0,false}}) do
            local p,s=fire(query,case[1]);local expected,reference=fire(trace.boxes(shapes),case[1])
            for _,axis in ipairs({"x","y","z"}) do near(p.position[axis],expected.position[axis]) end
            near(p.damage,expected.damage);near(p.power,expected.power)
            assert(s.exits==case[2] and p.alive==case[3] and s.impacts==reference.impacts)
        end
        check("native_thickness_layering_deflection_and_starting_inside",{lanes=6})
        local p,s=fire(query,70);local again,repeated=fire(query,70)
        near(p.position.x,again.position.x,1e-12);assert(s.deflections==1 and repeated.deflections==1)
        check("repeatable_round_local_scatter")
        local d={};for k,v in pairs(definition) do d[k]=v end;d.muzzleVelocity=12
        local slow=ballistics.new();local round=ballistics.spawn(slow,d,{x=70,y=10,z=-.93},{x=0,y=0,z=-1})
        ballistics.update(ctx,slow,1/120,query);assert(slow.exits==0 and round.alive)
        for _=1,3 do ballistics.update(ctx,slow,1/120,query) end
        assert(slow.exits==1 and slow.deflections==1);check("flight_spanning_fixed_ticks")

        -- Move one production soldier away from the map, then synchronize its
        -- actual Bullet volumes to three distinct authoritative animated poses.
        ai.reset(ctx,{x=70,y=12,z=-10},.7);frames(5)
        local e=ctx.ai.actors.enemy_1
        local damage={};events.on(ctx.events,events.DAMAGE_DEALT,test,function(_,hit)
            if hit.target==e.id then damage[#damage+1]=hit end
        end)
        for pose=1,3 do
            e.palette=rig.pose({time=pose,phase=pose*.8,walk=1,aim=1,pitch=.3,crouch=(pose-1)/2})
            soldiers.sync(ctx.services.soldiers,e)
            local volumes=rig.volumes(e.palette,e.position,e.yaw,e.id)
            local native=weapons.query({ctx.services.soldiers.by_id},{groups={hash("enemy")}})
            for _,volume in ipairs(volumes) do
                local origin=T.point(volume.transform,{x=0,y=0,z=volume.d/2+.02})
                local direction=T.direction(volume.transform,{x=0,y=0,z=-1})
                local found=false
                for _,hit in ipairs(native:segment(origin,direction,.1)) do
                    if hit.id==volume.id then found=true;near(hit.enter,.02,1e-5) end
                end
                assert(found,"Bullet missing "..volume.id.." pose "..pose.." "..json.encode({origin=origin,direction=direction,volume=volume,hits=native:segment(origin,direction,.1)}))
                -- Isolate each native collider for its scale check; a separate
                -- whole-body shot below verifies overlap ownership.
                local selected={segment=function(_,from,dir,length)
                    local out={};for _,hit in ipairs(native:segment(from,dir,length)) do
                        if hit.id==volume.id then out[#out+1]=hit end
                    end;return out
                end}
                combat.remove(ctx.combat,e.id);e.actor=combat.register(ctx.combat,e.id,1000)
                local before=#damage
                fire(selected,0,origin,direction)
                combat.fixed_update(ctx,1/120)
                assert(#damage==before+1 and damage[#damage].part==volume.part)
                near(1000-e.actor.health,20*volume.damage_scale,1e-5)
            end
        end
        check("all_animated_native_regions",{poses=3,volumes_per_pose=11})
        e.palette=rig.pose({});soldiers.sync(ctx.services.soldiers,e)
        local head=rig.volumes(e.palette,e.position,e.yaw,e.id)[1]
        local native=weapons.query({ctx.services.soldiers.by_id},{groups={hash("enemy")}})
        combat.remove(ctx.combat,e.id);e.actor=combat.register(ctx.combat,e.id,100)
        local head_def={};for k,v in pairs(definition) do head_def[k]=v end;head_def.damage=33
        local before=#damage
        fire(native,0,T.point(head.transform,{x=0,y=0,z=.4}),T.direction(head.transform,{x=0,y=0,z=-1}),head_def)
        combat.fixed_update(ctx,1/120)
        assert(#damage==before+1 and damage[#damage].headshot and not e.actor.alive)
        check("whole_actor_headshot_kills_once")
        events.off_owner(ctx.events,test)

        for _,case in ipairs({{100,"blocked_target",true},{104,"clear_target",false}}) do
            player.reset(ctx,{x=case[1],y=.01,z=0},0);frames(4)
            self.weapon_drive=driver.new({{ticks=90,aim=true},{ticks=1,aim=true,fire=true},{ticks=10,aim=true}})
            wait(function() return self.weapon_drive.complete end)
            local health=ctx.combat.actors[case[2]].health
            assert((health==1000)==case[3],case[2].."="..health)
        end
        check("production_eye_origin_and_muzzle_obstruction")
        local live=ballistics.spawn(ctx.weapons.sim,d,{x=70,y=10,z=0},{x=0,y=0,z=-1})
        test.hold_pause=true;runtime.set_paused(ctx,true)
        local point=V.copy(live.position);local age=live.age;frames(20)
        near(live.position.z,point.z);near(live.age,age)
        test.hold_pause=false;runtime.set_paused(ctx,false);frames(3)
        assert(live.age>age);check("pause_freezes_in_flight_rounds")
        table.remove(self.bullet_registries)
        world.final(fixtures);combat.remove(ctx.combat,"blocked_target");combat.remove(ctx.combat,"clear_target")
        for _=1,3 do
            restart(self);ctx.ai.enabled=false;frames(5)
            local state=soldiers.snapshot(ctx.services.soldiers)
            assert(state.active_hitboxes==66 and state.objects==78 and state.buffers==1,json.encode(state))
            assert(#ctx.weapons.sim.live==0 and ctx.weapons.sim.deflections==0)
        end
        check("repeated_reset_keeps_66_hitboxes_and_clears_rounds")
        test.done=true;report("PASS",{checks=test.checks,platform=sys.get_sys_info().system_name})
    end) end
    local ok,err=coroutine.resume(test.job)
    if not ok then test.done=true;error(err) end
end
return M
