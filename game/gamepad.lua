-- Standard mapped gamepads. Rate-based look runs on simulation ticks, not events.
local input=require "game.input"
local controls=require "game.ui.controls"
local M={}
M.names={"connected","disconnected","move_left","move_right","move_up","move_down",
    "look_left","look_right","look_up","look_down","fire","aim","jump","crouch","prone",
    "reload","next_weapon","previous_weapon","sprint","lean_left","lean_right","inspect","fire_mode","pause"}
local menu={move_up="ui_up",move_down="ui_down",move_left="ui_left",move_right="ui_right",
    inspect="ui_up",fire_mode="ui_down",previous_weapon="ui_left",next_weapon="ui_right",jump="ui_confirm",crouch="cancel"}
function M.new() return {raw={},blocked={},controls=controls.new(),sprint=false} end
function M.reset(s,buffer)
    input.release_source(buffer,"gamepad")
    for name,value in pairs(s.raw) do if value>.15 then s.blocked[name]=true end end
    s.controls.stance,s.sprint="stand",false
    s.menu_name,s.menu_time=nil,0
end
local function radial(x,y)
    local length=math.sqrt(x*x+y*y)
    if length<=.18 then return 0,0 end
    local strength=math.min(1,(length-.18)/.82)
    return x/length*strength,y/length*strength
end
local function value(s,name) return not s.blocked[name] and (s.raw[name] or 0) or 0 end
function M.handle(s,buffer,name,action,active,paused)
    local id=action.gamepad or 0
    if name=="connected" then return nil end
    if name=="disconnected" then
        if s.index==id then M.reset(s,buffer);s.index=nil;s.raw={};s.blocked={};return "disconnect" end
        return nil
    end
    local v=math.abs(action.value or (action.released and 0 or 1))
    if s.index==nil and (v>.2 or action.pressed) then s.index=id end
    if s.index~=id then return nil end
    local physical=name
    local old=s.raw[physical] or 0
    s.raw[name]=v
    if v<=.15 then s.blocked[name]=nil end
    local press=v>.25 and old<=.25
    local release=v<=.15 and old>.15
    if s.blocked[name] then return nil end
    name=name=="pause_back" and "pause" or name=="next_weapon_dpad" and "next_weapon" or name
    if name=="pause" and press then return "pause" end
    if paused then
        if menu[name] and press then s.menu_name=menu[name];s.menu_time=.4;return menu[name] end
        if menu[name] and release and s.menu_name==menu[name] then s.menu_name=nil end
        return nil
    end
    if not active then if v>.15 then s.blocked[name]=true end;return nil end
    if name=="sprint" then
        if press then s.sprint=not s.sprint end
        controls.button(s.controls,buffer,name,{pressed=s.sprint,released=not s.sprint},"gamepad")
    elseif buffer.buttons[name] then
        controls.button(s.controls,buffer,name,{pressed=press,released=release},"gamepad")
    end
end
function M.fixed_update(s,buffer,dt,settings,active)
    if not active then return end
    local x,z=radial(value(s,"move_right")-value(s,"move_left"),value(s,"move_down")-value(s,"move_up"))
    input.move(buffer,"gamepad",x,z)
    if z>-.25 and s.sprint then s.sprint=false;input.button(buffer,"sprint",{released=true},"gamepad") end
    local lx,ly=radial(value(s,"look_right")-value(s,"look_left"),value(s,"look_up")-value(s,"look_down"))
    -- Quadratic response retains fine aim near centre; ADS slows the maximum rate.
    local speed=1100*(settings.gamepad_sensitivity or 1)*(buffer.buttons.aim.held and .48 or 1)*dt
    input.look(buffer,lx*math.abs(lx)*speed,ly*math.abs(ly)*speed*(settings.invert_look and -1 or 1))
end
function M.menu_update(s,dt)
    if not s.menu_name or s.menu_name=="ui_confirm" or s.menu_name=="cancel" then return end
    s.menu_time=s.menu_time-dt
    if s.menu_time<=0 then s.menu_time=.13;return s.menu_name end
end
return M
