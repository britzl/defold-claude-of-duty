-- Engine-only checks: native numeric parity and buffer ownership on macOS/Wasm.
local mesh=require "game.world.mesh"
local materials=require "game.world.materials"
local faces=require "game.world.visible_faces"
local glass=require "game.render.glass"
local M={}
local function equal_buffer(a,b,names)
    for _,name in ipairs(names) do assert(buffer.get_bytes(a,hash(name))==buffer.get_bytes(b,hash(name)),name.." differs") end
end
function M.run()
    assert(worldmesh,"Native mesh tests require the extension")
    local registry={}
    local shapes={
        {id="plain",x=0,y=0,z=0,w=2,h=2,d=2},
        {id="clipped",x=2,y=.5,z=0,w=2,h=1,d=1},
        {id="rotated",x=-.1,y=2,z=-3,w=1,h=2,d=3,rotation_x=.3,rotation_y=-.6,rotation_z=.9},
        {id="road/test",x=10,y=0,z=0,w=7,h=.3,d=7},
        {id="masked",x=20,y=2,z=0,w=1,h=1,d=1,weather_masks={.2,.6,.9,0}},
        {id="card",kind="card",x=30,y=1,z=0,w=2,h=1,d=.01,rotation_y=.3},
    }
    for _,kind in ipairs({"bevel","cylinder","torus","frond","prism"}) do
        shapes[#shapes+1]={id=kind,kind=kind,x=40+#shapes,y=1,z=-2,w=1.2,h=.8,d=1.1,
            bevel=.09,taper=.4,rotation_x=.8,rotation_y=.2,rotation_z=-.3,
            profile={{-.6,-.4},{.6,-.4},{.35,.4},{-.4,.3}}}
    end
    local bounds,visible={},{}
    for i,s in ipairs(shapes) do s.material=s.kind=="frond" and "foliage" or "concrete";bounds[i]=faces.bounds(s) end
    for i in ipairs(shapes) do
        visible[i]=faces.for_box(i,bounds)
        if visible[i] then faces.register_edges(registry,bounds[i],visible[i]) end
    end
    local builder=worldmesh.begin(registry,16,12288)
    for i,s in ipairs(shapes) do
        local reference=mesh.new(s.id,s.material,0,0)
        mesh.shape(reference,s,1.037,visible[i],registry)
        assert(worldmesh.verify(builder,s,materials[s.material],1.037,visible[i],reference))
        assert(worldmesh.append(builder,s,materials[s.material],1.037,visible[i])==reference.vertex_count)
    end
    local batches=worldmesh.finish(builder)
    local buffers={}
    for i,b in ipairs(batches) do buffers[i]=worldmesh.take_buffer(builder,i);assert(#buffer.get_stream(buffers[i],hash("position"))==b.vertex_count*3) end
    assert(not pcall(worldmesh.take_buffer,builder,1),"A buffer may only be taken once")
    assert(not pcall(worldmesh.append,builder,shapes[1],materials.concrete,1),"Finished builders must reject writes")
    worldmesh.close(builder)
    assert(not pcall(worldmesh.finish,builder),"Closed builders must reject access")
    for _,b in ipairs(buffers) do assert(#buffer.get_bytes(b,hash("position"))>0,"Returned buffers outlive the builder") end
    local abandoned=worldmesh.begin({},16,12288)
    worldmesh.append(abandoned,shapes[3],materials.concrete,1)
    worldmesh.close(abandoned);worldmesh.close(abandoned)
    -- Exercise table/array growth and teardown with untaken batches and edge
    -- lines. Defold containers do not construct or destroy owning elements.
    local many_edges={}
    for i=1,80 do many_edges["1/0.0000000/"..string.format("%.7f",i)]={3,1,2} end
    local growing=worldmesh.begin(many_edges,16,36)
    for i=1,80 do
        local s={id="growth/"..i,material="concrete",x=i*20,y=0,z=0,w=1,h=1,d=1}
        assert(worldmesh.append(growing,s,materials.concrete,1)==36)
    end
    local grown=worldmesh.finish(growing)
    assert(#grown==80 and grown[80].boxes==1,"Container growth lost batches")
    local retained=worldmesh.take_buffer(growing,40)
    worldmesh.close(growing)
    assert(#buffer.get_stream(retained,hash("position"))==108)
    local cancelled=worldmesh.begin(many_edges,16,36)
    worldmesh.close(cancelled);worldmesh.close(cancelled)
    assert(not pcall(worldmesh.begin,{invalid={1,"bad"}},16,36))
    collectgarbage("collect") -- Includes the failed begin's owned edge line.
    local pane=glass.pane("test",42,1.4,-.5,2.5,2.6,"z")
    local native=worldmesh.pack(pane)
    local names={"position","normal","color","surface_edges","surface_masks"}
    local arrays={pane.positions,pane.normals,pane.colors,pane.edges,pane.masks}
    local counts={3,3,4,4,4};local declarations={}
    for i,name in ipairs(names) do declarations[i]={name=hash(name),type=buffer.VALUE_TYPE_FLOAT32,count=counts[i]} end
    local reference=buffer.create(pane.vertex_count,declarations)
    local center={pane.centre.x,pane.centre.y,pane.centre.z}
    for i,name in ipairs(names) do
        local stream=buffer.get_stream(reference,hash(name))
        for k,v in ipairs(arrays[i]) do stream[k]=i==1 and v-center[(k-1)%3+1] or v end
    end
    equal_buffer(native,reference,names)
    print("NATIVE_MESH_TEST PASS "..#shapes.." primitives, glass, ownership, container growth and cancellation")
    return #shapes
end
return M
