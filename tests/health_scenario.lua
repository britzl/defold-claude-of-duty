-- Shared native/WebGL checks using production Bullet, projectiles and health.
local runtime=require "game.runtime"
local player=require "game.systems.player"
local health=require "game.player.health"
local combat=require "game.combat"
local events=require "game.events"
local ballistics=require "game.weapons.ballistics"
local defs=require "game.weapons.defs"
local M={}
local function report(kind,data)
    local line="HEALTH "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then
        sys.set_error_handler(function(_,message,trace)
            html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(trace))..")")
        end)
    end
    report("START",sys.get_engine_info())
    return {checks=0}
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold_pause then
        local changed=ctx.paused or not self.focused
        runtime.set_paused(ctx,false);self.focused=true
        if changed then require("game.ui.controller").publish(self) end
    end
    ctx.ai.enabled=false
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then
        test.job=coroutine.create(function()
            if not self.course then self.course=require("game.player.course").create() end
            local function frames(n) for _=1,n do coroutine.yield() end end
            local function wait(fn)
                local deadline=ctx.time.frame_elapsed+20
                while not fn() do assert(ctx.time.frame_elapsed<deadline,"Health fixture timed out");coroutine.yield() end
            end
            local function ticks(n)
                local target=ctx.time.tick+n;wait(function() return ctx.time.tick>=target end)
            end
            local function check(name)
                test.checks=test.checks+1;report("CHECK",{name=name,state=health.snapshot(ctx)})
            end
            local function fresh(x,y,z)
                restart(self);ctx.ai.enabled=false
                player.reset(ctx,{x=x or 46,y=y or .01,z=z or 0},0);frames(3)
            end
            local function damage(amount)
                combat.request(ctx.combat,{target="player",amount=amount,from={x=48,y=1.7,z=0}})
                ticks(2)
            end
            fresh();damage(80)
            ticks(500);assert(ctx.player.actor.health==20 and not ctx.player.actor.regenerating)
            check("delayed_recovery")
            wait(function() return ctx.player.actor.since_damage>4.85 end)
            assert(ctx.player.actor.regenerating and ctx.player.actor.health>20 and ctx.player.actor.health<25)
            check("ramped_recovery")
            damage(5);local value=ctx.player.actor.health;ticks(120)
            assert(ctx.player.actor.health==value and not ctx.player.actor.regenerating)
            test.hold_pause=true;runtime.set_paused(ctx,true)
            local frozen=json.encode(health.snapshot(ctx));frames(35)
            assert(json.encode(health.snapshot(ctx))==frozen);check("pause_freezes_recovery")
            test.hold_pause=false;runtime.set_paused(ctx,false)
            wait(function() return ctx.player.actor.health==100 end)
            assert(not ctx.player.actor.regenerating);check("full_recovery")

            fresh(46,3)
            wait(function() return ctx.player.motion.grounded end);ticks(3)
            assert(ctx.player.actor.health==100);check("safe_drop")
            fresh(46,9)
            local speed
            events.on(ctx.events,events.PLAYER_LAND,test,function(_,e) speed=e.velocity end)
            wait(function() return ctx.player.motion.grounded end);ticks(3)
            assert(speed and speed>15)
            assert(math.abs(ctx.player.actor.health-(100-(speed-15)*7))<1e-5)
            value=ctx.player.actor.health;ticks(120);assert(ctx.player.actor.health==value)
            check("bullet_landing_damage_once")

            fresh()
            local sim=ballistics.new()
            local p=ballistics.spawn(sim,defs.rifle,{x=47,y=1.67,z=-4},{x=0,y=0,z=1},"enemy_1",false)
            ballistics.update(ctx,sim,1/120,ctx.services.enemy_bullets)
            assert(ctx.player.health_state.suppression>0 and ctx.player.actor.health==100)
            local pressure=ctx.player.health_state.suppression
            events.emit(ctx.events,events.BULLET_SEGMENT,{from=p.origin,to=p.position,source=p.source,round=p.token})
            assert(ctx.player.health_state.suppression==pressure);check("real_round_near_miss_deduplicated")

            fresh(50,.01,-2)
            sim=ballistics.new()
            ballistics.spawn(sim,defs.rifle,{x=50,y=1.67,z=-6},{x=0,y=0,z=1},"enemy_1",false)
            ballistics.update(ctx,sim,1/120,ctx.services.enemy_bullets)
            ticks(2)
            assert(ctx.player.actor.health==100 and ctx.player.health_state.suppression==0,json.encode(health.snapshot(ctx)))
            check("real_wall_blocks_round_and_pressure")

            fresh();sim=ballistics.new()
            ballistics.spawn(sim,defs.rifle,{x=46,y=1,z=-4},{x=0,y=0,z=1},"enemy_1",false)
            ballistics.update(ctx,sim,1/120,ctx.services.enemy_bullets);ticks(2)
            assert(ctx.player.actor.health<100 and ctx.player.health_state.suppression>0)
            assert(ctx.hud.source and ctx.hud.source.z==-4);check("real_round_damage_and_origin")
            value=ctx.player.actor.health
            events.emit(ctx.events,events.EXPLOSION,{position={x=45,y=1.67,z=0},radius=5,damage=90})
            assert(ctx.player.actor.health==value and ctx.player.health_state.suppression>0)
            check("explosion_feedback_has_no_damage_side_effect")

            fresh(0,.01,24);ticks(100)
            -- Freeze the same camera for healthy/low/recovered screenshots.
            ctx.player.enabled=false;ticks(4);frames(20)
            report("SHOT",{id="healthy"});frames(40)
            ctx.player.enabled=true;damage(90);ticks(160)
            local s=health.snapshot(ctx);assert(s.low and s.critical and s.effect>.7 and s.heartbeat_hz>1.7)
            ctx.player.enabled=false;ticks(4);frames(20)
            report("SHOT",{id="low_health"});frames(40)
            check("low_health_pulse_and_render_state")
            ctx.player.enabled=true
            wait(function() return ctx.player.actor.health==100 end);ticks(160)
            assert(ctx.player.health_state.effect<.004 and ctx.player.health_state.pulse==0)
            ctx.player.enabled=false;ticks(4);frames(20);report("SHOT",{id="recovered"});frames(40)
            ctx.player.enabled=true;damage(1000);ticks(900)
            s=health.snapshot(ctx);assert(s.dead and s.health==0 and s.pulse==0 and not s.regenerating)
            check("death_never_regenerates_or_beats")
            fresh();s=health.snapshot(ctx)
            assert(s.health==100 and s.effect==0 and s.suppression==0 and s.stimuli==0)
            check("restart_clears_feedback")
            events.off_owner(ctx.events,test)
            test.done=true
            report("PASS",{checks=test.checks,platform=sys.get_sys_info().system_name})
        end)
    end
    local ok,err=coroutine.resume(test.job)
    if not ok then test.done=true;error(err) end
end
return M
