package.path = "./?.lua;" .. package.path
local touch = require "game.touch"
local input = require "game.input"
local count=0
local function test(name,run) run();count=count+1;print("PASS "..name) end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." != "..tostring(b)) end
local function fixture(width,height,safe)
    local state,buffer,layout=touch.new(true),input.new(),touch.layout(width or 960,height or 640,safe)
    local function point(id,x,y,event)
        return {id=id,x=x/layout.width*960,y=y/layout.height*640,
            pressed=event=="down",released=event=="up"}
    end
    local function button(id,name,event)
        for _,b in ipairs(layout.buttons) do
            if b.id==name then return point(id,b.x,b.y,event) end
        end
        error(name)
    end
    local function send(...)
        return touch.handle(state,buffer,{...},layout,true,1)
    end
    return state,buffer,layout,point,button,send
end

test("mobile defaults, browser touch and explicit overrides",function()
    assert(touch.default_enabled("Android",false,-1))
    assert(touch.default_enabled("iPhone OS",false,-1))
    assert(touch.default_enabled("HTML5",true,-1))
    assert(not touch.default_enabled("HTML5",false,-1))
    assert(not touch.default_enabled("Darwin",false,-1))
    assert(touch.default_enabled("Darwin",false,1))
    assert(not touch.default_enabled("Android",true,0))
end)

test("stick dead zone, proportional speed, diagonal clamp and release",function()
    local s,i,l,p,b,send=fixture()
    local x,y=l.stick.x,l.stick.y
    send(p(7,x,y,"down"));near(i.move_x,0);near(i.move_z,0)
    send(p(7,x+5,y));near(i.move_x,0)
    send(p(7,x+l.stick.r*.575,y));near(i.move_x,.5)
    send(p(7,x+500,y+500));near(i.move_x^2+i.move_z^2,1)
    assert(i.move_z<0)
    input.end_tick(i);assert(i.move_x>0) -- sustained across fixed ticks
    send(p(7,x,y,"up"));near(i.move_x,0);near(i.move_z,0)
end)

test("stable finger IDs survive reordering while moving looking and firing",function()
    local s,i,l,p,b,send=fixture()
    local look=b(9,"look","down")
    local x,y=look.x*l.width/960,look.y*l.height/640
    send(p(41,l.stick.x,l.stick.y,"down"),look,b(72,"fire","down"))
    assert(i.buttons.fire.held)
    send(b(72,"fire"),p(9,x+20,y+10),p(41,l.stick.x+30,l.stick.y+45))
    near(i.look_x,20);near(i.look_y,10);assert(i.move_z<0 and i.move_x>0)
    send(b(72,"fire","up"))
    assert(not i.buttons.fire.held and s.move_id==41 and s.look_id==9)
end)

test("touches outside visible controls stay ignored even when dragged onto controls",function()
    for _,size in ipairs({{960,640},{844,390},{390,844},{2400,1080}}) do
        local s,i,l,p,b,send=fixture(size[1],size[2],{inset_left=30,inset_right=30,inset_bottom=20})
        local starts={{l.width*.6,l.height*.5},{l.left+320,l.bottom+202},
            {l.stick.x+l.stick.r+1,l.stick.y},{l.stick.x,l.stick.y+l.stick.r+1}}
        for _,pos in ipairs(starts) do
            send(p(1,pos[1],pos[2],"down"))
            send(p(1,pos[1]+15,pos[2]+10))
            send(b(1,"look"),b(1,"fire"),p(1,l.stick.x,l.stick.y+l.stick.r))
            near(i.move_x,0);near(i.move_z,0);near(i.look_x,0);near(i.look_y,0)
            assert(not i.buttons.fire.held and not i.buttons.fire.pressed)
            assert(not s.move_id and not s.look_id)
            send(p(1,pos[1],pos[2],"up"))
        end
    end
end)

test("LOOK pad turns without firing and keeps its gesture outside the pad",function()
    local s,i,l,p,b,send=fixture()
    local down=b(1,"look","down")
    local x,y=down.x*l.width/960,down.y*l.height/640
    send(down);near(i.look_x,0);near(i.look_y,0)
    send(p(1,x-200,y-100));near(i.look_x,-200);near(i.look_y,-100)
    assert(not i.buttons.fire.held and not i.buttons.fire.pressed)
    send(p(1,x-200,y-100,"up"));input.end_tick(i)
    send(p(1,x-220,y-120));near(i.look_x,0);near(i.look_y,0)
    assert(not s.look_id)
end)

test("fire finger can aim without becoming another button when dragged",function()
    local s,i,l,p,b,send=fixture()
    local down=b(1,"fire","down")
    send(down)
    send(p(1,down.x*l.width/960+25,down.y*l.height/640-12))
    near(i.look_x,25);near(i.look_y,-12)
    send(b(1,"jump"));assert(i.buttons.fire.held and not i.buttons.jump.held)
    send(b(1,"jump","up"));assert(not i.buttons.fire.held)
end)

test("extra fingers cannot steal sticks, look, or prematurely release fire",function()
    local s,i,l,p,b,send=fixture()
    send(p(1,l.stick.x,l.stick.y,"down"),p(2,l.stick.x,l.stick.y,"down"))
    send(p(2,l.stick.x+60,l.stick.y));near(i.move_x,0)
    send(b(3,"fire","down"),b(4,"fire","down"));assert(s.look_id==3)
    send(b(3,"fire","up"));assert(i.buttons.fire.held)
    send(b(4,"fire","up"));assert(not i.buttons.fire.held)
end)

test("aim and mutually exclusive stances toggle once per tap",function()
    local s,i,l,p,b,send=fixture()
    send(b(1,"aim","down"));input.end_tick(i)
    send(b(1,"aim"),b(1,"aim","up"));assert(i.buttons.aim.held and not i.buttons.aim.pressed)
    send(b(2,"crouch","down"),b(2,"crouch","up"));assert(i.buttons.crouch.held)
    send(b(3,"prone","down"),b(3,"prone","up"));assert(i.buttons.prone.held and not i.buttons.crouch.held)
    send(b(4,"aim","down"));assert(not i.buttons.aim.held)
end)

test("short taps retain pressed edges until the next fixed tick",function()
    local s,i,l,p,b,send=fixture()
    for _,name in ipairs({"jump","reload","next_weapon","fire_mode","inspect"}) do
        send(b(1,name,"down"),b(1,name,"up"))
        assert(i.buttons[name].pressed and i.buttons[name].released and not i.buttons[name].held)
    end
    input.end_tick(i)
    assert(not i.buttons.reload.pressed)
end)

test("forward rim sprints and backing off releases sprint",function()
    local s,i,l,p,b,send=fixture()
    send(p(1,l.stick.x,l.stick.y,"down"))
    send(p(1,l.stick.x,l.stick.y+100));assert(i.buttons.sprint.held and i.buttons.sprint.pressed)
    input.end_tick(i)
    send(p(1,l.stick.x,l.stick.y+30));assert(not i.buttons.sprint.held)
    send(p(1,l.stick.x,l.stick.y+100));assert(i.buttons.sprint.pressed)
    send(b(2,"crouch","down"));assert(i.buttons.crouch.pressed and not i.buttons.sprint.held)
end)

test("reset clears ownership and toggles; old holds cannot restart actions",function()
    local s,i,l,p,b,send=fixture()
    send(p(1,l.stick.x,l.stick.y+60,"down"),b(2,"fire","down"),b(3,"aim","down"))
    touch.reset(s,i);input.end_tick(i)
    assert(not i.buttons.fire.held and not i.buttons.aim.held and i.move_z==0)
    send(p(1,l.stick.x,l.stick.y+60),b(2,"fire"),b(3,"aim"))
    assert(not i.buttons.fire.held and not i.buttons.aim.held and i.move_z==0)
    send(b(2,"fire","up"),b(2,"fire","down"));assert(i.buttons.fire.held)
end)

test("touch and desktop holds are independent and reset clears both",function()
    local s,i,l,p,b,send=fixture()
    input.button(i,"fire",{pressed=true})
    send(b(1,"fire","down"),b(1,"fire","up"));assert(i.buttons.fire.held)
    send(b(1,"fire","down"))
    input.button(i,"fire",{released=true});assert(i.buttons.fire.held)
    input.reset(i);assert(not i.buttons.fire.held and next(i.buttons.fire.sources)==nil)
end)

test("loading/death disable combat controls but leave the menu accessible",function()
    local s,i,l,p,b=fixture()
    touch.handle(s,i,{b(1,"fire","down"),b(2,"jump","down")},l,false,1)
    assert(not i.buttons.fire.held and not i.buttons.jump.held)
    assert(touch.handle(s,i,{b(3,"pause","down")},l,false,1)=="pause")
    assert(next(s.fingers)==nil)
end)

test("layout fits safe areas without overlapping controls across phone/tablet aspects",function()
    for _,size in ipairs({{960,640},{844,390},{390,844},{1024,768},{2400,1080}}) do
        local s,i,l,p,b,send=fixture(size[1],size[2],{inset_left=30,inset_right=30,inset_bottom=20,inset_top=10})
        for a,rect in ipairs(l.buttons) do
            assert(rect.x-rect.w/2>=l.left and rect.x+rect.w/2<=l.right)
            assert(rect.y-rect.h/2>=l.bottom and rect.y+rect.h/2<=l.top)
            for c=a+1,#l.buttons do
                local other=l.buttons[c]
                assert(math.abs(rect.x-other.x)>=(rect.w+other.w)/2 or math.abs(rect.y-other.y)>=(rect.h+other.h)/2)
            end
        end
        send(b(5,"fire","down"));assert(i.buttons.fire.held)
        send(b(5,"fire","up"))
        send(p(6,l.stick.x,l.stick.y,"down"),p(6,l.stick.x+20,l.stick.y+20))
        assert(i.move_x>0 and i.move_z<0)
    end
end)

test("analog input reaches player intent and combines with keyboard without speeding diagonals",function()
    local runtime=require "game.runtime"
    local player=require "game.systems.player"
    local ctx=runtime.new()
    ctx.input.move_x,ctx.input.move_z=.25,-.5
    player.fixed_update(ctx,1/120)
    near(ctx.player.intent.move_x,.25);near(ctx.player.intent.move_z,-.5)
    input.button(ctx.input,"right",{pressed=true})
    player.fixed_update(ctx,1/120)
    near(ctx.player.intent.move_x^2+ctx.player.intent.move_z^2,1)
    runtime.set_paused(ctx,true)
    near(ctx.input.move_x,0);near(ctx.input.move_z,0)
    runtime.final(ctx)
end)

test("menu touch uses one finger, clears on pause/focus/resize, and requires fresh presses",function()
    local runtime=require "game.runtime"
    local ui=require "game.ui.controller"
    local controls=require "game.ui.controls"
    local old_window,old_msg,old_hash=window,msg,hash
    local messages,width={},960
    hash=function(value) return value end
    window={get_size=function() return width,640 end,set_mouse_lock=function() end}
    msg={post=function(_,id,data) messages[#messages+1]={id=id,data=data} end}
    local ctx=runtime.new();ctx.world.ready=true
    local self={ctx=ctx,ui=controls.new(),focused=true,touch=touch.new(true),touch_override=-1,
        renderer_settings=require("game.render.settings").defaults()}
    ui.sync_touch(self)
    local l=self.touch_layout
    local point={id=10,x=l.stick.x/l.width*960,y=l.stick.y/l.height*640,pressed=true}
    ui.touch_input(self,{touch={point}});assert(self.touch.move_id==10)
    width=1280;ui.sync_touch(self);assert(not self.touch.move_id)
    point.pressed=false;ui.touch_input(self,{touch={point}});assert(not self.touch.move_id)
    ui.pause(self,true)
    ui.touch_input(self,{touch={{id=1,x=100,y=100,pressed=true},{id=2,x=200,y=200,pressed=true}}})
    assert(self.touch.menu_id==1)
    local presses=0
    for _,m in ipairs(messages) do if m.id=="menu_input" and m.data.id=="fire" and m.data.pressed then presses=presses+1 end end
    assert(presses==1)
    ui.focus(self,false);assert(not self.touch.menu_id and ctx.paused)
    ui.focus(self,true);assert(ctx.paused)
    ui.pause(self,false);assert(not ctx.paused)
    runtime.final(ctx)
    window,msg,hash=old_window,old_msg,old_hash
end)

print(count.." touch tests passed")
