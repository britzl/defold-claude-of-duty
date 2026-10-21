package.path='./?.lua;'..package.path
local input=require 'game.input'
local pad=require 'game.gamepad'
local controls=require 'game.ui.controls'
local count=0
local function test(name,fn) fn();count=count+1;print('PASS '..name) end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a)..' != '..tostring(b)) end
local function setup()
    local s,i,c=pad.new(),input.new(),controls.new()
    local function event(name,value,index,paused)
        return pad.handle(s,i,name,{value=value,gamepad=index or 0},not paused,paused)
    end
    return s,i,c,event
end
test('gamepad deadzone, proportional movement and diagonal bound',function()
    local s,i,c,e=setup()
    e('move_right',.1);pad.fixed_update(s,i,1/120,c,true);near(i.move_x,0)
    e('move_right',.59);pad.fixed_update(s,i,1/120,c,true);near(i.move_x,.5)
    e('move_up',1);e('move_right',1);pad.fixed_update(s,i,1/120,c,true)
    near(i.move_x*i.move_x+i.move_z*i.move_z,1)
    e('move_up',0);e('move_right',0);pad.fixed_update(s,i,1/120,c,true);near(i.move_x,0)
end)
test('gamepad look is fixed-time, inverted and slower in ADS',function()
    local s,i,c,e=setup();e('look_right',1);e('look_up',1)
    pad.fixed_update(s,i,1/60,c,true);local x,y=i.look_x,i.look_y
    input.end_tick(i);pad.fixed_update(s,i,1/120,c,true);pad.fixed_update(s,i,1/120,c,true)
    near(i.look_x,x);near(i.look_y,y)
    input.end_tick(i);c.invert_look=true;e('aim',1);pad.fixed_update(s,i,1/60,c,true)
    near(i.look_x,x*.48);near(i.look_y,-y*.48)
end)
test('pause quarantine requires neutral sticks and released triggers',function()
    local s,i,c,e=setup();e('fire',1);e('move_up',1);e('look_right',1)
    assert(i.buttons.fire.held);pad.reset(s,i);input.end_tick(i)
    e('fire',1);e('move_up',1);e('look_right',1);pad.fixed_update(s,i,1/120,c,true)
    assert(not i.buttons.fire.held);near(i.move_z,0);near(i.look_x,0)
    e('fire',0);e('move_up',0);e('look_right',0);e('fire',1);e('move_up',1)
    pad.fixed_update(s,i,1/120,c,true);assert(i.buttons.fire.held and i.move_z==-1)
end)
test('one controller owns input; disconnect releases only its source',function()
    local s,i,c,e=setup();e('fire',1);e('fire',0,1);assert(i.buttons.fire.held)
    input.button(i,'fire',{pressed=true},'touch')
    assert(e('disconnected',0)=='disconnect');assert(i.buttons.fire.held)
    input.button(i,'fire',{released=true},'touch');assert(not i.buttons.fire.held)
    e('fire',1,1);assert(i.buttons.fire.held and s.index==1)
end)
test('gamepad menus repeat directions but never confirm, and back resumes',function()
    local s,i,c,e=setup()
    assert(e('move_down',1,0,true)=='ui_down')
    assert(pad.menu_update(s,.5)=='ui_down')
    e('move_down',0,0,true);assert(not pad.menu_update(s,1))
    assert(e('jump',1,0,true)=='ui_confirm');assert(not pad.menu_update(s,1))
    assert(e('crouch',1,0,true)=='cancel')
    assert(not i.buttons.jump.held and not i.buttons.crouch.held)
end)
test('keyboard reference stance transitions and alias hold independence',function()
    local c,i=controls.new(),input.new()
    local function tap(n) controls.button(c,i,n,{pressed=true});controls.button(c,i,n,{released=true}) end
    tap('crouch');assert(i.buttons.crouch.held)
    tap('crouch');assert(not i.buttons.crouch.held)
    tap('prone');assert(i.buttons.prone.held)
    tap('prone');assert(not i.buttons.prone.held and i.buttons.crouch.held)
    tap('jump');assert(not i.buttons.crouch.held)
    controls.button(c,i,'forward',{pressed=true},'W');controls.button(c,i,'forward',{pressed=true},'UP')
    controls.button(c,i,'forward',{released=true},'W');assert(i.buttons.forward.held)
end)
test('settings bounds and defaults cover all adapters without mutating global tuning',function()
    local c=controls.new()
    for key,value in pairs({fov=90,sensitivity=2,touch_sensitivity=.5,gamepad_sensitivity=1.5,invert_look=true}) do
        controls.configure(c,value,key);assert(c[key]==value)
    end
    for key,value in pairs({fov=180,touch_sensitivity=0,gamepad_sensitivity=0/0,invert_look=1}) do
        assert(not pcall(controls.configure,c,value,key))
    end
    controls.defaults(c);assert(c.fov==70 and not c.invert_look and c.touch_sensitivity==1)
end)
test('adjustable FOV reaches the rendered camera and survives pause',function()
    local runtime=require 'game.runtime'
    local camera=require 'game.player.camera'
    local ctx=runtime.new();ctx.world.ready=true;ctx.preferences=controls.new()
    controls.configure(ctx.preferences,90,'fov')
    for n=1,3 do camera.update(ctx,1/120) end
    local out={camera={}};camera.compose(ctx,1,out)
    near(out.fov,math.rad(90))
    runtime.set_paused(ctx,true);runtime.set_paused(ctx,false)
    assert(ctx.preferences.fov==90)
    runtime.final(ctx)
end)
test('gamepad releases after focus loss cannot navigate on return',function()
    local s,i,c,e=setup()
    e('move_down',1,0,true);pad.reset(s,i)
    pad.handle(s,i,'move_down',{gamepad=0,value=1},false,false)
    assert(not pad.menu_update(s,1))
    e('move_down',0,0,true)
    assert(e('move_down',1,0,true)=='ui_down')
end)
print(count..' input adapter tests passed')
