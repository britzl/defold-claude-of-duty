package.path = "./?.lua;" .. package.path
local runtime = require "game.runtime"
local input = require "game.input"
local combat = require "game.combat"
local hud = require "game.ui.hud"
local controls = require "game.ui.controls"
local events = require "game.events"
local ai = require "game.systems.ai"
local ballistics = require "game.weapons.ballistics"
local defs = require "game.weapons.defs"
local h, count = 1/120, 0
local function test(name, run)
    run(); count=count+1; print("PASS "..name)
end
local function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." != "..tostring(b)) end
local function ready()
    local ctx=runtime.new()
    while not ctx.world.ready do runtime.update(ctx,1/60) end
    ai.reset(ctx,{x=0,y=0,z=-10},0)
    for _=1,90 do runtime.fixed_update(ctx,h);runtime.update(ctx,h) end
    return ctx
end

test("pause freezes ticks, reloads, rounds, damage and presentation without catch-up", function()
    local ctx=ready()
    ctx.weapons.inventory.rifle.mag=10
    input.button(ctx.input,"reload",{pressed=true})
    runtime.fixed_update(ctx,h);runtime.update(ctx,h)
    assert(ctx.weapons.clip=="reloadTac")
    input.button(ctx.input,"forward",{pressed=true})
    input.button(ctx.input,"fire",{pressed=true})
    input.look(ctx.input,50,10)
    combat.request(ctx.combat,{target="player",amount=25})
    local tick,elapsed,clip=ctx.time.tick,ctx.time.elapsed,ctx.weapons.clip_time
    local px,py,pz=ctx.presentation.camera.x,ctx.presentation.camera.y,ctx.presentation.camera.z
    local round=ballistics.spawn(ctx.weapons.sim,defs.rifle,{x=0,y=2,z=0},{x=0,y=0,z=-1},"player")
    local round_age,round_z=round.age,round.position.z
    runtime.set_paused(ctx,true)
    for _=1,240 do runtime.fixed_update(ctx,h);runtime.update(ctx,h) end
    assert(ctx.time.tick==tick and ctx.time.elapsed==elapsed and ctx.player.actor.health==100)
    assert(ctx.weapons.clip_time==clip and round.age==round_age and round.position.z==round_z)
    near(ctx.presentation.camera.x,px);near(ctx.presentation.camera.y,py);near(ctx.presentation.camera.z,pz)
    assert(ctx.player.intent.move_z==0 and not ctx.input.buttons.fire.held and ctx.input.look_x==0)
    assert(ctx.audio.suspended)
    runtime.set_paused(ctx,false)
    runtime.fixed_update(ctx,h);runtime.update(ctx,h)
    assert(ctx.player.actor.health==75 and ctx.time.tick==tick+1)
    near(ctx.weapons.clip_time,clip+h);near(ctx.time.elapsed,elapsed+h)
    assert(round.age>round_age and round.position.z<round_z)
    assert(not ctx.audio.suspended and ctx.weapons.shot_index==0)
    assert(ctx.player.intent.move_z==0 and ctx.player.intent.look_x==0)
    runtime.final(ctx)
end)

test("focus return cannot resume combat or audio until an explicit resume", function()
    local controller=require "game.ui.controller"
    local previous_window,previous_msg=window,msg
    window={set_mouse_lock=function() end}
    msg={post=function() end}
    local self={ctx=ready(),ui=controls.new(),focused=true,
        renderer_settings=require("game.render.settings").defaults()}
    input.button(self.ctx.input,"fire",{pressed=true})
    controls.observe(self.ui,"fire",{pressed=true})
    controller.focus(self,false)
    assert(self.ctx.paused and self.ctx.audio.suspended and not self.focused)
    controller.pause(self,false)
    assert(self.ctx.paused)
    controller.focus(self,true)
    assert(self.focused and self.ctx.paused and self.ctx.audio.suspended)
    controller.pause(self,false)
    assert(not self.ctx.paused and not self.ctx.audio.suspended and not self.ctx.input.buttons.fire.held)
    runtime.final(self.ctx)
    window,msg=previous_window,previous_msg
end)

test("pausing during loading still finishes bounded world generation", function()
    local ctx=runtime.new()
    runtime.set_paused(ctx,true)
    -- This is a pause/progress check, not a fixed wall-clock loading budget.
    -- Dense world clipping still obeys each update's 2 ms work deadline.
    for _=1,3000 do
        runtime.fixed_update(ctx,h);runtime.update(ctx,h)
        if ctx.world.ready then break end
    end
    assert(ctx.world.ready and ctx.time.tick==0 and ctx.audio.ready)
    runtime.set_paused(ctx,false)
    runtime.fixed_update(ctx,h)
    assert(ctx.time.tick==1)
    runtime.final(ctx)
end)

test("killfeed emits once per death, bounds floods, freezes during pause and clears on restart", function()
    local ctx=ready()
    for i=1,7 do
        local id="enemy_test"..i
        combat.register(ctx.combat,id,10)
        combat.request(ctx.combat,{target=id,source="player",amount=20,headshot=i==7})
        combat.request(ctx.combat,{target=id,source="player",amount=20})
    end
    runtime.fixed_update(ctx,h)
    local state=hud.snapshot(ctx)
    assert(state.feed_count==4 and state.headshot)
    assert(ctx.hud.feed[1].text=="YOU  >  HOSTILE  [HEAD]")
    runtime.set_paused(ctx,true)
    runtime.update(ctx,20)
    assert(hud.snapshot(ctx).feed_count==4)
    runtime.set_paused(ctx,false)
    runtime.update(ctx,hud.feed_seconds+.01)
    assert(hud.snapshot(ctx).feed_count==0)
    events.emit(ctx.events,events.DAMAGE_TAKEN,{source="enemy_1"})
    hud.reset(ctx)
    assert(hud.snapshot(ctx).damage==0 and not hud.snapshot(ctx).headshot)
    runtime.final(ctx)
end)

test("damage direction follows camera yaw and copies the source position at impact", function()
    local ctx=ready()
    ctx.presentation.position={x=0,y=0,z=0};ctx.presentation.yaw=0
    local enemy=ctx.ai.actors.enemy_1
    for _,v in ipairs({{0,-10,"front"},{10,0,"right"},{0,10,"back"},{-10,0,"left"}}) do
        enemy.position.x,enemy.position.z=v[1],v[2]
        events.emit(ctx.events,events.DAMAGE_TAKEN,{source="enemy_1"})
        enemy.position.x,enemy.position.z=100,100
        assert(hud.snapshot(ctx).damage_direction==v[3])
    end
    ctx.presentation.yaw=math.pi/2
    assert(hud.snapshot(ctx).damage_direction=="front")
    events.emit(ctx.events,events.DAMAGE_TAKEN,{})
    assert(hud.snapshot(ctx).damage_direction=="" and hud.snapshot(ctx).damage==1)
    runtime.final(ctx)
end)

test("compass wraps with north at -Z and east at +X", function()
    near(hud.heading(0),0);near(hud.heading(-math.pi/2),90)
    near(hud.heading(math.pi),180);near(hud.heading(math.pi/2),270)
    near(hud.heading(math.pi*4),0)
end)

test("minimap clips footprints to view and height without covering ground-floor doors with roofs", function()
    local shape={x=21,z=-10,w=8,d=4,bottom=0,top=3}
    local r=hud.map_rect(shape,0,0,0,176)
    near(r.x+r.w/2,88);near(r.y,40);assert(not r.floor)
    shape.bottom=3.2;shape.top=3.4
    assert(not hud.map_rect(shape,0,0,0,176))
    assert(hud.map_rect(shape,0,3.4,0,176).floor)
    shape.bottom=0;shape.top=.145;shape.x=100
    assert(not hud.map_rect(shape,0,0,0,176))
end)

test("held actions across menu transitions need release; a fresh press and sensitivity remain valid", function()
    local state=controls.new()
    controls.observe(state,"fire",{pressed=true})
    controls.quarantine(state)
    controls.observe(state,"fire",{pressed=true})
    assert(not controls.allowed(state,"fire"))
    controls.observe(state,"forward",{pressed=true}) -- pressed inside menu
    controls.quarantine(state)
    assert(not controls.allowed(state,"forward"))
    controls.observe(state,"fire",{released=true})
    controls.observe(state,"fire",{pressed=true})
    assert(controls.allowed(state,"fire"))
    controls.configure(state,1.75)
    for _,bad in ipairs({0,-1,3.1,math.huge,0/0,"1"}) do
        assert(not pcall(controls.configure,state,bad));assert(state.sensitivity==1.75)
    end
end)
print(count.." UI tests passed")
