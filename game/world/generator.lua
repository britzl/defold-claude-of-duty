local rng = require "game.rng"
local mesh = require "game.world.mesh"
local recipes = require "game.world.recipes"
local interior = require "game.world.interior"
local visible_faces = require "game.world.visible_faces"
local daylight = require "game.render.daylight"
local materials=require "game.world.materials"
local M = { max_batch_vertices = 12288 }

-- These monotonic timestamps include frames missed by an attaching profiler.
function M.mark(world,stage)
    if world.timings and not world.timings[stage] then
        world.timings[stage]=(worldmesh.clock()-world.load_started)*1000
    end
end

local function append(batch, shape, material)
    for _,name in ipairs({"positions","normals","colors","edges","masks"}) do
        local target,source=batch[name],shape[name]
        local offset=#target
        for i=1,#source do target[offset+i]=source[i] end
    end
    for _=1,shape.vertex_count do
        batch.surfaces[#batch.surfaces+1]=material.kind
        batch.surfaces[#batch.surfaces+1]=material.weather or 1
    end
    for i=1,3 do
        batch.bounds[i]=math.min(batch.bounds[i],shape.bounds[i])
        batch.bounds[i+3]=math.max(batch.bounds[i+3],shape.bounds[i+3])
    end
    batch.vertex_count=batch.vertex_count+shape.vertex_count
    batch.boxes=batch.boxes+1
end

local function metadata(layout)
    local s, base = layout.street, layout.street.walk_height
    local nav = { nodes = {}, edges = {}, flanks = {}, surfaces = {
        { id="street",layer=0,y=0,x0=-s.half_width,x1=s.half_width,z0=s.z_min,z1=s.z_max },
        { id="west_walk",layer=0,y=base,x0=-s.kerb,x1=-s.half_width,z0=s.z_min,z1=s.z_max },
        { id="east_walk",layer=0,y=base,x0=s.half_width,x1=s.kerb,z0=s.z_min,z1=s.z_max },
    } }
    local function node(id,x,y,z)
        local n={id=id,x=x,y=y,z=z,layer=0}
        nav.nodes[#nav.nodes+1]=n
        return n
    end
    local hubs={}
    for _,p in ipairs(layout.street_route or {
        {id="north",x=0,z=s.z_max-4},{id="south",x=0,z=s.z_min+4},
    }) do hubs[#hubs+1]=node("street_"..p.id,p.x,0,p.z) end
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
            if b.secondary_door then
                local d,z=b.secondary_door,b.z-b.d/2
                node(prefix.."alley_inside",d.x,base,z+2)
                node(prefix.."alley_door",d.x,base,z)
                node(prefix.."alley_outside",d.x,0,z-1)
                nav.edges[#nav.edges+1]={from=prefix.."room",to=prefix.."alley_inside",kind="walk"}
                nav.edges[#nav.edges+1]={from=prefix.."alley_inside",to=prefix.."alley_door",kind="doorway",width=d.width,height=d.height}
                nav.edges[#nav.edges+1]={from=prefix.."alley_door",to=prefix.."alley_outside",kind="step",rise=base}
                nav.edges[#nav.edges+1]={from=prefix.."alley_outside",to=d.route_node,kind="walk"}
            end
        end
    end
    for _,ground in ipairs(layout.ground or {}) do
        nav.surfaces[#nav.surfaces+1]={id=ground.id,layer=0,y=ground.y,
            x0=ground.x0,x1=ground.x1,z0=ground.z0,z1=ground.z1}
    end
    if layout.terrain then
        local t=layout.terrain
        nav.surfaces[#nav.surfaces+1]={id="terrain",layer=0,y=0,x0=t.x0,x1=t.x1,z0=t.z0,z1=t.z1}
    end
    for _,route in ipairs(layout.routes or {}) do
        local previous
        local flank={id=route.id,points={}}
        for i,p in ipairs(route.points) do
            local id=route.id.."/"..p.id
            flank.points[#flank.points+1]=node(id,p.x,p.y,p.z)
            if previous then nav.edges[#nav.edges+1]={from=previous,to=id,kind="walk"} end
            previous=id
            if i==1 or i==#route.points then
                local side=p.x<0 and -1 or 1
                hubs[#hubs+1]=node(id.."/street",0,0,p.z)
                node(id.."/walk",side*(s.half_width+s.kerb)/2,base,p.z)
                local street={x=0,y=0,z=p.z}
                local walk={x=side*(s.half_width+s.kerb)/2,y=base,z=p.z}
                if i==1 then
                    table.insert(flank.points,1,walk);table.insert(flank.points,1,street)
                else
                    flank.points[#flank.points+1]=walk;flank.points[#flank.points+1]=street
                end
                nav.edges[#nav.edges+1]={from=id.."/street",to=id.."/walk",kind="step",rise=base}
                nav.edges[#nav.edges+1]={from=id.."/walk",to=id,kind="step",rise=base-p.y}
            end
        end
        nav.flanks[#nav.flanks+1]=flank
    end
    -- The street spine and flank endpoints together form a traversable cycle.
    table.sort(hubs,function(a,b) return a.z==b.z and a.id<b.id or a.z<b.z end)
    for i=2,#hubs do
        nav.edges[#nav.edges+1]={from=hubs[i-1].id,to=hubs[i].id,kind="walk"}
    end
    return nav
end

function M.new(layout, options)
    local started=worldmesh and worldmesh.clock()
    options = options or {}
    local backend=options.backend or (worldmesh and "native" or "lua")
    assert(backend=="native" or backend=="lua","Invalid world mesh backend")
    assert(backend~="native" or worldmesh,"WorldMesh native extension is required")
    local world = {
        load_started=started,timings=started and {} or nil,
        mesh_backend=backend, verify_mesh=options.verify_mesh,
        spawn = layout.spawn, spawn_points = { { id = "player", position = layout.spawn } },
        views = layout.views, layout = layout, seed = options.seed or layout.seed,
        spawn_anchors = layout.spawn_anchors or {},
        batches = {}, colliders = {}, shapes = {}, navigation = metadata(layout),
        lights = { { kind = "sun", direction = { x = daylight.sun_direction[1], y = daylight.sun_direction[2], z = daylight.sun_direction[3] } } },
        lighting_volumes = {},
        cover = {}, minimap = {}, ready = false, phase = "geometry", jobs_done = 0,
        stats = { boxes = 0, vertices = 0, mesh_bytes = 0, batches = 0, colliders = 0 },
        batch_lookup = {},
    }
    for _,e in ipairs(layout.enemies or {{id="enemy_1",x=0,y=0,z=-12}}) do
        world.spawn_points[#world.spawn_points+1]={id=e.id,squad=e.squad,
            position={x=e.x,y=e.y,z=e.z},yaw=e.yaw or math.pi,patrol=e.patrol}
    end
    for _, b in ipairs(layout.buildings) do
        if b.room then
            for _, light in ipairs(interior.lights(layout,b)) do world.lights[#world.lights+1]=light end
            for _, volume in ipairs(interior.lighting_volumes(layout,b)) do world.lighting_volumes[#world.lighting_volumes+1]=volume end
        end
    end
    assert(#world.lighting_volumes<=daylight.max_volumes,"Indirect lighting volume budget exceeded")
    world.decoration_rng = rng.new(world.seed, "decoration")
    world.spawn_rng = rng.new(world.seed, "spawns")
    world.weapon_rng = rng.new(world.seed, "weapons")
    world.job = coroutine.create(function() recipes.generate(layout, options.detail ~= false, world.seed) end)
    return world
end

local function add(world, shape, faces)
    -- Sparse terrain uses larger cells; detailed architecture retains 16 m
    -- culling cells. Surface selection travels with vertices, not draw state.
    local terrain=shape.id and shape.id:match("^terrain/")
    local chunk = world.layout.chunk_size * (terrain and 4 or 1)
    local cx, cz = math.floor(shape.x / chunk), math.floor(shape.z / chunk)
    local material=materials[shape.material]
    local key = (terrain and "terrain/" or "world/") .. cx .. "/" .. cz
    local geometry
    local shade=0.94 + world.decoration_rng() * 0.12
    if profiler then profiler.scope_begin("loading.mesh.shape") end
    if world.native_builder then
        if world.verify_mesh then
            local reference=mesh.new(shape.id,shape.material,cx,cz)
            mesh.shape(reference,shape,shade,faces,world.edge_points)
            worldmesh.verify(world.native_builder,shape,material,shade,faces,reference)
        end
        geometry={vertex_count=worldmesh.append(world.native_builder,shape,material,shade,faces)}
    else
        geometry=mesh.new(shape.id,shape.material,cx,cz)
        mesh.shape(geometry,shape,shade,faces,world.edge_points)
    end
    if profiler then profiler.scope_end() end
    local batch = world.batch_lookup[key]
    if geometry.vertex_count>0 and not world.native_builder then
        -- Bound uploads by actual vertex work, including curved primitives.
        assert(geometry.vertex_count<=M.max_batch_vertices,"World primitive exceeds mesh upload budget")
        if not batch or batch.vertex_count+geometry.vertex_count>M.max_batch_vertices then
            batch = mesh.new(key .. "/" .. (#world.batches + 1), shape.material, cx, cz)
            batch.surfaces={}
            world.batches[#world.batches + 1] = batch
            world.batch_lookup[key] = batch
        end
        if profiler then profiler.scope_begin("loading.mesh.append") end
        append(batch,geometry,material)
        if profiler then profiler.scope_end() end
    end
    if shape.surface then
        world.colliders[#world.colliders + 1] = shape
        world.minimap[#world.minimap + 1] = { id = shape.id, x = shape.x, z = shape.z, w = shape.w, d = shape.d,
            bottom = shape.y - shape.h / 2, top = shape.y + shape.h / 2, surface = shape.surface }
        if shape.cover then
            local nx,nz=shape.cover.normal_x,shape.cover.normal_z
            local floor=shape.cover.ground_y or shape.y-shape.h/2
            world.cover[#world.cover + 1] = { id = shape.id,
                x = shape.x + nx*(shape.w/2+.4), z = shape.z + nz*(shape.d/2+.4),
                y = floor, height = shape.y+shape.h/2-floor, normal_x = nx, normal_z = nz }
        end
    end
    local stats = world.stats
    stats.boxes, stats.vertices = stats.boxes + 1, stats.vertices + geometry.vertex_count
    stats.mesh_bytes = stats.mesh_bytes + geometry.vertex_count * 20 * 4
    stats.batches, stats.colliders = #world.batches, #world.colliders
end

-- The caller supplies both a hard job bound and (optionally) a clock deadline.
-- No frame-dependent randomness: yielding never changes generated output.
function M.step(world, max_jobs, deadline, now)
    if world.phase ~= "geometry" then return 0 end
    M.mark(world,"recipes")
    local done = 0
    while done < max_jobs and (not deadline or now() < deadline) do
        if world.job then
            if profiler then profiler.scope_begin("loading.geometry.recipes") end
            local ok, shape = coroutine.resume(world.job)
            assert(ok, shape)
            if coroutine.status(world.job) == "dead" then
                world.job=nil
                world.face_index=1
                world.shape_faces,world.edge_points={},{}
                world.face_grid=visible_faces.index(world.shape_bounds)
                M.mark(world,"faces")
            else
                world.shapes[#world.shapes+1]=shape
                world.shape_bounds=world.shape_bounds or {}
                world.shape_bounds[#world.shapes]=visible_faces.bounds(shape)
            end
            if profiler then profiler.scope_end() end
        elseif world.face_index then
            local i=world.face_index
            if i<=#world.shapes then
                if profiler then profiler.scope_begin("loading.geometry.visible_faces") end
                local faces=visible_faces.for_box(i,world.shape_bounds,world.face_grid)
                world.shape_faces[i]=faces
                if profiler then profiler.scope_end();profiler.scope_begin("loading.geometry.register_edges") end
                if faces then visible_faces.register_edges(world.edge_points,world.shape_bounds[i],faces) end
                if profiler then profiler.scope_end() end
                world.face_index=i+1
            else
                world.face_index=nil;world.mesh_index=1
                M.mark(world,"construction")
                if world.mesh_backend=="native" then
                    world.native_builder=worldmesh.begin(world.edge_points,world.layout.chunk_size,M.max_batch_vertices)
                end
            end
        elseif world.mesh_index<=#world.shapes then
            local i=world.mesh_index
            add(world,world.shapes[i],world.shape_faces[i])
            world.mesh_index=i+1
        else
            if profiler then profiler.scope_begin("loading.geometry.finish") end
            if world.native_builder then world.batches=worldmesh.finish(world.native_builder) end
            world.batch_lookup,world.decoration_rng,world.shape_bounds=nil,nil,nil
            world.shape_faces,world.edge_points,world.face_grid=nil,nil,nil
            local visible={}
            for _,batch in ipairs(world.batches) do
                if batch.vertex_count>0 then visible[#visible+1]=batch end
            end
            world.batches=visible
            for _,batch in ipairs(require("game.render.glass").world(world.layout)) do
                batch.native_upload=world.mesh_backend=="native"
                world.batches[#world.batches+1]=batch
                world.stats.vertices=world.stats.vertices+batch.vertex_count
                world.stats.mesh_bytes=world.stats.mesh_bytes+batch.vertex_count*18*4
            end
            world.stats.batches=#world.batches
            world.phase="meshes"
            M.mark(world,"upload")
            if profiler then profiler.scope_end() end
            break
        end
        done = done + 1
        world.jobs_done = world.jobs_done + 1
    end
    return done
end

return M
