-- Optional visual fixture. No collision, gameplay registration or RNG consumption.
local mesh=require "game.world.mesh"
local M={roughness={.08,.25,.5,.75,1}}
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
    local list,by_material={},{}
    local function box(material,x,y,z,w,h,d)
        local batch=by_material[material]
        if not batch then batch=mesh.new(material,material,0,0);by_material[material]=batch;list[#list+1]=batch end
        mesh.box(batch,{material=material,x=x,y=y,z=z,w=w,h=h,d=d},1)
    end
    box("concrete",0,-.1,0,16,.2,14)
    box("plaster_cream",0,1.8,-5.5,16,3.6,.2)
    box("plaster_cream",-7.5,1.8,-1,.2,3.6,9)
    for i,material in ipairs({"plaster_sand","concrete","asphalt","wood","metal","awning_red"}) do
        box(material,(i-3.5)*2.4,2,-5.32,2.1,2.6,.12)
    end
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
