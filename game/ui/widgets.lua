local M = {}
M.white = vmath.vector4(.91,.95,.96,1)
M.muted = vmath.vector4(.59,.69,.72,1)
M.accent = vmath.vector4(.42,.88,.78,1)
M.red = vmath.vector4(1,.28,.22,1)
M.panel = vmath.vector4(.025,.047,.06,.94)
M.row = vmath.vector4(.08,.12,.14,.96)
M.selected = vmath.vector4(.13,.24,.26,1)
M.hover = vmath.vector4(.10,.17,.19,1)
local function setup(node, id, colour, layer, anchor)
    if id then gui.set_id(node,id) end
    gui.set_color(node,colour or M.white)
    gui.set_layer(node,layer or "hud")
    if anchor then
        gui.set_parent(node,anchor.root,false)
        local p=gui.get_position(node)
        gui.set_position(node,vmath.vector3(p.x-anchor.x,p.y-anchor.y,p.z))
        gui.set_inherit_alpha(node,false)
    end
    return node
end
function M.group(anchor,x,y)
    local node=gui.new_box_node(vmath.vector3(x,y,0),vmath.vector3(960,640,0))
    gui.set_color(node,vmath.vector4(0,0,0,0))
    gui.set_xanchor(node,anchor[1])
    gui.set_yanchor(node,anchor[2])
    anchor.root,anchor.x,anchor.y=node,x,y
end
function M.position(node,x,y,anchor)
    gui.set_position(node,vmath.vector3(x-anchor.x,y-anchor.y,0))
end
function M.box(id,x,y,w,h,colour,layer,anchor)
    return setup(gui.new_box_node(vmath.vector3(x,y,0),vmath.vector3(w,h,0)),id,colour,layer,anchor)
end
function M.text(id,x,y,value,scale,colour,pivot,layer,anchor)
    local node=gui.new_text_node(vmath.vector3(x,y,0),value)
    gui.set_font(node,"default")
    gui.set_scale(node,vmath.vector3(scale or 1,scale or 1,1))
    gui.set_pivot(node,pivot or gui.PIVOT_CENTER)
    gui.set_shadow(node,vmath.vector4(0,0,0,.6))
    return setup(node,id,colour,layer,anchor)
end
return M
