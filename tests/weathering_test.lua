local mesh=require "game.world.mesh"
local atlas=require "game.render.surface_atlas"
local materials=require "game.world.materials"
local settings=require "game.render.settings"
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function box(id)
    return {id=id,material="plaster_sand",x=3,y=2,z=-5,w=4,h=4,d=.2}
end
test("clipping a face keeps distances to real edges, not the artificial cut",function()
    local b=mesh.new("test","plaster_sand",0,0)
    local visible={{},{},{},{},{{2,1,4,3}}, {}}
    mesh.box(b,box("wall"),1,visible)
    assert(b.vertex_count==6)
    for i=1,b.vertex_count do
        local p,e=(i-1)*3,(i-1)*4
        assert(math.abs(b.edges[e+1]-(b.positions[p+1]-1))<1e-6)
        assert(math.abs(b.edges[e+2]-(5-b.positions[p+1]))<1e-6)
        assert(b.edges[e+1]>=1 and b.edges[e+2]>=1,"Visibility cut became a worn edge")
        assert(b.edges[e+3]>=1 and b.edges[e+4]>=1)
    end
end)
test("world ground chunks never grow artificial wear or contact seams",function()
    for _,id in ipairs({"road/1","walk/1","ground/west/1"}) do
        local b=mesh.new(id,"plaster_sand",0,0);mesh.box(b,box(id),1)
        for _,value in ipairs(b.masks) do assert(value==0) end
    end
end)
test("authored wear grime and occlusion masks survive all vertices and rotations",function()
    local s=box("ledge");s.rotation_x=.35;s.weather_masks={.8,.3,.2,.6}
    local b=mesh.new("test","plaster_sand",0,0);mesh.box(b,s,1)
    for i=1,b.vertex_count*4 do
        if i%4~=0 then assert(math.abs(b.masks[i]-s.weather_masks[(i-1)%4+1])<1e-7) end
        assert(b.edges[i]>=-1e-6 and b.edges[i]<=4.000001)
    end
end)
test("all fifteen surface families have production mappings and distinct recipes",function()
    local found={}
    for _,material in pairs(materials) do
        assert(atlas.surfaces[material.kind+1]);found[material.kind]=true
    end
    for kind=0,14 do assert(found[kind],"Missing material family "..kind) end
    assert(materials.dirt.kind~=materials.asphalt.kind)
    assert(materials.concrete.kind~=materials.concrete_floor.kind)
end)
test("quality presets reduce storage without changing physical scale or stable IDs",function()
    local previous=0
    for _,quality in ipairs({"low","medium","high"}) do
        local a=atlas.new(quality)
        local bytes=a.width*a.height*12
        assert(bytes>previous);previous=bytes
        for i,s in ipairs(a.surfaces) do
            assert(s.name==atlas.surfaces[i].name and s.metres==atlas.surfaces[i].metres)
            assert(s.relief==atlas.surfaces[i].relief and s.parallax==atlas.surfaces[i].parallax)
        end
    end
    assert(not pcall(atlas.new,"invalid"))
    for _,feature in ipairs({"weathering","micro_detail","parallax"}) do
        local defaults=settings.defaults()
        assert(settings.configure(defaults,{[feature]=false})[feature]==false and defaults[feature])
    end
end)
print(count.." weathering tests passed")
