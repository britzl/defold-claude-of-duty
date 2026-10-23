local M = {}
M.white = vmath.vector4(.93,.94,.91,1)
M.muted = vmath.vector4(.66,.71,.70,1)
M.accent = vmath.vector4(.72,.85,.65,1)
M.red = vmath.vector4(1,.28,.22,1)
M.panel = vmath.vector4(.035,.047,.05,.66)
M.hud_panel = vmath.vector4(.025,.04,.045,.36)
M.row = vmath.vector4(.08,.11,.12,.34)
M.selected = vmath.vector4(.18,.27,.25,.78)
M.hover = vmath.vector4(.14,.21,.20,.62)
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
