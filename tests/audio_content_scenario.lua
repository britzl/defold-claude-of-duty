-- Shared real-engine audio fixture. Event-only auditions are distinguished from
-- actual Bullet contacts, projectile travel, AI strides and combat-owner damage.
local runtime=require "game.runtime"
local audio=require "game.systems.audio"
local player=require "game.systems.player"
local ai=require "game.systems.ai"
local combat=require "game.combat"
local events=require "game.events"
local dynamics=require "game.physics.defold"
local grenades=require "game.systems.grenades"
local ballistics=require "game.weapons.ballistics"
local M={}
local function report(kind,data)
    local line="AUDIO_CONTENT "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    report("START",sys.get_engine_info());return {checks=0}
end
function M.update(t,self,dt,restart)
    if t.done then return end
    local ctx=self.ctx
    if not t.hold then runtime.set_paused(ctx,false);self.focused=true end
    if not t.live then ctx.ai.enabled=false end
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not t.job then t.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function seconds(n) local at=ctx.time.elapsed+n;repeat frames(1) until ctx.time.elapsed>=at end
        local function wait(fn,timeout,label)
            local at=ctx.time.elapsed+timeout
            while not fn() do assert(ctx.time.elapsed<at,label.." "..json.encode({audio=audio.snapshot(ctx),ai=ai.snapshot(ctx)}));frames(1) end
        end
        local function check(name,detail) t.checks=t.checks+1;report("CHECK",{name=name,detail=detail}) end
        local function count(kind) return ctx.audio.by_kind[kind] or 0 end
        local function reset()
            restart(self);ctx.ai.enabled=false;self.view=nil
            player.reset(ctx,{x=0,y=.01,z=4},0)
            audio.configure(ctx,{ambience=0});frames(8)
        end
        reset()
        local initial=audio.snapshot(ctx)
        assert(initial.loaded==234 and initial.bytes==10611456 and initial.verified==234)
        assert(initial.physical_voice_limit==72)
        check("native_lua_bank_parity_and_fixed_resources",{bytes=initial.bytes,samples=initial.loaded,voices=72})
        for _,name in ipairs({"rifle","smg","pistol"}) do
            local before=count("shot")
            audio.preview(ctx,{kind="shot",weapon=name,position={x=4,y=1.66,z=4}})
            wait(function() return count("shot")>before end,2,"shot")
            seconds(.12)
            local meter=audio.snapshot(ctx).meter
            assert(meter.right>meter.left and meter.right>0,"right channel output")
            check("audible_"..name.."_stereo",meter);seconds(1.4)
        end
        audio.preview(ctx,{kind="shot",weapon="rifle",position={x=-12,y=1.8,z=-6}})
        seconds(.22)
        local voice
        for _,v in ipairs(ctx.audio.voices) do if v.active and v.cue.kind=="shot" then voice=v;break end end
        assert(voice and voice.occlusion>.5,"wall did not muffle")
        local serial,blocked=voice.serial,voice.occlusion
        player.reset(ctx,{x=-12,y=.01,z=-6},0);seconds(.22)
        assert(voice.active and voice.serial==serial and voice.occlusion<blocked*.3 and voice.room>.3)
        check("moving_listener_filters_same_playback_continuously",{blocked=blocked,clear=voice.occlusion,wet=voice.room})
        reset()
        local before=count("shell")
        dynamics.spawn(ctx.services.dynamics,"casing",{x=1,y=3,z=4},{x=0,y=0,z=0},"rifle")
        frames(2);assert(count("shell")==before,"casing sounded before impact")
        wait(function() return count("shell")>before end,3,"Bullet casing impact")
        seconds(1);local settled=count("shell");seconds(1)
        assert(count("shell")==settled,"resting casing repeated")
        check("real_bullet_casing_contact_and_quiet_rest")
        before=count("near_miss")
        ballistics.spawn(ctx.ai.sim,{id="fixture",muzzleVelocity=500,damage=1,penetration=.5,dropoff=1,maxRange=60,dragK=0},
            {x=1,y=ctx.audio.listener.position.y,z=2},{x=0,y=0,z=1},"enemy_1",true)
        ballistics.update(ctx,ctx.ai.sim,1/120,ctx.services.enemy_bullets);frames(3)
        assert(count("near_miss")==before+1)
        check("travelled_hostile_round_has_one_crack")
        local pin,bounce,blast=count("grenade"),count("bounce"),count("explosion")
        ctx.ai.damage_scale=0
        assert(grenades.launch(ctx,"enemy_1",{x=3,y=2,z=4},{x=0,y=0,z=0}))
        wait(function() return count("explosion")>blast end,5,"grenade explosion")
        assert(count("grenade")>pin and count("bounce")>bounce and ctx.audio.deafness>.4 and count("tinnitus")>0)
        check("physical_grenade_pin_bounce_blast_and_concussion",{deafness=ctx.audio.deafness})
        local deaf=ctx.audio.deafness;t.hold=true;runtime.set_paused(ctx,true)
        frames(25);assert(ctx.audio.deafness==deaf and audio.snapshot(ctx).active==0)
        t.hold=false;runtime.set_paused(ctx,false);seconds(1);assert(ctx.audio.deafness<deaf)
        check("pause_silences_and_freezes_concussion_recovery")
        reset()
        ai.reset(ctx,{x=3,y=.01,z=4},0)
        local body,barks,hits=count("body"),count("bark"),count("hit")
        combat.request(ctx.combat,{target="enemy_1",source="player",amount=120,headshot=true,point={x=3,y=1.4,z=4}})
        wait(function() return count("body")>body end,4,"ragdoll floor impact")
        assert(count("bark")>barks and count("hit")>hits)
        check("combat_confirmation_death_bark_and_body_contact")
        reset()
        combat.request(ctx.combat,{target="player",source="enemy_1",amount=85})
        local heart=count("heartbeat");wait(function() return count("heartbeat")>heart end,3,"critical heartbeat")
        check("real_low_health_heartbeat")
        reset()
        ai.reset(ctx,{x=0,y=.01,z=4},0)
        local e=ctx.ai.actors.enemy_1
        e.patrol_points={{x=0,y=.01,z=4},{x=0,y=.01,z=-2}};e.patrol=2
        player.reset(ctx,{x=0,y=.01,z=20},0);t.live=true;ctx.ai.enabled=true;ctx.ai.damage_scale=0
        local steps=count("soldier_step")
        wait(function() return count("soldier_step")>steps end,8,"AI stride footsteps")
        t.live=false;ctx.ai.enabled=false;check("real_ai_stride_footsteps")
        ctx.audio.battle_due=ctx.audio.scene_clock;local battle=count("battle")
        wait(function() return count("battle")>battle end,2,"distant battle schedule")
        check("simulation_clock_distant_battle")
        for _=1,3 do reset();wait(function() return audio.snapshot(ctx).active==2 end,3,"restart voice cleanup");assert(ctx.audio.deafness==0 and ctx.audio.bytes==initial.bytes and audio.snapshot(ctx).active==2) end
        check("three_restarts_release_layers_and_reuse_bank")
        local peak=0
        for _=1,120 do
            events.emit(ctx.events,events.WEAPON_FIRE,{weapon="rifle"})
            for i=1,4 do events.emit(ctx.events,events.BULLET_IMPACT,{surface="metal",point={x=i,y=1,z=4},normal={x=0,y=1,z=0},incident={x=0,y=-1,z=0},damage=10}) end
            frames(2);local s=audio.snapshot(ctx);peak=math.max(peak,s.meter.left,s.meter.right)
            assert(s.active<=24 and s.pending<=64 and s.last_probes<=4 and s.meter.left<=.86 and s.meter.right<=.86)
        end
        assert(ctx.audio.preempted>0,"priority sounds never replaced effect tails")
        check("sustained_fire_bounded_layers_probes_and_output",{peak=peak,dropped=ctx.audio.dropped,preempted=ctx.audio.preempted})
        audio.configure(ctx,{master=0});seconds(.3)
        local silent=audio.snapshot(ctx).meter;assert(silent.left<.000001 and silent.right<.000001)
        check("master_zero_mutes_all_layers",silent)
        audio.configure(ctx,{master=.8,ambience=.6});t.done=true
        local receipt=audio.snapshot(ctx);receipt.voices=nil;receipt.last=nil
        report("PASS",{checks=t.checks,audio=receipt})
    end) end
    local ok,message=coroutine.resume(t.job);if not ok then t.done=true;error(message) end
end
return M
