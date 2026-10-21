local runtime=require "game.runtime"
local F=require "game.ui.feedback"
local hud=require "game.ui.hud"
local player=require "game.systems.player"
local ai=require "game.systems.ai"
local grenades=require "game.systems.grenades"
local combat=require "game.combat"
local input=require "game.input"
local events=require "game.events"
local ui=require "game.ui.controller"
local M={}
local function report(kind,data)
    local line="HUD_FEEDBACK "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    report("START",sys.get_engine_info())
    local t={checks=0}
    if automation_bridge then automation_bridge.command("hud.validation_continue",function(data) t.ack=data.id;return {ok=true} end) end
    return t
end
function M.update(t,self,dt,restart)
    if t.done then return end
    local ctx=self.ctx
    ctx.ai.enabled=false;self.focused=true
    local menu=ui.snapshot(self);menu.paused=false;menu.focused=true
    msg.post("/hud#gui","menu_state",menu)
    if not t.hold then runtime.set_paused(ctx,false) end
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not t.job then t.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function seconds(n) local at=ctx.time.elapsed+n;repeat frames(1) until ctx.time.elapsed>=at end
        local function check(name) t.checks=t.checks+1;report("CHECK",{name=name}) end
        local function receipt()
            self.hud_receipt=nil;msg.post("/hud#gui","hud_inspect",{})
            for _=1,10 do frames(1);if self.hud_receipt then return self.hud_receipt end end
            error("HUD receipt timeout")
        end
        local function shot(id)
            t.hold=true;runtime.set_paused(ctx,true);frames(4)
            t.ack=nil;report("SHOT",{id=id})
            local waiting=0
            repeat
                frames(1);waiting=waiting+1
                if html5 then
                    if html5.run("window.__HUD_SHOT_ACK__ === "..json.encode(id).." ? '1' : '0'")=="1" then t.ack=id end
                end
                assert(waiting<6000,"screenshot acknowledgement timeout")
            until t.ack==id
            t.hold=false;runtime.set_paused(ctx,false)
        end
        local function reset()
            restart(self);ctx.ai.enabled=false;ctx.ai.damage_scale=0;self.view=nil
            player.reset(ctx,{x=0,y=.01,z=4},0);frames(8)
        end
        reset()
        ai.reset(ctx,{x=3,y=.01,z=-6},0);frames(8)
        local r=receipt();assert(r.contacts>0 and r.numbers==0 and r.banner=="")
        check("live_enemy_minimap_contacts")
        local enemy=ctx.ai.actors.enemy_1
        enemy.position.y=3.3
        local items=F.items(ctx,960,640);local above=false
        for _,p in ipairs(items.contacts) do if p.id==enemy.id then above=p.floor==1 end end
        assert(above);enemy.position.y=.01
        check("contact_floor_hint")
        combat.request(ctx.combat,{target="enemy_1",source="player",amount=120,headshot=true,point={x=3,y=1.6,z=-6}})
        combat.request(ctx.combat,{target="player",source="enemy_2",amount=76,from={x=5,y=1.5,z=-4}})
        frames(5);r=receipt()
        assert(r.numbers==1 and r.arcs==1 and r.banner=="ENEMY ELIMINATED")
        assert(F.snapshot(ctx).hit_kind=="kill" and not enemy.actor.alive and ctx.player.actor.health==24)
        check("combat_owner_drives_numbers_banner_arcs_and_health")
        assert(grenades.launch(ctx,"enemy_2",{x=-3,y=.3,z=6},{x=0,y=0,z=0}))
        frames(4);r=receipt();assert(r.grenades==1)
        items=F.items(ctx,960,640);assert(items.grenades[1].offscreen and items.grenades[1].fuse>0)
        check("real_bullet_grenade_behind_camera_fuse")
        F.set_objectives(ctx,{{position={x=2,y=1.7,z=-14},label="A",name="DISPLAY FIXTURE"}})
        F.set_prompt(ctx,{key="F",text="DISPLAY FIXTURE",sub="NO GAME ACTION",progress=.6})
        frames(3);r=receipt();assert(r.objectives==1 and r.prompt=="[F]  DISPLAY FIXTURE")
        check("optional_objective_and_prompt_display")
        shot("combat")
        local saved=ctx.hud.feedback.numbers[1].age
        t.hold=true;runtime.set_paused(ctx,true);frames(20)
        assert(ctx.hud.feedback.numbers[1].age==saved)
        check("pause_freezes_transients_and_fuses")
        for _,mode in ipairs({"diagnostic","inspection"}) do
            if mode=="diagnostic" then self.renderer_settings.view="normals" else self.renderer_settings.view="scene";self.view=next(ctx.world.views) end
            frames(4);r=receipt()
            assert(r.grenades==0 and r.contacts==0 and r.numbers==0 and r.arcs==0 and r.prompt=="",mode.." "..json.encode(r))
        end
        self.renderer_settings.view="scene";self.view=nil
        check("diagnostic_and_inspection_hide_combat_feedback")
        t.hold=false;runtime.set_paused(ctx,false)
        seconds(3);r=receipt();assert(r.numbers==0 and r.arcs==0 and r.banner=="" and r.grenades==0)
        check("expired_hits_and_detonated_grenade_release_nodes")
        reset();seconds(.7);ctx.weapons.inventory.rifle.mag=4
        input.button(ctx.input,"reload",{pressed=true});seconds(.7);r=receipt()
        assert(r.reload and r.reload_width>0 and r.reload_width<188 and F.snapshot(ctx).mag==0,json.encode(F.snapshot(ctx)))
        check("reload_progress_and_removed_magazine")
        shot("reload");seconds(2);r=receipt();assert(not r.reload and F.snapshot(ctx).mag==30)
        check("reload_completion_restores_magazine")
        for _,entry in ipairs({{"smg",32},{"pistol",17},{"rifle",30}}) do
            ctx.weapons.equipped=entry[1];frames(3);r=receipt();assert(r.pips==entry[2])
        end
        check("all_weapon_magazine_capacities")
        for i=1,80 do
            events.emit(ctx.events,events.DAMAGE_DEALT,{source="player",target="enemy_2",amount=12,point={x=(i%5)-2,y=1.5,z=-6}})
            events.emit(ctx.events,events.DAMAGE_TAKEN,{amount=1,from={x=(i%5)+1,y=1,z=-6}})
        end
        frames(3);r=receipt();assert(r.numbers==16 and r.arcs==6)
        check("event_pressure_reuses_bounded_gui_pools")
        for _=1,3 do reset();r=receipt();assert(r.numbers==0 and r.arcs==0 and r.grenades==0 and r.objectives==0 and r.prompt=="") end
        check("three_restarts_clear_all_feedback_and_display_hooks")
        combat.request(ctx.combat,{target="player",amount=999});frames(4);r=receipt()
        assert(r.contacts==0 and r.arcs==0 and r.numbers==0)
        check("death_hides_combat_markers")
        reset();combat.request(ctx.combat,{target="player",amount=76});seconds(5)
        assert(ctx.player.actor.regenerating);shot("recovery")
        check("health_recovery_presentation")
        reset();t.done=true;report("PASS",{checks=t.checks,limits={contacts=F.contacts,grenades=F.grenades,numbers=F.numbers,arcs=F.arcs,objectives=F.objectives}})
    end) end
    local ok,err=coroutine.resume(t.job);if not ok then t.done=true;error(err) end
end
return M
