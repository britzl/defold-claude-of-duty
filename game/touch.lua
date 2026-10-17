-- Engine-independent touch ownership and layout, shared with the GUI.
-- Coordinates use a uniform virtual scale; Defold action.x/y use 960 x 640.
local input = require "game.input"
local M = {}
local toggles = { aim=true, crouch=true, prone=true }

function M.default_enabled(system, browser_touch, override)
    if override == 0 then return false end
    return override == 1 or system == "Android" or system == "iPhone OS"
        or (system == "HTML5" and browser_touch) or false
end

function M.layout(width, height, safe)
    width, height = math.max(1,width), math.max(1,height)
    safe = safe or {}
    local left, right = safe.inset_left or 0, safe.inset_right or 0
    local bottom, top = safe.inset_bottom or 0, safe.inset_top or 0
    local scale = math.max(.01,math.min((width-left-right)/960,(height-bottom-top)/540))
    local l, r, b, t = left/scale,(width-right)/scale,bottom/scale,(height-top)/scale
    local layout = { width=width/scale, height=height/scale, buttons={},
        stick={x=l+132,y=b+202,r=76}, left=l, right=r, bottom=b, top=t }
    local function button(id,label,x,y,w,h)
        layout.buttons[#layout.buttons+1]={id=id,label=label,x=x,y=y,w=w or 82,h=h or 60}
    end
    button("pause","MENU",r-66,t-106,92,52)
    button("look","LOOK",r-222,b+390,92,76)
    button("fire","FIRE",r-90,b+298,112,100)
    button("aim","AIM",r-222,b+298,92,76)
    button("jump","JUMP",r-64,b+192)
    button("crouch","CROUCH",r-158,b+192)
    button("reload","RELOAD",r-252,b+192)
    button("prone","PRONE",r-64,b+124)
    button("next_weapon","WEAPON",r-158,b+124)
    button("fire_mode","MODE",r-252,b+124)
    button("lean_left","LEAN <",l+58,b+330)
    button("lean_right","LEAN >",l+152,b+330)
    button("inspect","INSPECT",l+246,b+330)
    return layout
end

function M.new(enabled)
    return { enabled=enabled, fingers={}, toggled={}, held={}, move_x=0, move_z=0 }
end

function M.reset(state, buffer)
    for name in pairs(state.held) do input.button(buffer,name,{released=true},"touch") end
    buffer.move_x, buffer.move_z = 0, 0
    state.fingers, state.toggled, state.held = {}, {}, {}
    state.move_id, state.look_id, state.menu_id = nil, nil, nil
    state.move_x, state.move_z = 0, 0
end

local function hit(rect,x,y)
    return math.abs(x-rect.x)<=rect.w/2 and math.abs(y-rect.y)<=rect.h/2
end

local function target(layout,x,y,active)
    for _,button in ipairs(layout.buttons) do
        if (active or button.id=="pause") and hit(button,x,y) then return button.id end
    end
    if not active then return "ignored" end
    local stick=layout.stick
    if (x-stick.x)^2+(y-stick.y)^2 <= stick.r^2 then return "move" end
    return "ignored"
end

local function movement(state,layout,x,y)
    local s=layout.stick
    local dx,dy=(x-s.x)/s.r,(y-s.y)/s.r
    local length=math.sqrt(dx*dx+dy*dy)
    if length<=.15 then state.move_x,state.move_z=0,0;return end
    local strength=math.min(1,(length-.15)/.85)
    state.move_x,state.move_z=dx/length*strength,-dy/length*strength
end

local function publish(state,buffer)
    local held={}
    for name,value in pairs(state.toggled) do if value then held[name]=true end end
    for _,finger in pairs(state.fingers) do
        if buffer.buttons[finger.role] and not toggles[finger.role] then held[finger.role]=true end
    end
    -- Pushing forward to the rim sprints; crossing it twice also uses the
    -- normal tactical-sprint press timing. Crouching/prone still allow walking.
    held.sprint = state.move_z < -.9 and not held.crouch and not held.prone or nil
    for name in pairs(state.held) do
        if not held[name] then input.button(buffer,name,{released=true},"touch") end
    end
    for name in pairs(held) do
        if not state.held[name] then input.button(buffer,name,{pressed=true},"touch") end
    end
    state.held=held
    buffer.move_x,buffer.move_z=state.move_x,state.move_z
end

function M.handle(state,buffer,points,layout,active,sensitivity)
    for _,point in ipairs(points) do
        local id=point.id
        local x,y=point.x*layout.width/960,point.y*layout.height/640
        local finger=state.fingers[id]
        if point.pressed and not finger then
            local role=target(layout,x,y,active)
            if role=="pause" then M.reset(state,buffer);return "pause" end
            if role=="move" then
                if state.move_id then role="ignored" else state.move_id=id end
            end
            if role=="look" then
                if state.look_id then role="ignored" else state.look_id=id end
            elseif role=="fire" and not state.look_id then state.look_id=id end
            finger={role=role,x=x,y=y}
            state.fingers[id]=finger
            if toggles[role] then
                state.toggled[role]=not state.toggled[role]
                if role=="crouch" then state.toggled.prone=false
                elseif role=="prone" then state.toggled.crouch=false end
            end
        end
        -- A hold surviving reset/focus/resize cannot acquire a new role.
        if finger then
            if not point.released then
                if state.move_id==id then movement(state,layout,x,y) end
                if state.look_id==id then
                    input.look(buffer,(x-finger.x)*(sensitivity or 1),(y-finger.y)*(sensitivity or 1))
                end
                finger.x,finger.y=x,y
            else
                state.fingers[id]=nil
                if state.move_id==id then state.move_id=nil;state.move_x,state.move_z=0,0 end
                if state.look_id==id then state.look_id=nil end
            end
            -- Preserve short tap edges even if press/release share a batch.
            publish(state,buffer)
        end
    end
end

return M
