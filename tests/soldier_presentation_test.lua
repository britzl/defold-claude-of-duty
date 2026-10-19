-- Verify the adapter's current/previous shader data across recycled buffers.
package.path="./?.lua;"..package.path
local rig=require "game.ai.rig"
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
end
hash=function(value) return value end
vmath={}
function vmath.vector3(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
function vmath.quat_rotation_y(yaw) return {yaw=yaw} end
function vmath.matrix4()
    local m={}
    for r=0,3 do for c=0,3 do m["m"..r..c]=r==c and 1 or 0 end end
    return m
end
function vmath.matrix4_rotation_y(yaw)
    local m=vmath.matrix4()
    m.m00,m.m02,m.m20,m.m22=math.cos(yaw),math.sin(yaw),-math.sin(yaw),math.cos(yaw)
    return m
end
local properties={}
go={set_position=function() end,set_rotation=function() end}
function go.set(url,property,value)
    properties[url]=properties[url] or {}
    -- Defold copies the values on assignment, rather than retaining Lua data.
    properties[url][property]=copy(value)
end
local adapter=require "game.ai.defold"
local a=adapter.new({}, {}, nil, nil, nil)
local function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." != "..tostring(b)) end
local function check_palette(actual,expected)
    assert(#actual==rig.count)
    for i,t in ipairs(expected) do
        local m=actual[i]
        for r=0,2 do for c=0,3 do near(m["m"..r..c],t[r*4+c+1]) end end
        near(m.m30,0);near(m.m31,0);near(m.m32,0);near(m.m33,1)
    end
end
local previous,scratch={},{}
-- Two unrelated actors, enough frames to reuse both palette buffers, plus a
-- stationary frame to ensure motion history settles before movement resumes.
for frame=1,7 do for actor=1,2 do
    local id="actor_"..actor
    if not a.instances[id] then a.instances[id]={mesh=id,url=id.."/mesh",prepass=id.."/prepass"} end
    local t=frame==4 and 3 or frame
    scratch[id]=scratch[id] or {}
    local palette=rig.pose({variant=actor==1 and "irregular" or "breacher",time=t,phase=t*.37,
        walk=1,run=.7,aim=actor-1,crouch=t/10,death=actor==2 and t/10 or 0,
        reload=t/10,reload_weight=1,hit=.3,hit_region="arm",hit_side=-1,
        feet={R={target={x=.103,y=.18,z=.12},normal={x=.1,y=.99,z=0},weight=1},
            L={target={x=-.103,y=.088,z=-.2},normal={x=0,y=1,z=0},weight=1}}},scratch[id])
    local position={x=t*actor,y=actor,z=-t}
    local yaw=t*.13
    local world=vmath.matrix4_rotation_y(yaw)
    world.m03,world.m13,world.m23=position.x,position.y,position.z
    adapter.present(a,{id=id},palette,position,yaw)
    local colour,depth=properties[id.."/mesh"],properties[id.."/prepass"]
    check_palette(colour.bone_palette,palette)
    check_palette(depth.bone_palette,palette)
    check_palette(depth.previous_bones,previous[id] and previous[id].palette or palette)
    for k,v in pairs(previous[id] and previous[id].world or world) do near(depth.previous_world[k],v) end
    previous[id]={palette=copy(palette),world=world}
end end
print("PASS complete current/previous bone and world transforms across first, moving, stationary and recycled frames for two soldiers")
