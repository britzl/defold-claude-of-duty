-- Engine adapter. Generation and metadata remain testable without Defold.
local materials = require "game.world.materials"
local M = {}
local POSITION, NORMAL, COLOR = hash("position"), hash("normal"), hash("color")
local WORLD = { hash("world") }

function M.new(mesh_factory, collision_factory)
    return { api = M, mesh_factory = mesh_factory, collision_factory = collision_factory,
        objects = {}, buffers = {}, collisions = {}, by_id = {} }
end

function M.add_batch(adapter, batch)
    local data = buffer.create(batch.vertex_count, {
        { name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
        { name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
        { name = COLOR, type = buffer.VALUE_TYPE_FLOAT32, count = 4 },
    })
    local positions, normals, colors = buffer.get_stream(data, POSITION), buffer.get_stream(data, NORMAL), buffer.get_stream(data, COLOR)
    for i = 1, #batch.positions do positions[i] = batch.positions[i]; normals[i] = batch.normals[i] end
    for i = 1, #batch.colors do colors[i] = batch.colors[i] end
    buffer.set_metadata(data, "AABB", batch.bounds, buffer.VALUE_TYPE_FLOAT32)
    local id = factory.create(adapter.mesh_factory)
    adapter.objects[#adapter.objects + 1] = id
    local path = resource.create_buffer("/generated/world_" .. hash_to_hex(id) .. ".bufferc", { buffer = data })
    adapter.buffers[#adapter.buffers + 1] = path
    local url = msg.url(nil, id, "mesh")
    go.set(url, "vertices", path)
    go.set(url, "surface", vmath.vector4(materials[batch.material].kind, 0, 0, 0))
    batch.object, batch.resource = id, path
    -- The resource owns the buffer now. Keep only bounds/stats in Lua.
    batch.positions, batch.normals, batch.colors = nil, nil, nil
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

function M.validate(adapter, world)
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
        edges[#edges + 1] = { from = edge.from, to = edge.to, clear = not hit.hit }
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
