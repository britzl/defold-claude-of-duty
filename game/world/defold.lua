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

local function begin_batch(batch)
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
    return {batch=batch,data=data,cursor=0,
        positions=buffer.get_stream(data,POSITION),normals=buffer.get_stream(data,NORMAL),
        colors=buffer.get_stream(data,COLOR),edges=buffer.get_stream(data,EDGES),masks=buffer.get_stream(data,MASKS),
        surfaces=not batch.glass and buffer.get_stream(data,SURFACES) or nil}
end

local function copy_vertices(upload,count)
    if profiler then profiler.scope_begin("loading.upload.streams") end
    local batch=upload.batch
    local first,last=upload.cursor,math.min(upload.cursor+count,batch.vertex_count)
    local positions,normals=upload.positions,upload.normals
    local source_positions,source_normals=batch.positions,batch.normals
    for i=first*3+1,last*3 do positions[i]=source_positions[i];normals[i]=source_normals[i] end
    local colors,edges,masks=upload.colors,upload.edges,upload.masks
    local source_colors,source_edges,source_masks=batch.colors,batch.edges,batch.masks
    for i=first*4+1,last*4 do colors[i]=source_colors[i];edges[i]=source_edges[i];masks[i]=source_masks[i] end
    local surfaces=upload.surfaces
    if surfaces then
        local source=batch.surfaces
        if source then
            for i=first*2+1,last*2 do surfaces[i]=source[i] end
        else
            local material=materials[batch.material]
            local kind,weather=batch.surface and batch.surface[1] or material.kind,material.weather or 1
            for i=first+1,last do surfaces[i*2-1]=kind;surfaces[i*2]=weather end
        end
    end
    upload.cursor=last
    if profiler then profiler.scope_end() end
end

local function finish_batch(adapter,upload)
    if profiler then profiler.scope_begin("loading.upload.resource") end
    local batch,data=upload.batch,upload.data
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
    if profiler then profiler.scope_end() end
    batch.object, batch.resource = id, path
    -- The resource owns the buffer now. Keep only bounds/stats in Lua.
    batch.positions, batch.normals, batch.colors, batch.edges, batch.masks = nil, nil, nil, nil, nil
    batch.surfaces=nil
end

-- A partial buffer is never exposed to a mesh. Preserve batch boundaries and
-- draw order, but allow the loader to check its deadline between vertex slices.
function M.step_batch(adapter,batch,max_vertices)
    assert(max_vertices>0,"Upload slice must contain vertices")
    if profiler then profiler.scope_begin("loading.upload.batch") end
    local upload=adapter.pending_batch
    if not upload then upload=begin_batch(batch);adapter.pending_batch=upload end
    assert(upload.batch==batch,"Finish the pending batch before starting another")
    copy_vertices(upload,max_vertices)
    local complete=upload.cursor==batch.vertex_count
    if complete then
        finish_batch(adapter,upload)
        adapter.pending_batch=nil
    end
    if profiler then profiler.scope_end() end
    return complete
end

function M.add_batch(adapter,batch)
    M.step_batch(adapter,batch,batch.vertex_count)
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
    adapter.pending_batch=nil -- Unpublished buffer is Lua-owned and can be collected.
    for _, id in ipairs(adapter.objects) do go.delete(id) end
    -- Components retain their references until deferred GO deletion completes.
    for _, path in ipairs(adapter.buffers) do resource.release(path) end
    adapter.objects, adapter.buffers, adapter.collisions, adapter.by_id = {}, {}, {}, {}
end

return M
