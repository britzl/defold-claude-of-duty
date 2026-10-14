-- Optional visual fixture. No collision, gameplay registration or RNG consumption.
local mesh=require "game.world.mesh"
local visible=require "game.world.visible_faces"
local M={roughness={.08,.25,.5,.75,1},
    extra_materials={"concrete_floor","brick","tile","dirt","gravel","metal_painted","metal_rust","rubber","glass"},
    batch_count=31}
M.lights={
    {id="lab/key",kind="room",x=40.5,y=2.7,z=-.5,radius=8,intensity=24,
        minimum={x=37,y=0,z=-6},maximum={x=47,y=4,z=6}},
    {id="lab/fill",kind="room",x=52,y=2.7,z=-1,radius=9,intensity=42,colour={1,.75,.5},
        minimum={x=49,y=0,z=-6},maximum={x=59,y=4,z=6}}
}
local function sphere_vertex(batch,centre,radius,lat,lon)
    local n={math.sin(lat)*math.cos(lon),math.cos(lat),math.sin(lat)*math.sin(lon)}
    for axis=1,3 do
        local v=centre[axis]+radius*n[axis]
        batch.positions[#batch.positions+1]=v
        batch.normals[#batch.normals+1]=n[axis]
        batch.colors[#batch.colors+1]=.65
        batch.bounds[axis]=math.min(batch.bounds[axis],v)
        batch.bounds[axis+3]=math.max(batch.bounds[axis+3],v)
    end
    batch.colors[#batch.colors+1]=1
    for _=1,4 do batch.edges[#batch.edges+1]=10;batch.masks[#batch.masks+1]=0 end
    batch.vertex_count=batch.vertex_count+1
end
function M.sphere(batch,centre,radius)
    local rows,columns=16,32
    for y=0,rows-1 do for x=0,columns-1 do
        local a,b=y*math.pi/rows,(y+1)*math.pi/rows
        local c,d=x*2*math.pi/columns,(x+1)*2*math.pi/columns
        if y>0 then
            sphere_vertex(batch,centre,radius,a,c);sphere_vertex(batch,centre,radius,a,d);sphere_vertex(batch,centre,radius,b,c)
        end
        if y<rows-1 then
            sphere_vertex(batch,centre,radius,a,d);sphere_vertex(batch,centre,radius,b,d);sphere_vertex(batch,centre,radius,b,c)
        end
    end end
end
function M.batches()
    local list,by_material,boxes,bounds={},{},{},{}
    local function box(material,x,y,z,w,h,d)
        local batch=by_material[material]
        if not batch then batch=mesh.new(material,material,0,0);by_material[material]=batch;list[#list+1]=batch end
        local shape={material=material,x=x,y=y,z=z,w=w,h=h,d=d}
        boxes[#boxes+1]=shape;bounds[#bounds+1]=visible.bounds(shape)
    end
    box("concrete_floor",3,-.1,0,64,.2,14)
    box("plaster_cream",0,1.8,-5.5,16,3.6,.2)
    box("plaster_cream",-7.5,1.8,-1,.2,3.6,9)
    for i,material in ipairs({"plaster_sand","concrete","asphalt","wood","metal","awning_red"}) do
        box(material,(i-3.5)*2.4,2,-5.32,2.1,2.6,.12)
    end
    for i,material in ipairs(M.extra_materials) do
        box(material,8.4+i*2.4,2,-5.32,2.1,2.6,.12)
    end
    -- Large wall with ledges for metre-scale repairs/runoff and close wear.
    box("plaster_sand",-20,2,-5.5,12,4,.2)
    box("trim",-20,4.05,-5.45,12.2,.1,.4)
    box("wood",5.2,.95,2.5,2.4,.12,1.3)
    for _,x in ipairs({4.2,6.2}) do for _,z in ipairs({2,3}) do box("wood",x,.445,z,.12,.89,.12) end end
    box("wood",-6.6,.55,-3,1.1,1.1,1.1)
    box("wood",-6.6,1.38,-3,.65,.55,.65)
    for metal=0,1 do for i,roughness in ipairs(M.roughness) do
        local batch=mesh.new("sphere/"..metal.."/"..i,"metal",0,0)
        batch.surface={3,1,roughness,metal}
        M.sphere(batch,{(i-3)*2,.6,metal==0 and -2.4 or .2},.6)
        list[#list+1]=batch
    end end
    -- Remote fixture proves shadows follow inspection/teleport cameras outside
    -- the original street map. Reuses existing material batches and bounds.
    box("concrete_floor",160,-.1,0,14,.2,14)
    box("wood",160,1,0,1,2,1)
    box("metal",163,1,-2,.12,2,.12)
    box("concrete_floor",42,-.1,0,10,.2,12)
    box("plaster_cream",42,1.5,-4.5,10,3,.2)
    box("wood",42,.6,-2,1.2,1.2,1.2)
    box("concrete_floor",54,-.1,0,10,.2,12)
    box("plaster_cream",54,1.5,-4.5,10,3,.2)
    box("wood",54,.6,-1.5,1.2,1.2,1.2)
    local mirror=mesh.new("reflection_floor","metal",0,0)
    mirror.surface={3,1,.12,1}
    -- Participate in the same visibility cuts and edge stitching as the box.
    -- A separate intersecting plate caused subpixel depth ties in reflections.
    local plate={material="metal",x=42,y=.01,z=0,w=7,h=.02,d=8,batch=mirror}
    boxes[#boxes+1]=plate;bounds[#bounds+1]=visible.bounds(plate)
    list[#list+1]=mirror
    -- Match production clipping/tessellation at table feet and wall/floor joints.
    -- Subpixel camera jitter exposes otherwise hidden T-junctions here.
    local faces,edges={},{}
    for i=1,#boxes do
        faces[i]=visible.for_box(i,bounds)
        visible.register_edges(edges,bounds[i],faces[i])
    end
    for i,shape in ipairs(boxes) do mesh.box(shape.batch or by_material[shape.material],shape,1,faces[i],edges) end
    -- Perforated overhead panel: colour and shadow must show identical holes.
    local cutout=mesh.new("cutout","metal",0,0)
    mesh.box(cutout,{material="metal",x=2,y=2.2,z=3,w=2.4,h=.02,d=1.8},1)
    for i=4,#cutout.colors,4 do cutout.colors[i]=.45 end
    list[#list+1]=cutout
    for _,pane in ipairs(require("game.render.glass").laboratory()) do list[#list+1]=pane end
    return list
end
function M.create()
    local api=require "game.world.defold"
    local adapter=api.new("#capture_mesh",nil)
    local vertices=0
    for _,batch in ipairs(M.batches()) do vertices=vertices+batch.vertex_count;api.add_batch(adapter,batch) end
    adapter.vertices=vertices
    return adapter
end
function M.final(adapter) adapter.api.final(adapter) end
return M
