local rng = require "game.rng"
local mesh = require "game.world.mesh"
local recipes = require "game.world.recipes"
local interior = require "game.world.interior"
local M = {}

local function metadata(layout)
    local base = layout.street.walk_height
    local shop
    for _, building in ipairs(layout.buildings) do
        if building.room then shop = building; break end
    end
    assert(shop, "The first block requires one enterable shop")
    local door_x = shop.x + shop.w / 2
    local door_z = shop.door.z
    local nodes = {
        { id = "street_north", x = 0, y = 0, z = 8, layer = 0 },
        { id = "street", x = 0, y = 0, z = door_z, layer = 0 },
        { id = "street_south", x = 0, y = 0, z = -12, layer = 0 },
        { id = "west_walk", x = -5.5, y = base, z = door_z, layer = 0 },
        { id = "door", x = door_x, y = base, z = door_z, layer = 0 },
        { id = "room", x = door_x - 3, y = base, z = door_z, layer = 0 },
    }
    local edges = {
        { from = "street_north", to = "street", kind = "walk" },
        { from = "street", to = "street_south", kind = "walk" },
        { from = "street", to = "west_walk", kind = "step", rise = base },
        { from = "west_walk", to = "door", kind = "doorway", width = shop.door.width, height = shop.door.height },
        { from = "door", to = "room", kind = "walk" },
    }
    local s = layout.street
    local nav = {
        nodes = nodes, edges = edges,
        surfaces = {
            { id = "street", layer = 0, y = 0, x0 = -s.half_width, x1 = s.half_width, z0 = s.z_min, z1 = s.z_max },
            { id = "west_walk", layer = 0, y = base, x0 = -s.kerb, x1 = -s.half_width, z0 = s.z_min, z1 = s.z_max },
            { id = "east_walk", layer = 0, y = base, x0 = s.half_width, x1 = s.kerb, z0 = s.z_min, z1 = s.z_max },
            { id = "room", layer = 0, y = base, x0 = shop.x - shop.w / 2 + layout.wall,
                x1 = door_x - layout.wall, z0 = shop.z - shop.d / 2 + layout.wall, z1 = shop.z + shop.d / 2 - layout.wall },
        },
    }
    interior.navigation(layout, shop, nav)
    return nav
end

function M.new(layout, options)
    options = options or {}
    local world = {
        spawn = layout.spawn, spawn_points = { { id = "player", position = layout.spawn },
            { id = "enemy", position = { x = 0, y = 0, z = -12 } } },
        views = layout.views, layout = layout, seed = options.seed or layout.seed,
        batches = {}, colliders = {}, shapes = {}, navigation = metadata(layout),
        lights = { { kind = "sun", direction = { x = -0.6, y = 0.85, z = 0.4 } } },
        cover = {}, minimap = {}, ready = false, phase = "geometry", jobs_done = 0,
        stats = { boxes = 0, vertices = 0, mesh_bytes = 0, batches = 0, colliders = 0 },
        batch_lookup = {},
    }
    for _, b in ipairs(layout.buildings) do
        if b.room then
            for _, light in ipairs(interior.lights(layout,b)) do world.lights[#world.lights+1]=light end
        end
    end
    world.decoration_rng = rng.new(world.seed, "decoration")
    world.spawn_rng = rng.new(world.seed, "spawns")
    world.weapon_rng = rng.new(world.seed, "weapons")
    world.job = coroutine.create(function() recipes.generate(layout, options.detail ~= false) end)
    return world
end

local function add(world, shape)
    local chunk = world.layout.chunk_size
    local cx, cz = math.floor(shape.x / chunk), math.floor(shape.z / chunk)
    local key = shape.material .. "/" .. cx .. "/" .. cz
    local batch = world.batch_lookup[key]
    -- Bound each upload job as well as each geometry job.
    if not batch or batch.boxes == 64 then
        batch = mesh.new(key .. "/" .. (#world.batches + 1), shape.material, cx, cz)
        world.batches[#world.batches + 1] = batch
        world.batch_lookup[key] = batch
    end
    mesh.box(batch, shape, 0.94 + world.decoration_rng() * 0.12)
    world.shapes[#world.shapes + 1] = shape
    if shape.surface then
        world.colliders[#world.colliders + 1] = shape
        world.minimap[#world.minimap + 1] = { id = shape.id, x = shape.x, z = shape.z, w = shape.w, d = shape.d,
            bottom = shape.y - shape.h / 2, top = shape.y + shape.h / 2, surface = shape.surface }
        if shape.id == "cover/barrier" or shape.id:match("^crate/%d+$") then
            world.cover[#world.cover + 1] = { id = shape.id, x = shape.x - shape.w / 2 - 0.4,
                y = shape.y - shape.h / 2, z = shape.z, height = shape.h, normal_x = -1, normal_z = 0 }
        end
    end
    local stats = world.stats
    stats.boxes, stats.vertices = stats.boxes + 1, stats.vertices + 36
    stats.mesh_bytes = stats.vertices * 10 * 4
    stats.batches, stats.colliders = #world.batches, #world.colliders
end

-- The caller supplies both a hard job bound and (optionally) a clock deadline.
-- No frame-dependent randomness: yielding never changes generated output.
function M.step(world, max_jobs, deadline, now)
    if world.phase ~= "geometry" then return 0 end
    local done = 0
    while done < max_jobs and (not deadline or now() < deadline) do
        local ok, shape = coroutine.resume(world.job)
        assert(ok, shape)
        if coroutine.status(world.job) == "dead" then
            world.job, world.batch_lookup, world.decoration_rng = nil, nil, nil
            world.phase = "meshes"
            break
        end
        add(world, shape)
        done = done + 1
        world.jobs_done = world.jobs_done + 1
    end
    return done
end

return M
