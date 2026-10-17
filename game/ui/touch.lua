local model = require "game.touch"
local W = require "game.ui.widgets"
local M = {}
local idle=vmath.vector4(.035,.075,.09,.58)
local active=vmath.vector4(.16,.42,.40,.78)

local function place(node,layout,x,y,w,h)
    -- Compensate for STRETCH on each axis, keeping physical shapes/text square
    -- while positioning controls against the safe edges on any aspect ratio.
    gui.set_adjust_mode(node,gui.ADJUST_STRETCH)
    gui.set_position(node,vmath.vector3(x*960/layout.width,y*640/layout.height,0))
    if w then gui.set_size(node,vmath.vector3(w*960/layout.width,h*640/layout.height,0))
    else gui.set_scale(node,vmath.vector3(.82*960/layout.width,.82*640/layout.height,1)) end
end

local function circle(id,size,colour)
    local node=gui.new_pie_node(vmath.vector3(),vmath.vector3(size,size,0))
    gui.set_id(node,id)
    gui.set_color(node,colour)
    gui.set_layer(node,"touch")
    gui.set_perimeter_vertices(node,48)
    return node
end

function M.new()
    return { buttons={} }
end

function M.update(state,data)
    if not data.enabled then
        if state.base then
            for _,node in ipairs({state.base,state.knob,state.hint}) do gui.set_enabled(node,false) end
        end
        for _,item in pairs(state.buttons) do gui.set_enabled(item.box,false);gui.set_enabled(item.text,false) end
        return
    end
    local width,height=window.get_size()
    local safe=window.get_safe_area and window.get_safe_area() or {}
    local layout=model.layout(width,height,safe)
    if not state.base then
        state.base=circle("touch_move",152,idle)
        state.knob=circle("touch_stick",54,W.accent)
        state.hint=W.text("touch_move_hint",0,0,"MOVE / PUSH TO SPRINT",.82,W.white,nil,"touch")
    end
    local stick=layout.stick
    place(state.base,layout,stick.x,stick.y,stick.r*2,stick.r*2)
    place(state.knob,layout,stick.x+data.move_x*stick.r,stick.y-data.move_z*stick.r,54,54)
    place(state.hint,layout,stick.x,stick.y-stick.r-22)
    for _,node in ipairs({state.base,state.knob,state.hint}) do gui.set_enabled(node,data.active) end
    for _,button in ipairs(layout.buttons) do
        local item=state.buttons[button.id]
        if not item then
            item={box=W.box("touch_"..button.id,0,0,1,1,idle,"touch"),
                text=W.text(nil,0,0,button.label,.82,W.white,nil,"touch")}
            state.buttons[button.id]=item
        end
        local visible=data.enabled and data.focused and not data.paused and (data.active or button.id=="pause")
        gui.set_enabled(item.box,visible);gui.set_enabled(item.text,visible)
        gui.set_color(item.box,data.held[button.id] and active or idle)
        gui.set_color(item.text,data.held[button.id] and W.accent or W.white)
        place(item.box,layout,button.x,button.y,button.w,button.h)
        place(item.text,layout,button.x,button.y)
    end
end

return M
