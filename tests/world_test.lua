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
        assert(frames < 2000, "Generation did not finish")
    end
    return world, frames
end

test("loading yields within its job budget and respects the clock deadline", function()
    local world = generator.new(layout)
    assert(generator.step(world, 10, 1, function() return 2 end) == 0)
    assert(world.stats.boxes == 0)
    local completed, frames = generate(1)
    assert(frames > 100 and completed.stats.boxes*3 == frames - 3)
end)

test("changing loading budget does not change meshes, bounds or collider placement", function()
    local a, b = generate(1), generate(24)
    assert(#a.batches == #b.batches and #a.colliders == #b.colliders)
    for i, batch in ipairs(a.batches) do
        local other = b.batches[i]
        for _, stream in ipairs({ "positions", "normals", "colors", "edges", "masks", "bounds" }) do
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
    local mesh = require "game.world.mesh"
    local ramp = mesh.new("ramp", "concrete", 0, 0)
    mesh.box(ramp, { x = 70, y = 1.5, z = -5, w = 4, h = 0.2, d = 6,
        rotation_x = math.rad(30), material = "concrete" }, 1)
    assert(math.abs(ramp.bounds[2] - (1.5-math.cos(math.rad(30))*0.1-1.5)) < 1e-7)
    assert(math.abs(ramp.bounds[5] - (1.5+math.cos(math.rad(30))*0.1+1.5)) < 1e-7)
    world.batches[#world.batches+1] = ramp
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

test("both street-facing doorways are open at foot and head height with walls and lintels", function()
    local world=generate(24)
    for _,b in ipairs(layout.buildings) do
        if b.room then
            local front=b.x+b.side*b.w/2
            local function blocked(z,y)
                for _,shape in ipairs(world.colliders) do
                    if math.abs(shape.x-front)<shape.w/2+.5 and math.abs(shape.z-z)<shape.d/2
                        and math.abs(shape.y-y)<shape.h/2 then return shape.id end
                end
            end
            for _,y in ipairs({.2,1,1.9,2.7}) do
                for _,dz in ipairs({-.9,0,.9}) do assert(not blocked(b.door.z+dz,y),b.id) end
            end
            assert(blocked(b.door.z+3,1))
            assert(blocked(b.door.z,3)==b.id.."/door_lintel")
        end
    end
end)

test("structural solids share visual dimensions while trim has no individual collider", function()
    local world = generate(24)
    local shapes = {}
    for _, shape in ipairs(world.shapes) do
        assert(not shapes[shape.id], "Duplicate recipe id: " .. shape.id)
        shapes[shape.id] = shape
    end
    local surfaces = require "game.weapons.surfaces"
    for _, collider in ipairs(world.colliders) do
        assert(shapes[collider.id] == collider)
        assert(surfaces[collider.surface], "Unknown collision surface: "..collider.surface)
    end
    assert(#world.colliders < #world.shapes / 2)
    assert(world.stats.mesh_bytes == world.stats.vertices * 72)
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
    assert(found["W2/room"])
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

test("room light bounds include the actual floor, walls and ceiling without reaching the street", function()
    local world=generate(24)
    local light=world.lights[2]
    local shapes={}
    for _,s in ipairs(world.colliders) do shapes[s.id]=s end
    local floor,ceiling=shapes["W2/floor"],shapes["W2/upper/floor/east"]
    local west,south,north=shapes["W2/west"],shapes["W2/south"],shapes["W2/north"]
    local function near(a,b) assert(math.abs(a-b)<1e-6) end
    near(light.minimum.y,floor.y+floor.h/2)
    near(light.maximum.y,ceiling.y-ceiling.h/2)
    near(light.minimum.x,west.x+west.w/2)
    near(light.minimum.z,south.z+south.d/2)
    near(light.maximum.z,north.z-north.d/2)
    assert(light.maximum.x < -layout.street.half_width)
end)

test("all three flights have matching treads and standing headroom under stacked stairs", function()
    local world=generate(24)
    local interior=require "game.world.interior"
    local nodes,shapes={},{}
    for _,n in ipairs(world.navigation.nodes) do
        assert(not nodes[n.id],"Duplicate node: "..n.id)
        nodes[n.id]=n
    end
    for _,s in ipairs(world.colliders) do shapes[s.id]=s end
    for _,b in ipairs(layout.buildings) do
        if b.room then
            for level=1,b.floors-1 do
                local prefix=interior.prefix(b,level)
                for i=1,b.stairs.steps do
                    local node,tread=nodes[prefix.."stair/"..i],shapes[prefix.."stair/"..i]
                    assert(math.abs(node.y-tread.y-tread.h/2)<1e-7)
                    assert(math.abs(node.z-tread.z)<1e-7)
                    for _,s in ipairs(world.shapes) do
                        if math.abs(node.x-s.x)<s.w/2+.32 and math.abs(node.z-s.z)<s.d/2+.32 then
                            assert(s.y+s.h/2<=node.y+.43 or s.y-s.h/2>=node.y+1.78,
                                "Blocked stair headroom: "..s.id.." above "..node.id)
                        end
                    end
                end
                assert(nodes[prefix.."stair_bottom"].layer==level-1 and nodes[prefix.."stair_top"].layer==level)
            end
            assert(not shapes[b.id.."/mass"],"Enterable building must not have a solid facade")
        end
    end
    assert(not shapes["E2/upper/guard/end"],"Middle-floor guard must not block the next flight")
    assert(shapes["E2/floor2/guard/end"],"Top-floor opening needs its end guard")
end)

test("upper rooms connect only through stairs and have supported doorway centres", function()
    local world = generate(24)
    local function reachable(stairs)
        local found = {street_north=true}
        for _=1,#world.navigation.nodes do
            for _,e in ipairs(world.navigation.edges) do
                if stairs or e.kind ~= "stairs" then
                    if found[e.from] then found[e.to]=true end
                    if found[e.to] then found[e.from]=true end
                end
            end
        end
        return found
    end
    local connected,ground_only=reachable(true),reachable(false)
    for _,n in ipairs(world.navigation.nodes) do
        assert(connected[n.id],"Disconnected node: "..n.id)
        if n.layer>0 then assert(not ground_only[n.id],"Floor shortcut: "..n.id) end
    end
    assert(ground_only["W2/room"] and ground_only["E2/room"])
    for _,n in ipairs(world.navigation.nodes) do
        local support = false
        for _,s in ipairs(world.colliders) do
            if math.abs(n.x-s.x) <= s.w/2+1e-7 and math.abs(n.z-s.z) <= s.d/2+1e-7 then
                support = support or math.abs(s.y+s.h/2-n.y) < 1e-7
                assert(s.y+s.h/2 <= n.y+.43 or s.y-s.h/2 >= n.y+1.78,
                    "Blocked node: "..n.id.." by "..s.id)
            end
        end
        assert(support,"Unsupported node: "..n.id)
    end
end)

test("minimap selects each floor and preserves the stair opening within the GUI budget", function()
    local world = generate(24)
    local hud = require "game.ui.hud"
    local base,upper = layout.street.walk_height,layout.street.walk_height+layout.storey
    assert(#world.minimap <= hud.map_limit)
    local shapes = {}
    for _,s in ipairs(world.minimap) do shapes[s.id]=s end
    assert(not hud.map_rect(shapes["W2/upper/floor/east"],-14,base,0,176))
    assert(hud.map_rect(shapes["W2/upper/floor/east"],-14,upper,0,176).floor)
    assert(not hud.map_rect(shapes["W2/floor"],-14,upper,0,176))
    local bedroom = shapes["W2/upper/bedroom_door/left"]
    assert(not hud.map_rect(bedroom,-14,base,0,176))
    assert(not hud.map_rect(bedroom,-14,upper,0,176).floor)
    for _,s in ipairs(world.minimap) do
        local r=hud.map_rect(s,-19.2,upper,-1,176)
        assert(not r or math.abs(r.x) >= r.w/2 or math.abs(r.y) >= r.h/2,
            "Minimap fills upper stair opening: "..s.id)
    end
end)

test("E2 minimap distinguishes both upper floors and leaves the top stair opening",function()
    local world=generate(24)
    local hud=require "game.ui.hud"
    local y=layout.street.walk_height+2*layout.storey
    local shapes={}
    for _,s in ipairs(world.minimap) do shapes[s.id]=s end
    assert(hud.map_rect(shapes["E2/floor2/floor/west"],10,y,-5,176).floor)
    assert(not hud.map_rect(shapes["E2/upper/floor/west"],10,y,-5,176))
    assert(not hud.map_rect(shapes["E2/floor2/floor/west"],10,y-layout.storey,-5,176))
    for _,s in ipairs(world.minimap) do
        local r=hud.map_rect(s,18.1,y,-6,176)
        assert(not r or math.abs(r.x)>=r.w/2 or math.abs(r.y)>=r.h/2,"Filled E2 opening: "..s.id)
    end
end)

test("west flank forms a second route even when the central street connection is removed",function()
    local world=generate(24)
    local nav=world.navigation
    local function reachable(flank,street)
        local found={["west_loop/north_entry/street"]=true}
        for _=1,#nav.nodes do
            for _,edge in ipairs(nav.edges) do
                local rear=edge.from:match("^west_loop/") and edge.to:match("^west_loop/")
                    and not edge.from:match("/street$") and not edge.to:match("/street$")
                local centre=edge.from=="E2/street" and edge.to=="W2/street"
                if (flank or not rear) and (street or not centre) then
                    if found[edge.from] then found[edge.to]=true end
                    if found[edge.to] then found[edge.from]=true end
                end
            end
        end
        return found["west_loop/south_entry/street"]
    end
    assert(reachable(true,false),"Rear alley must bypass the main street")
    assert(reachable(false,true),"Main street must remain independently connected")
    assert(not reachable(false,false),"Test must cut both routes")
end)

test("flank edges have continuous ground and full standing capsule clearance",function()
    local world=generate(24)
    local nodes={}
    for _,n in ipairs(world.navigation.nodes) do nodes[n.id]=n end
    for _,edge in ipairs(world.navigation.edges) do
        if edge.from:match("^west_loop/") or edge.to:match("^west_loop/") then
            local a,b=nodes[edge.from],nodes[edge.to]
            local steps=math.ceil(math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)/.1)
            for i=0,steps do
                local t=i/steps
                local x,z=a.x+(b.x-a.x)*t,a.z+(b.z-a.z)*t
                for _,dx in ipairs({-.32,0,.32}) do
                    for _,dz in ipairs({-.32,0,.32}) do
                        local supported=false
                        for _,s in ipairs(world.colliders) do
                            if math.abs(x+dx-s.x)<=s.w/2+1e-7 and math.abs(z+dz-s.z)<=s.d/2+1e-7 then
                                local top,bottom=s.y+s.h/2,s.y-s.h/2
                                supported=supported or (top>=-1e-7 and top<=.146)
                                assert(top<=.43 or bottom>=1.78,"Blocked flank: "..edge.from.." by "..s.id)
                            end
                        end
                        assert(supported,"Ground gap: "..edge.from.." at "..x..","..z)
                    end
                end
            end
        end
    end
end)

test("cover positions have support and clearance; closed shopfronts face the street",function()
    local world=generate(24)
    local shapes={}
    for _,s in ipairs(world.shapes) do shapes[s.id]=s end
    for _,cover in ipairs(world.cover) do
        local shape=shapes[cover.id]
        assert(cover.height==shape.h)
        local support=false
        for _,s in ipairs(world.colliders) do
            if math.abs(cover.x-s.x)<=s.w/2+.32 and math.abs(cover.z-s.z)<=s.d/2+.32 then
                assert(s.y+s.h/2<=cover.y+.43 or s.y-s.h/2>=cover.y+1.78,"Blocked cover: "..cover.id.." by "..s.id)
            end
            if math.abs(cover.x-s.x)<=s.w/2 and math.abs(cover.z-s.z)<=s.d/2 then
                support=support or math.abs(s.y+s.h/2-cover.y)<1e-7
            end
        end
        assert(support,"Unsupported cover: "..cover.id)
    end
    for _,b in ipairs(layout.buildings) do
        if not b.room then
            local mass=shapes[b.id.."/mass"]
            assert(mass and math.abs(mass.y-mass.h/2)<1e-7,"Facade floats above alley")
            local shop=shapes[b.id.."/shop/1"]
            assert((shop.x-b.x)*b.side>b.w/2)
            assert(shop.z-shop.d/2>=b.z-b.d/2 and shop.z+shop.d/2<=b.z+b.d/2)
        end
    end
    -- Conforming clipped edges remove depth ties; the bounded extra vertices
    -- raise streams to 1.39 MiB while retaining the same material/chunk batches.
    assert(world.stats.batches<100 and world.stats.mesh_bytes<3*1024*1024)
    assert(#world.minimap<=require("game.ui.hud").map_limit)
end)

print(count .. " world tests passed")
