-- Shared native/WebGL fixture: production input, fixed ticks, Bullet and camera.
local runtime = require "game.runtime"
local player = require "game.systems.player"
local driver = require "game.player.driver"
local input = require "game.input"
local camera = require "game.player.camera"
local course = require "game.player.course"
local world_adapter = require "game.world.defold"
local M = {}
local function report(kind,data)
    local line="TRAVERSAL "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then
        sys.set_error_handler(function(_,message,traceback)
            html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(traceback))..")")
        end)
    end
    report("START",sys.get_engine_info())
    return {checks=0,frames=0}
end
function M.update(test,self,dt)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold_pause then runtime.set_paused(ctx,false) end
    ctx.ai.enabled=false
    if not ctx.world.ready or not ctx.services.capsule or not self.renderer_stats.ready then return end
    test.frames=test.frames+1
    if not test.job then
        test.job=coroutine.create(function()
            if not self.course then self.course=course.create() end
            local function frames(n) for _=1,n do coroutine.yield() end end
            local function wait(fn)
                local deadline=ctx.time.frame_elapsed+15
                while not fn() do assert(ctx.time.frame_elapsed<deadline,"Traversal timeout");coroutine.yield() end
            end
            local function check(name,data)
                test.checks=test.checks+1;report("CHECK",{name=name,result=data or {}})
            end
            local function reset(x,z,y)
                input.reset(ctx.input);self.view=nil;ctx.player.enabled=true;ctx.player.drive=nil
                player.reset(ctx,{x=x,y=y or 0.01,z=z or -11},0)
                ctx.weapons.ads,ctx.weapons.previous_ads=0,0
                frames(3)
            end
            local function drive(segments)
                ctx.player.drive=driver.new(segments)
                wait(function() return ctx.player.drive.complete end)
                local r=ctx.player.drive.result
                assert(not r.recovery_failed and r.min_y> -0.02,json.encode(r))
                return r
            end
            frames(5)
            for _,sprint in ipairs({false,true}) do
                reset(46)
                local r=drive({{ticks=120,move_z=-1,sprint=sprint}})
                assert(r.vaults==1 and r.vault_completions==1 and r.vault_aborts==0 and r.z< -14.7 and r.grounded,json.encode(r))
                check(sprint and "sprint_vault" or "walk_vault",r)
            end
            reset(94,-13.325)
            local r=drive({{ticks=100,move_z=-1,jump=true}})
            assert(r.vault_completions==1 and r.y<0.02 and r.z< -14.7,json.encode(r))
            check("explicit_high_vault",r)
            reset(62,-2.4)
            r=drive({{ticks=50,move_z=-1,jump=true}})
            assert(r.mantle_completions==1 and r.vaults==0 and math.abs(r.y-0.65)<0.015,json.encode(r))
            check("deep_ledge_mantle",r)
            reset(56,0)
            r=drive({{ticks=140,move_z=-1}})
            assert(r.mantles==0 and r.y>0.59,json.encode(r));check("stairs_remain_steps",r)
            reset(110)
            r=drive({{ticks=120,move_z=-1,sprint=true}})
            assert(r.vaults==0 and r.z> -14,json.encode(r));check("blocked_landing",r)

            reset(46,-13.2)
            ctx.player.drive=driver.new({{ticks=1,move_z=-1,jump=true}})
            wait(function() return ctx.player.drive.complete end)
            assert(ctx.player.motion.mantle and ctx.player.motion.mantle.kind=="vault")
            wait(function() return ctx.player.motion.mantle.time>=0.14 end)
            test.hold_pause=true;runtime.set_paused(ctx,true)
            local time,breath=ctx.player.motion.mantle.time,ctx.player.camera.breath
            local pose=camera.compose(ctx,1,{})
            frames(3);report("SHOT",{id="vault_paused"});frames(45)
            assert(ctx.player.motion.mantle.time==time and ctx.player.camera.breath==breath)
            local frozen=camera.compose(ctx,1,{})
            assert(frozen.camera.y==pose.camera.y and frozen.pitch==pose.pitch)
            test.hold_pause=false;runtime.set_paused(ctx,false)
            r=drive({{ticks=80}})
            assert(r.vault_completions==1 and r.grounded,json.encode(r))
            check("pause_resume_vault",r)

            reset(46,0)
            input.button(ctx.input,"forward",{pressed=true})
            input.button(ctx.input,"sprint",{pressed=true})
            local tick=ctx.time.tick;wait(function() return ctx.time.tick>=tick+150 end)
            local fov=camera.compose(ctx,1,{}).fov
            assert(math.abs(fov-math.rad(70)*1.055)<0.001,tostring(fov))
            check("sprint_fov",{fov=fov})
            input.reset(ctx.input);ctx.player.drive=nil
            input.button(ctx.input,"aim",{pressed=true})
            tick=ctx.time.tick;wait(function() return ctx.time.tick>=tick+150 end)
            fov=camera.compose(ctx,1,{}).fov
            assert(math.abs(fov-math.rad(70)*require("game.weapons.defs").rifle.adsFov)<0.001)
            frames(2)
            assert(math.abs(go.get("/camera#camera","fov")-ctx.presentation.fov)<0.001)
            check("ads_fov_applied_to_camera",{fov=fov})
            reset(46,0,3)
            local min_dip,max_roll=0,0
            wait(function()
                min_dip=math.min(min_dip,ctx.player.camera.dip.x)
                max_roll=math.max(max_roll,math.abs(ctx.player.camera.roll.x))
                return ctx.player.motion.grounded and min_dip< -0.03
            end)
            assert(max_roll>0.001);check("landing_camera",{dip=min_dip,roll=max_roll})
            player.camera_impulse(ctx,"suppression",0.6,{x=1,z=-1})
            player.camera_impulse(ctx,"explosion",0.5,{x=-1,z=-1})
            assert(ctx.player.camera.trauma>0 and ctx.player.camera.suppression>0)
            check("impulse_channels")

            reset(46,-13.2)
            ctx.player.drive=driver.new({{ticks=120,move_z=-1,jump=true}})
            wait(function() return ctx.player.motion.mantle~=false end)
            local start_z=ctx.player.position.z
            world_adapter.add_collision(self.course,{id="course/dynamic_wall",x=46,y=1.5,z=-14.7,
                w=3,h=3,d=0.15,surface="concrete"})
            wait(function() return ctx.player.drive.mantle_aborts>0 end)
            assert(ctx.player.drive.vault_aborts==1 and ctx.player.position.z> -14.7)
            check("dynamic_obstruction_aborts",{start_z=start_z,z=ctx.player.position.z})
            reset(56,-12.9)
            ctx.player.drive=driver.new({{ticks=120,move_z=-1,jump=true}})
            wait(function() return ctx.player.motion.mantle~=false end)
            require("game.combat").request(ctx.combat,{target="player",amount=1000})
            wait(function() return not ctx.player.actor.alive and not ctx.player.motion.mantle end)
            assert(ctx.player.camera.trauma==0 and ctx.player.camera.current.roll==0)
            check("death_cancels_and_clears_camera")
            test.done=true
            report("PASS",{checks=test.checks,frames=test.frames,platform=sys.get_sys_info().system_name})
        end)
    end
    local ok,err=coroutine.resume(test.job)
    if not ok then test.done=true;error(err) end
end
return M
