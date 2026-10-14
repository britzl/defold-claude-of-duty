local rng = require "game.rng"
local mesh = require "game.world.mesh"
local recipes = require "game.world.recipes"
local interior = require "game.world.interior"
local M = {}

local function metadata(layout)
    local s, base = layout.street, layout.street.walk_height
    local nav = { nodes = {}, edges = {}, surfaces = {
        { id="street",layer=0,y=0,x0=-s.half_width,x1=s.half_width,z0=s.z_min,z1=s.z_max },
        { id="west_walk",layer=0,y=base,x0=-s.kerb,x1=-s.half_width,z0=s.z_min,z1=s.z_max },
        { id="east_walk",layer=0,y=base,x0=s.half_width,x1=s.kerb,z0=s.z_min,z1=s.z_max },
    } }
    local function node(id,x,y,z)
        local n={id=id,x=x,y=y,z=z,layer=0}
        nav.nodes[#nav.nodes+1]=n
        return n
    end
    local hubs={node("street_north",0,0,s.z_max-4),node("street_south",0,0,s.z_min+4)}
    for _,b in ipairs(layout.buildings) do
        if b.room then
            local front=b.x+b.side*b.w/2
            local prefix=b.id.."/"
            hubs[#hubs+1]=node(prefix.."street",0,0,b.door.z)
            node(prefix.."walk",-b.side*(s.half_width+s.kerb)/2,base,b.door.z)
            node(prefix.."door",front,base,b.door.z)
            node(prefix.."room",front-b.side*3,base,b.door.z)
            nav.edges[#nav.edges+1]={from=prefix.."street",to=prefix.."walk",kind="step",rise=base}
            nav.edges[#nav.edges+1]={from=prefix.."walk",to=prefix.."door",kind="doorway",width=b.door.width,height=b.door.height}
            nav.edges[#nav.edges+1]={from=prefix.."door",to=prefix.."room",kind="walk"}
            nav.surfaces[#nav.surfaces+1]={id=prefix.."room",layer=0,y=base,
                x0=b.x-b.w/2+layout.wall,x1=b.x+b.w/2-layout.wall,
                z0=b.z-b.d/2+layout.wall,z1=b.z+b.d/2-layout.wall}
            interior.navigation(layout,b,nav,prefix.."room")
        end
    end
    for _,ground in ipairs(layout.ground or {}) do
        nav.surfaces[#nav.surfaces+1]={id=ground.id,layer=0,y=ground.y,
            x0=ground.x0,x1=ground.x1,z0=ground.z0,z1=ground.z1}
    end
    for _,route in ipairs(layout.routes or {}) do
        local previous
        for i,p in ipairs(route.points) do
            local id=route.id.."/"..p.id
            node(id,p.x,p.y,p.z)
            if previous then nav.edges[#nav.edges+1]={from=previous,to=id,kind="walk"} end
            previous=id
            if i==1 or i==#route.points then
                local side=p.x<0 and -1 or 1
                hubs[#hubs+1]=node(id.."/street",0,0,p.z)
                node(id.."/walk",side*(s.half_width+s.kerb)/2,base,p.z)
                nav.edges[#nav.edges+1]={from=id.."/street",to=id.."/walk",kind="step",rise=base}
                nav.edges[#nav.edges+1]={from=id.."/walk",to=id,kind="step",rise=base-p.y}
            end
        end
    end
    -- The street spine and flank endpoints together form a traversable cycle.
    table.sort(hubs,function(a,b) return a.z==b.z and a.id<b.id or a.z<b.z end)
    for i=2,#hubs do
        nav.edges[#nav.edges+1]={from=hubs[i-1].id,to=hubs[i].id,kind="walk"}
    end
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
        if shape.cover then
            local nx,nz=shape.cover.normal_x,shape.cover.normal_z
            world.cover[#world.cover + 1] = { id = shape.id,
                x = shape.x + nx*(shape.w/2+.4), z = shape.z + nz*(shape.d/2+.4),
                y = shape.y - shape.h / 2, height = shape.h, normal_x = nx, normal_z = nz }
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
