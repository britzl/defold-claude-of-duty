-- Engine adapter. Generation and metadata remain testable without Defold.
local materials = require "game.world.materials"
local M = {}
local POSITION, NORMAL, COLOR = hash("position"), hash("normal"), hash("color")
local EDGES,MASKS=hash("surface_edges"),hash("surface_masks")
local SURFACES=hash("surface_data")
local atlas=require "game.render.surface_atlas"
local WORLD = { hash("world") }

function M.new(mesh_factory, collision_factory)
    return { api = M, mesh_factory = mesh_factory, collision_factory = collision_factory,
        objects = {}, buffers = {}, collisions = {}, by_id = {} }
end

function M.add_batch(adapter, batch)
    if batch.glass then
        local c=batch.centre
        for i=1,#batch.positions,3 do
            batch.positions[i]=batch.positions[i]-c.x;batch.positions[i+1]=batch.positions[i+1]-c.y;batch.positions[i+2]=batch.positions[i+2]-c.z
        end
        for i,v in ipairs({c.x,c.y,c.z}) do batch.bounds[i]=batch.bounds[i]-v;batch.bounds[i+3]=batch.bounds[i+3]-v end
    end
    local declarations = {
        { name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
        { name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
        { name = COLOR, type = buffer.VALUE_TYPE_FLOAT32, count = 4 },
        { name = EDGES, type = buffer.VALUE_TYPE_FLOAT32, count = 4 },
        { name = MASKS, type = buffer.VALUE_TYPE_FLOAT32, count = 4 },
    }
    if not batch.glass then declarations[#declarations+1]={name=SURFACES,type=buffer.VALUE_TYPE_FLOAT32,count=2} end
    local data = buffer.create(batch.vertex_count, declarations)
    local positions, normals, colors = buffer.get_stream(data, POSITION), buffer.get_stream(data, NORMAL), buffer.get_stream(data, COLOR)
    for i = 1, #batch.positions do positions[i] = batch.positions[i]; normals[i] = batch.normals[i] end
    for i = 1, #batch.colors do colors[i] = batch.colors[i] end
    local edges,masks=buffer.get_stream(data,EDGES),buffer.get_stream(data,MASKS)
    for i=1,batch.vertex_count*4 do edges[i]=batch.edges[i];masks[i]=batch.masks[i] end
    if not batch.glass then
        local surfaces=buffer.get_stream(data,SURFACES)
        local material=materials[batch.material]
        for i=1,batch.vertex_count do
            surfaces[i*2-1]=batch.surfaces and batch.surfaces[i*2-1] or (batch.surface and batch.surface[1] or material.kind)
            surfaces[i*2]=batch.surfaces and batch.surfaces[i*2] or material.weather or 1
        end
    end
    buffer.set_metadata(data, "AABB", batch.bounds, buffer.VALUE_TYPE_FLOAT32)
    local factory_url=batch.glass and (adapter.mesh_factory=="#capture_mesh" and "#capture_glass" or "#glass_mesh") or adapter.mesh_factory
    local id = factory.create(factory_url,batch.glass and vmath.vector3(batch.centre.x,batch.centre.y,batch.centre.z) or nil)
    adapter.objects[#adapter.objects + 1] = id
    local path = resource.create_buffer("/generated/world_" .. hash_to_hex(id) .. ".bufferc", { buffer = data })
    adapter.buffers[#adapter.buffers + 1] = path
    local url = msg.url(nil, id, "mesh")
    go.set(url, "vertices", path)
    local surface=batch.surface or {materials[batch.material].kind,0,0,0}
    if batch.glass then
        go.set(url, "surface", vmath.vector4(surface[1],surface[2],surface[3],surface[4]))
        local s=assert(atlas.surfaces[surface[1]+1])
        go.set(url,"surface_info",vmath.vector4(s.metres,s.size,s.relief,s.last_level))
    elseif batch.surface then
        go.set(url,"surface_override",vmath.vector4(surface[1],surface[2],surface[3],surface[4]))
    end
    batch.object, batch.resource = id, path
    -- The resource owns the buffer now. Keep only bounds/stats in Lua.
    batch.positions, batch.normals, batch.colors, batch.edges, batch.masks = nil, nil, nil, nil, nil
    batch.surfaces=nil
end

function M.add_collision(adapter, shape)
    local id = factory.create(adapter.collision_factory, vmath.vector3(shape.x, shape.y, shape.z), vmath.quat_rotation_x(shape.rotation_x or 0))
    adapter.objects[#adapter.objects + 1] = id
    local url = msg.url(nil, id, "collision")
    physics.set_shape(url, "box", { type = physics.SHAPE_TYPE_BOX, dimensions = vmath.vector3(shape.w, shape.h, shape.d) })
    adapter.collisions[#adapter.collisions + 1] = { id = id, url = url, shape = shape }
    adapter.by_id[id] = shape
end

function M.raycast(adapter, from, to)
    local hit = physics.raycast(vmath.vector3(from.x, from.y, from.z), vmath.vector3(to.x, to.y, to.z), WORLD)
    if not hit then return { hit = false } end
    local shape = adapter.by_id[hit.id]
    return { hit = true, id = shape and shape.id or "unknown", surface = shape and shape.surface or "unknown",
        x = hit.position.x, y = hit.position.y, z = hit.position.z, fraction = hit.fraction }
end

function M.validate(adapter, world, query)
    local maximum_error = 0
    for _, item in ipairs(adapter.collisions) do
        local dims = physics.get_shape(item.url, "box").dimensions
        local pos = go.get_position(item.id)
        local s = item.shape
        maximum_error = math.max(maximum_error, math.abs(dims.x - s.w), math.abs(dims.y - s.h), math.abs(dims.z - s.d),
            math.abs(pos.x - s.x), math.abs(pos.y - s.y), math.abs(pos.z - s.z))
    end
    local nav, by_name = {}, {}
    for _, node in ipairs(world.navigation.nodes) do
        by_name[node.id] = node
        local floor = M.raycast(adapter, { x = node.x, y = node.y + 0.5, z = node.z }, { x = node.x, y = node.y - 0.3, z = node.z })
        nav[#nav + 1] = { id = node.id, supported = floor.hit and math.abs(floor.y - node.y) < 0.01 }
    end
    local edges = {}
    for _, edge in ipairs(world.navigation.edges) do
        local a, b = by_name[edge.from], by_name[edge.to]
        local hit = M.raycast(adapter, { x = a.x, y = a.y + 0.9, z = a.z }, { x = b.x, y = b.y + 0.9, z = b.z })
        local result={ from = edge.from, to = edge.to, clear = not hit.hit }
        if query then
            result.forward=query:walkable(a,b)
            result.reverse=query:walkable(b,a)
        end
        edges[#edges + 1] = result
    end
    return { max_error = maximum_error, colliders = #adapter.collisions, nodes = nav, edges = edges }
end

function M.final(adapter)
    for _, id in ipairs(adapter.objects) do go.delete(id) end
    -- Components retain their references until deferred GO deletion completes.
    for _, path in ipairs(adapter.buffers) do resource.release(path) end
    adapter.objects, adapter.buffers, adapter.collisions, adapter.by_id = {}, {}, {}, {}
end

return M
