-- Engine-independent touch ownership and layout, shared with the GUI.
-- Coordinates use a uniform virtual scale; Defold action.x/y use 960 x 640.
local input = require "game.input"
local M = {}
local toggles = { aim=true, crouch=true }

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
    local portrait=(width-left-right)<(height-bottom-top)
    local scale=math.max(.01,math.min((width-left-right)/(portrait and 460 or 960),
        (height-bottom-top)/(portrait and 800 or 540)))
    local l,r,b,t=left/scale,(width-right)/scale,bottom/scale,(height-top)/scale
    local layout={width=width/scale,height=height/scale,scale=scale,portrait=portrait,buttons={},
        stick={x=l+110,y=b+(portrait and 220 or 180),r=72},left=l,right=r,bottom=b,top=t}
    -- The whole unobstructed right side is a look surface. Buttons win hit tests.
    layout.look={x=(l+r)*.5+(r-l)*.25,y=(b+t)*.5,w=(r-l)*.5,h=t-b-120}
    local function button(id,label,x,y,w,h)
        layout.buttons[#layout.buttons+1]={id=id,label=label,x=x,y=y,w=w or 94,h=h or 78}
    end
    button("pause","PAUSE",r-66,t-72,100,70)
    if portrait then
        button("fire","FIRE",r-70,b+280,112,104)
        button("aim","AIM",r-70,b+390)
        button("jump","JUMP",r-62,b+170)
        button("crouch","CROUCH",r-164,b+76)
        button("reload","RELOAD",r-268,b+76)
        button("next_weapon","SWAP",r-62,b+76)
    else
        button("fire","FIRE",r-74,b+242,112,104)
        button("aim","AIM",r-190,b+242)
        button("jump","JUMP",r-68,b+138)
        button("crouch","CROUCH",r-174,b+138)
        button("reload","RELOAD",r-280,b+138)
        button("next_weapon","SWAP",r-300,b+242)
    end
    return layout
end

function M.new(enabled)
    return { enabled=enabled, fingers={}, toggled={}, held={}, move_x=0, move_z=0 }
end

function M.reset(state, buffer)
    for name in pairs(state.held) do input.button(buffer,name,{released=true},"touch") end
    input.move(buffer,"touch",0,0)
    state.fingers, state.toggled, state.held = {}, {}, {}
    state.move_id, state.look_id, state.menu_id = nil, nil, nil
    state.move_x, state.move_z, state.sprinting = 0, 0, false
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
    if hit(layout.look,x,y) then return "look" end
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
    -- Hysteresis prevents noisy thumb motion from repeatedly toggling sprint.
    state.sprinting=state.move_z < (state.sprinting and -.72 or -.92) and not held.crouch and not held.aim and not held.fire
    held.sprint=state.sprinting or nil
    for name in pairs(state.held) do
        if not held[name] then input.button(buffer,name,{released=true},"touch") end
    end
    for name in pairs(held) do
        if not state.held[name] then input.button(buffer,name,{pressed=true},"touch") end
    end
    state.held=held
    input.move(buffer,"touch",state.move_x,state.move_z)
end

function M.handle(state,buffer,points,layout,active,sensitivity,invert)
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
            if role=="jump" then state.toggled.crouch=false end
            if role=="look" then
                if state.look_id then role="ignored" else state.look_id=id end
            elseif role=="fire" and not state.look_id then state.look_id=id end
            finger={role=role,x=x,y=y}
            state.fingers[id]=finger
            if toggles[role] then
                state.toggled[role]=not state.toggled[role]
            end
        end
        -- A hold surviving reset/focus/resize cannot acquire a new role.
        if finger then
            if not point.released then
                if state.move_id==id then movement(state,layout,x,y) end
                if state.look_id==id then
                    local speed=(sensitivity or 1)*(state.toggled.aim and .55 or 1)
                    input.look(buffer,(x-finger.x)*speed,(y-finger.y)*speed*(invert and -1 or 1))
                end
                finger.x,finger.y=x,y
            else
                state.fingers[id]=nil
                if state.move_id==id then state.move_id=nil;state.move_x,state.move_z=0,0 end
                if state.look_id==id then
                    state.look_id=nil
                    -- An already-held fire finger takes over smoothly, using its
                    -- last position rather than the departing look finger's origin.
                    for other_id,other in pairs(state.fingers) do
                        if other.role=="fire" or other.role=="look" then state.look_id=other_id;break end
                    end
                end
            end
            -- Preserve short tap edges even if press/release share a batch.
            publish(state,buffer)
        end
    end
end

return M
