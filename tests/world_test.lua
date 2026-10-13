package.path = "./?.lua;" .. package.path
local generator = require "game.world.generator"
local layout = require "game.world.layout"
local runtime = require "game.runtime"
local count = 0

local function test(name, run)
    run()
    count = count + 1
    print("PASS " .. name)
end

local function generate(budget, options)
    local world = generator.new(layout, options)
    local frames = 0
    while world.phase == "geometry" do
        local jobs = generator.step(world, budget)
        assert(jobs <= budget)
        frames = frames + 1
        assert(frames < 1000, "Generation did not finish")
    end
    return world, frames
end

test("loading yields within its job budget and respects the clock deadline", function()
    local world = generator.new(layout)
    assert(generator.step(world, 10, 1, function() return 2 end) == 0)
    assert(world.stats.boxes == 0)
    local completed, frames = generate(1)
    assert(frames > 100 and completed.stats.boxes == frames - 1)
end)

test("changing loading budget does not change meshes, bounds or collider placement", function()
    local a, b = generate(1), generate(24)
    assert(#a.batches == #b.batches and #a.colliders == #b.colliders)
    for i, batch in ipairs(a.batches) do
        local other = b.batches[i]
        for _, stream in ipairs({ "positions", "normals", "colors", "bounds" }) do
            assert(#batch[stream] == #other[stream])
            for j, value in ipairs(batch[stream]) do assert(value == other[stream][j]) end
        end
    end
    for i, shape in ipairs(a.colliders) do
        for _, key in ipairs({ "id", "surface", "x", "y", "z", "w", "h", "d" }) do
            assert(shape[key] == b.colliders[i][key])
        end
    end
end)

test("every vertex fits its culling bounds; triangle winding agrees with normals", function()
    local world = generate(24)
    for _, batch in ipairs(world.batches) do
        assert(batch.boxes <= 64 and batch.vertex_count == #batch.positions / 3)
        assert(#batch.normals == #batch.positions and #batch.colors == batch.vertex_count * 4)
        for i, value in ipairs(batch.positions) do
            local axis = (i - 1) % 3 + 1
            assert(value >= batch.bounds[axis] and value <= batch.bounds[axis + 3])
        end
        local p, n = batch.positions, batch.normals
        for i = 1, #p, 9 do
            local ax, ay, az = p[i+3]-p[i], p[i+4]-p[i+1], p[i+5]-p[i+2]
            local bx, by, bz = p[i+6]-p[i], p[i+7]-p[i+1], p[i+8]-p[i+2]
            local dot = (ay*bz-az*by)*n[i] + (az*bx-ax*bz)*n[i+1] + (ax*by-ay*bx)*n[i+2]
            assert(dot > 0, "Inverted or degenerate triangle in " .. batch.key)
        end
    end
end)

local function intersects_door_volume(shape, z, y)
    return shape.x + shape.w / 2 > -7.2 and shape.x - shape.w / 2 < -6
        and y > shape.y - shape.h / 2 and y < shape.y + shape.h / 2
        and z > shape.z - shape.d / 2 and z < shape.z + shape.d / 2
end

test("doorway is a real opening at foot and head height, bounded by walls and lintel", function()
    local world = generate(24)
    for _, y in ipairs({ 0.2, 1, 1.9, 2.7 }) do
        for _, z in ipairs({ -1.2, 0, 1.2 }) do
            for _, shape in ipairs(world.colliders) do
                assert(not intersects_door_volume(shape, z, y), "Blocked doorway: " .. shape.id)
            end
        end
    end
    local wall, lintel = false, false
    for _, shape in ipairs(world.colliders) do
        wall = wall or intersects_door_volume(shape, 3, 1)
        lintel = lintel or intersects_door_volume(shape, 0, 3)
    end
    assert(wall and lintel)
end)

test("structural solids share visual dimensions while trim has no individual collider", function()
    local world = generate(24)
    local shapes = {}
    for _, shape in ipairs(world.shapes) do
        assert(not shapes[shape.id], "Duplicate recipe id: " .. shape.id)
        shapes[shape.id] = shape
    end
    for _, collider in ipairs(world.colliders) do assert(shapes[collider.id] == collider) end
    assert(#world.colliders < #world.shapes / 2)
    assert(world.stats.mesh_bytes == world.stats.vertices * 40)
    assert(#world.batches < #world.shapes / 4)
end)

test("decoration detail and seed cannot move collision or change spawn/weapon random streams", function()
    local a = generate(24, { detail = true, seed = 42 })
    local b = generate(24, { detail = false, seed = 42 })
    local c = generate(24, { detail = true, seed = 99 })
    assert(a.stats.boxes > b.stats.boxes and #a.colliders == #b.colliders)
    for i, shape in ipairs(a.colliders) do
        assert(shape.id == b.colliders[i].id and shape.x == c.colliders[i].x)
    end
    for _ = 1, 10 do
        assert(a.spawn_rng() == b.spawn_rng())
        assert(a.weapon_rng() == b.weapon_rng())
    end
    assert(a.batches[1].colors[1] ~= c.batches[1].colors[1])
end)

test("navigation connects the street to the raised room through an explicit doorway", function()
    local world = generate(24)
    local found = { street_north = true }
    for _ = 1, #world.navigation.nodes do
        for _, edge in ipairs(world.navigation.edges) do
            if found[edge.from] then found[edge.to] = true end
            if found[edge.to] then found[edge.from] = true end
        end
    end
    assert(found.room)
    local doorway = false
    for _, edge in ipairs(world.navigation.edges) do
        if edge.kind == "doorway" then doorway = edge.width >= 0.64 and edge.height >= 1.78 end
    end
    assert(doorway and #world.cover > 0 and #world.minimap == #world.colliders)
    assert(world.navigation.surfaces[4].y == layout.street.walk_height)
end)

test("adapter receives each resource once; readiness waits for installation and teardown runs", function()
    local batches, collisions, disposed = 0, 0, false
    local adapter = { api = {
        add_batch = function() batches = batches + 1 end,
        add_collision = function() collisions = collisions + 1 end,
        final = function() disposed = true end,
    } }
    local ctx = runtime.new({ world = adapter })
    for _ = 1, 300 do
        if ctx.world.ready then break end
        runtime.update(ctx, 1/60)
    end
    assert(ctx.world.ready)
    assert(batches == ctx.world.stats.batches and collisions == ctx.world.stats.colliders)
    runtime.update(ctx, 1/60)
    assert(batches == ctx.world.stats.batches)
    runtime.final(ctx)
    assert(disposed and ctx.world == nil)
end)

print(count .. " world tests passed")
