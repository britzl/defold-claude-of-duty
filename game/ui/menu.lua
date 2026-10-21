local W = require "game.ui.widgets"
local touch_model=require "game.touch"
local M = {}
local tabs = { "graphics", "audio", "display", "atmosphere", "combat", "photo", "controls" }
local specs = {
    graphics = {{key="mode",label="QUALITY",kind="quality",choices={"auto","low","medium","high","ultra"}}},
    audio = {
        {key="master",label="MASTER",kind="audio",min=0,max=1,step=.05},
        {key="weapons",label="WEAPONS",kind="audio",min=0,max=1,step=.05},
        {key="foley",label="MOVEMENT & IMPACTS",kind="audio",min=0,max=1,step=.05},
        {key="ambience",label="AMBIENCE",kind="audio",min=0,max=1,step=.05},
        {key="muted",label="MUTE ALL AUDIO",kind="audio"},
    },
    display = {
        {key="shadows",label="SUN SHADOWS",kind="renderer"},
        {key="normal_maps",label="SURFACE DETAIL",kind="renderer"},
        {key="local_lights",label="LOCAL LIGHTS",kind="renderer"},
        {key="fog",label="FOG",kind="renderer"},
        {key="bloom",label="BLOOM",kind="renderer"},
        {key="exposure",label="EXPOSURE",kind="renderer",min=.25,max=4,step=.05},
        {key="view",label="RENDER VIEW",kind="renderer",
            choices={"scene","albedo","normals","material","shadow","environment"}},
        {key="reflections",label="SCREEN REFLECTIONS",kind="renderer"},
        {key="glass",label="GLASS",kind="renderer"},
        {key="local_shadows",label="LOCAL SHADOWS",kind="renderer"},
        {key="muzzle_lights",label="MUZZLE LIGHTS",kind="renderer"},
        {key="temporal_aa",label="TEMPORAL ANTIALIASING",kind="renderer"},
        {key="weapon_aa",label="WEAPON ANTIALIASING",kind="renderer"},
    },
    atmosphere = {
        {key="lighting",label="LIGHTING",kind="renderer",choices={"daylight","sunset","night"}},
        {key="hour",label="SOLAR HOUR",kind="renderer",min=0,max=24,step=.25},
        {key="time_rate",label="HOURS PER SECOND",kind="renderer",min=0,max=1,step=.05},
        {key="weather_speed",label="WEATHER SPEED",kind="renderer",min=0,max=10,step=.5},
        {key="clouds",label="CLOUD LAYERS",kind="renderer"},
        {key="cloud_shadows",label="CLOUD SHADOWS",kind="renderer"},
        {key="fog",label="FOG",kind="renderer"},
        {key="volumetric_fog",label="VOLUMETRIC FOG",kind="renderer"},
        {key="fog_shadows",label="SHADOWED LIGHT SHAFTS",kind="renderer"},
    },
    combat = {
        {key="combat_materials",label="WEAPON & SOLDIER DETAIL",kind="renderer"},
        {key="combat_effects",label="SMOKE & MUZZLE FLASHES",kind="renderer"},
        {key="soft_particles",label="SOFT PARTICLE INTERSECTIONS",kind="renderer"},
        {key="impact_decals",label="IMPACT MARKS",kind="renderer"},
    },
    photo = {
        {key="photographic_quality",label="PHOTO QUALITY",kind="renderer",choices={"low","medium","high"}},
        {key="auto_exposure",label="ADAPT EXPOSURE",kind="renderer"},
        {key="bloom_strength",label="BLOOM STRENGTH",kind="renderer",min=0,max=.5,step=.02},
        {key="grade_strength",label="COLOUR GRADE",kind="renderer",min=0,max=1,step=.05},
        {key="sharpen",label="SHARPENING",kind="renderer",min=0,max=.5,step=.05},
        {key="motion_blur",label="MOTION BLUR",kind="renderer",min=0,max=1,step=.05},
        {key="ads_dof",label="ADS DEPTH OF FIELD",kind="renderer",min=0,max=1,step=.05},
        {key="vignette",label="VIGNETTE",kind="renderer",min=0,max=.5,step=.05},
        {key="grain",label="FILM GRAIN",kind="renderer",min=0,max=.03,step=.01},
    },
    controls = {
        {key="sensitivity",label="MOUSE SENSITIVITY",kind="input",min=.25,max=3,step=.05},
        {key="touch_sensitivity",label="TOUCH SENSITIVITY",kind="input",min=.25,max=3,step=.05},
        {key="gamepad_sensitivity",label="GAMEPAD SENSITIVITY",kind="input",min=.25,max=3,step=.05},
        {key="fov",label="FIELD OF VIEW",kind="input",min=55,max=100,step=1},
        {key="invert_look",label="INVERT VERTICAL LOOK",kind="input"},
    },
}
local function add(state,node)
    state.nodes[#state.nodes+1]=node
    return node
end
local function text(state,id,x,y,value,scale,colour,pivot)
    return add(state,W.text(id,x,y,value,scale,colour,pivot,"menu"))
end
local function box(state,id,x,y,w,h,colour)
    return add(state,W.box(id,x,y,w,h,colour,"menu"))
end
local function button(state,id,x,y,w,label)
    local height=state.settings.touch_controls and ((id=="resume" or id=="restart") and 72 or 52) or 36
    local item={id=id,node=box(state,id,x,y,w,height,W.row)}
    item.label=text(state,id.."_label",x,y,label,1,W.white)
    state.items[#state.items+1]=item
    return item
end
local function read(state,spec)
    if spec.kind=="quality" then return state.settings.quality[spec.key] end
    if spec.kind=="input" then return state.settings.input[spec.key] end
    return state.settings[spec.kind=="audio" and "audio" or "renderer"][spec.key]
end
local function highlight(state)
    for i,item in ipairs(state.items) do
        gui.set_color(item.node, i==state.focus and W.selected or i==state.hover and W.hover or W.row)
        if item.tab then gui.set_color(item.label,item.tab==state.tab and W.accent or W.muted) end
    end
end
local function refresh(state)
    for _,item in ipairs(state.items) do
        local spec=item.spec
        if spec then
            local value=read(state,spec)
            if spec.min then
                local t=(value-spec.min)/(spec.max-spec.min)
                gui.set_size(item.fill,vmath.vector3(math.max(.01,t*(item.track_width or 220)),3,0))
                local kx,ky=(item.track_left or 505)+t*(item.track_width or 220),item.y
                if state.touch_layout then kx,ky=kx*960/state.touch_layout.width,ky*640/state.touch_layout.height end
                gui.set_position(item.knob,vmath.vector3(kx,ky,0))
                gui.set_text(item.value,spec.key=="fov" and string.format("%d",value) or spec.kind=="audio" and string.format("%d%%",math.floor(value*100+.5)) or string.format("%.2fx",value))
            else
                gui.set_text(item.value,spec.choices and string.upper(value) or value and "ON" or "OFF")
                gui.set_color(item.value,value==false and W.muted or W.accent)
            end
        end
    end
    if state.tab=="graphics" and not state.touch_layout then
        local q=state.settings.quality
        gui.set_text(gui.get_node("quality_active"),q.mode=="custom" and "CUSTOM SETTINGS" or "ACTIVE: "..string.upper(q.active).."  /  TARGET: "..q.target_fps.." FPS")
    end
    highlight(state)
end
local function touch_layout(state)
    local width,height=window.get_size()
    local safe=window.get_safe_area and window.get_safe_area() or {}
    local layout=touch_model.layout(width,height,safe)
    -- A compact centred sheet with large rows. Portrait keeps physical text size.
    local cx,cy=(layout.left+layout.right)/2,(layout.bottom+layout.top)/2
    state.touch_layout=layout
    state.touch_key=width..":"..height..":"..layout.left..":"..layout.bottom..":"..layout.right..":"..layout.top
    local w=math.min(layout.right-layout.left-24,760)
    local h=math.min(layout.top-layout.bottom-24,520)
    state.touch_origin={x=cx-w/2,y=cy-h/2,w=w,h=h}
    return state.touch_origin
end
local touch_tabs={"controls","audio","display"}
local function rebuild_touch(state)
    local o=touch_layout(state)
    local x,y,w,h=o.x,o.y,o.w,o.h
    local cx=x+w/2
    state.tab=state.tab=="audio" and "audio" or state.tab=="display" and "display" or "controls"
    box(state,"pause_panel",cx,y+h/2,w,h,W.panel)
    text(state,"pause_title",x+18,y+h-30,"PAUSED",1.35,W.white,gui.PIVOT_W)
    text(state,"pause_subtitle",x+18,y+h-57,"",.7,W.muted,gui.PIVOT_W)
    for i,tab in ipairs(touch_tabs) do
        local item=button(state,"tab_"..tab,x+(i-.5)*w/3,y+h-103,w/3-12,string.upper(tab))
        item.tab=tab
    end
    local rows={}
    if state.tab=="controls" then
        rows={specs.controls[2],specs.controls[4],specs.controls[5]}
    elseif state.tab=="audio" then rows={specs.audio[1],specs.audio[4],specs.audio[5]}
    else rows={specs.graphics[1],specs.display[1],specs.display[4]} end
    for i,spec in ipairs(rows) do
        local ry=y+h-175-(i-1)*84
        local item={id="setting_"..spec.key,spec=spec,y=ry-17,
            node=box(state,"setting_"..spec.key,cx,ry,w-28,76,W.row)}
        text(state,nil,x+24,ry+15,spec.label,.88,W.white,gui.PIVOT_W)
        item.value=text(state,"value_"..spec.key,x+w-24,ry+15,"",.9,W.accent,gui.PIVOT_E)
        if spec.min then
            item.track_left=x+30;item.track_width=w-60
            item.track=box(state,"slider_"..spec.key,cx,ry-17,w-52,42,vmath.vector4(0,0,0,0))
            box(state,nil,cx,ry-17,item.track_width,4,W.muted)
            item.fill=box(state,nil,item.track_left,ry-17,1,4,W.accent);gui.set_pivot(item.fill,gui.PIVOT_W)
            item.knob=box(state,nil,item.track_left,ry-17,12,25,W.accent)
        end
        state.items[#state.items+1]=item
    end
    if state.tab=="controls" then
        button(state,"defaults",cx,y+102,w-28,"RESET CONTROLS")
    elseif state.tab=="display" then
        button(state,"quality_defaults",cx,y+102,w-28,"DEFAULTS: AUTO QUALITY")
    else
        text(state,nil,cx,y+100,state.tab=="audio" and "MASTER / AMBIENCE / MUTE" or "MORE DISPLAY OPTIONS ON DESKTOP",.68,W.muted)
    end
    button(state,"resume",x+w*.25,y+40,w/2-20,"RESUME")
    button(state,"restart",x+w*.75,y+40,w/2-20,"RESTART")
    for _,node in ipairs(state.nodes) do
        if node~=state.overlay then
            local pos,size,scale=gui.get_position(node),gui.get_size(node),gui.get_scale(node)
            gui.set_adjust_mode(node,gui.ADJUST_STRETCH)
            gui.set_position(node,vmath.vector3(pos.x*960/state.touch_layout.width,pos.y*640/state.touch_layout.height,0))
            -- Scale the whole node, including its text, uniformly in physical pixels.
            gui.set_scale(node,vmath.vector3(scale.x*960/state.touch_layout.width,scale.y*640/state.touch_layout.height,1))
        end
        gui.set_enabled(node,state.open)
    end
end
local function rebuild(state)
    for _,node in ipairs(state.nodes) do gui.delete_node(node) end
    state.nodes,state.items,state.drag,state.hover={}, {}, nil, nil
    state.overlay=add(state,W.box("pause_overlay",480,320,960,640,vmath.vector4(.01,.02,.03,.74),"overlay"))
    gui.set_adjust_mode(state.overlay,gui.ADJUST_STRETCH)
    if state.settings.touch_controls then
        rebuild_touch(state)
        state.focus=math.min(state.focus or 1,#state.items)
        refresh(state)
        return
    end
    state.touch_layout=nil
    box(state,"pause_panel",480,320,756,576,W.panel)
    box(state,nil,480,607,756,2,W.accent)
    text(state,"pause_title",140,567,"PAUSED",1.8,W.white,gui.PIVOT_W)
    text(state,"pause_subtitle",140,535,"MARKET STREET  /  ENCOUNTER ON HOLD",.85,W.muted,gui.PIVOT_W)
    button(state,"resume",300,91,318,"RESUME")
    button(state,"restart",660,91,318,"RESTART ENCOUNTER")
    for i,tab in ipairs(tabs) do
        local item=button(state,"tab_"..tab,140+(i-.5)*680/#tabs,489,680/#tabs-10,string.upper(tab))
        item.tab=tab
    end
    for i,spec in ipairs(specs[state.tab]) do
        local y=435-(i-1)*((state.tab=="display" or state.tab=="photo") and 25 or 42)
        local item={id="setting_"..spec.key,spec=spec,y=y,
            node=box(state,"setting_"..spec.key,480,y,678,(state.tab=="display" or state.tab=="photo") and 25 or 36,W.row)}
        text(state,nil,157,y,spec.label,.92,W.white,gui.PIVOT_W)
        item.value=text(state,"value_"..spec.key,802,y,"",.9,W.accent,gui.PIVOT_E)
        if spec.min then
            item.track=box(state,"slider_"..spec.key,615,y,240,30,vmath.vector4(0,0,0,0))
            box(state,nil,615,y,220,3,W.muted)
            item.fill=box(state,nil,505,y,1,3,W.accent)
            gui.set_pivot(item.fill,gui.PIVOT_W)
            item.knob=box(state,nil,505,y,6,17,W.accent)
        end
        state.items[#state.items+1]=item
    end
    if state.tab=="graphics" then
        text(state,"quality_active",157,385,"",.92,W.accent,gui.PIVOT_W)
        text(state,nil,157,342,"AUTO ADJUSTS QUALITY TO KEEP PLAY SMOOTH.",.78,W.muted,gui.PIVOT_W)
        button(state,"quality_defaults",480,275,420,"DEFAULTS: AUTO QUALITY")
    end
    if state.tab=="controls" then
        button(state,"defaults",650,213,300,"RESET CONTROLS")
        local lines={"WASD / ARROWS MOVE | SHIFT SPRINT | C / CTRL CROUCH | Z PRONE",
            "SPACE JUMP | MOUSE FIRE / AIM | R RELOAD | 1-3 / WHEEL WEAPONS",
            "PAD: STICKS MOVE / LOOK | RT FIRE | LT AIM | A JUMP | B CROUCH",
            "X RELOAD | Y SWAP | L3 SPRINT | R3 PRONE | START MENU"}
        for i,line in ipairs(lines) do text(state,nil,157,178-(i-1)*21,line,.65,W.muted,gui.PIVOT_W) end
    end
    text(state,"menu_help",480,49,state.settings.touch_controls and "TAP TO SELECT   /   DRAG SLIDERS TO ADJUST   /   TAP RESUME TO PLAY"
        or "TAB / UP / DOWN   SELECT     LEFT / RIGHT   ADJUST     ENTER   ACTIVATE     ESC   RESUME",.7,W.muted)
    state.focus=math.min(state.focus or 1,#state.items)
    for _,node in ipairs(state.nodes) do gui.set_enabled(node,state.open) end
    refresh(state)
end
function M.new()
    return { nodes={},items={},tab="graphics",focus=1,open=false }
end
function M.state(state,settings)
    local changed=state.open~=settings.paused
    local changed_controls=state.settings and state.settings.touch_controls~=settings.touch_controls
    state.settings,state.open=settings,settings.paused
    if #state.nodes==0 or changed_controls then rebuild(state) end
    if changed then
        state.focus,state.drag,state.hover=1,nil,nil
        for i,item in ipairs(state.items) do if item.id=="resume" then state.focus=i;break end end
        for _,node in ipairs(state.nodes) do gui.set_enabled(node,state.open) end
    end
    if not settings.focused then state.drag,state.hover=nil,nil end
    gui.set_text(gui.get_node("pause_subtitle"),settings.focused and "MARKET STREET  /  ENCOUNTER ON HOLD" or "WINDOW INACTIVE  /  ENCOUNTER ON HOLD")
    refresh(state)
end
local function change(state,item,delta,absolute)
    local spec=item.spec
    local value=read(state,spec)
    if spec.min then
        value=absolute or value+delta*spec.step
        value=math.max(spec.min,math.min(spec.max,math.floor(value*100+.5)/100))
    elseif spec.choices then
        local index=1
        for i,choice in ipairs(spec.choices) do if choice==value then index=i end end
        value=spec.choices[(index-1+delta)%#spec.choices+1]
    else value=not value end
    -- Fast repeats should not need to wait for message dispatch.
    if spec.kind=="quality" then state.settings.quality[spec.key]=value
    elseif spec.kind=="input" then state.settings.input[spec.key]=value;state.settings.sensitivity=state.settings.input.sensitivity
    else state.settings[spec.kind=="audio" and "audio" or "renderer"][spec.key]=value end
    msg.post("/controller#script","ui_action",{action="setting",kind=spec.kind,key=spec.key,value=value})
    refresh(state)
end
local function activate(state,item,delta)
    if item.tab then state.tab=item.tab;rebuild(state)
    elseif item.spec then change(state,item,delta or 1)
    else msg.post("/controller#script","ui_action",{action=item.id}) end
end
local function slider(state,item,action)
    local px
    if state.touch_layout then px=action.x*state.touch_layout.width/960
    else px=gui.screen_to_local(item.track,vmath.vector3(action.screen_x,action.screen_y,0)).x end
    local t=math.max(0,math.min(1,(px-(item.track_left or 505))/(item.track_width or 220)))
    change(state,item,0,item.spec.min+t*(item.spec.max-item.spec.min))
end
function M.update(state)
    if not state.settings or not state.settings.touch_controls then return end
    local old=state.touch_key
    touch_layout(state)
    if state.touch_key~=old then rebuild(state) end
end
function M.input(state,action)
    if not state.open or not state.settings.focused then return end
    local id=action.id
    if id==hash("fire") then
        if action.released then state.drag=nil end
        if action.pressed then
            for i,item in ipairs(state.items) do
                if gui.pick_node(item.node,action.x,action.y) then
                    state.focus=i
                    if item.spec and item.spec.min then
                        if gui.pick_node(item.track,action.x,action.y) then state.drag=item;slider(state,item,action) end
                    else activate(state,item) end
                    break
                end
            end
        end
    elseif id==hash("pointer") then
        if state.drag then slider(state,state.drag,action)
        elseif action.dx~=0 or action.dy~=0 then
            state.hover=nil
            for i,item in ipairs(state.items) do
                if gui.pick_node(item.node,action.x,action.y) then state.hover=i;break end
            end
        end
    elseif action.pressed or action.repeated then
        state.hover=nil
        if id==hash("next_weapon") or id==hash("ui_down") then state.focus=state.focus%#state.items+1
        elseif id==hash("ui_up") then state.focus=(state.focus-2)%#state.items+1
        elseif id==hash("ui_confirm") then activate(state,state.items[state.focus])
        elseif id==hash("ui_left") or id==hash("ui_right") then
            local item=state.items[state.focus]
            local delta=id==hash("ui_left") and -1 or 1
            if item.spec then change(state,item,delta)
            elseif item.tab then
                local available=state.touch_layout and touch_tabs or tabs
                for i,tab in ipairs(available) do
                    if item.tab==tab then
                        state.tab=available[(i-1+delta)%#available+1]
                        state.focus=(i-1+delta)%#available+(state.touch_layout and 1 or 3)
                        rebuild(state);break
                    end
                end
            end
        end
    end
    highlight(state)
end
return M
