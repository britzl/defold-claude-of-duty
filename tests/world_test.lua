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
        assert(frames < 15000, "Generation did not finish")
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
        assert(batch.boxes <= 64 and batch.vertex_count>0 and batch.vertex_count == #batch.positions / 3)
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
    for _ = 1, 3000 do
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

test("all five flights have matching treads and standing headroom under stacked stairs", function()
    local world=generate(24)
    local interior=require "game.world.interior"
    local nodes,shapes={},{}
    for _,n in ipairs(world.navigation.nodes) do
        assert(not nodes[n.id],"Duplicate node: "..n.id)
        nodes[n.id]=n
    end
    for _,s in ipairs(world.colliders) do shapes[s.id]=s end
    for _,b in ipairs(layout.buildings) do
        if b.stairs then
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
    assert(#hud.map_visible(world.minimap,0,0,0,176) <= hud.map_limit)
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
                local centre=not rear and not (edge.from:match("^west_loop/") and edge.to:match("^west_loop/"))
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
        if nodes[edge.from].layer==0 and nodes[edge.to].layer==0 and edge.kind~="stairs" then
            local a,b=nodes[edge.from],nodes[edge.to]
            local steps=math.max(1,math.ceil(math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)/.1))
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
                                assert(top<=.43 or bottom>=1.925,"Blocked flank: "..edge.from.." by "..s.id)
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
        assert(math.abs(cover.height+cover.y-(shape.y+shape.h/2))<1e-7)
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
            if not b.arcade then
                local shop=shapes[b.id.."/shop/1"]
                if b.facade_axis=="z" then
                    assert((shop.z-b.z)*b.side>b.d/2)
                    assert(shop.x-shop.w/2>=b.x-b.w/2 and shop.x+shop.w/2<=b.x+b.w/2)
                else
                    assert((shop.x-b.x)*b.side>b.w/2)
                    assert(shop.z-shop.d/2>=b.z-b.d/2 and shop.z+shop.d/2<=b.z+b.d/2)
                end
            end
        end
    end
    -- Full-map bounds include terrain chunks, five flights and all background rows.
    assert(world.stats.batches<560 and world.stats.mesh_bytes<32*1024*1024)
    assert(#world.minimap<1240)
end)

-- Source layout.js / world_layout.h footprints, in metres. Keep the oracle
-- independent of the procedural recipes so missing or shifted rows fail.
test("full reference extent and all twenty footprints are present",function()
    local expected={
        W1={-13.5,15,14,10,2},W2={-14,-1.5,15,13,2},W3={-13,-19,13,14,2},
        W4={-14.5,-34.5,16,15,2},W5={-12.5,31,12,14,2},
        E1={14,16,15,16,3},E2={13.5,-5,14,14,3},E3={14,-22,15,16,2},
        E4={13.5,-39,14,14,3},E5={12.5,33,12,14,2},
        BW1={-30,8,16,22,3},BW2={-31,-18,18,24,2},BE1={31,18,18,20,3},
        BE2={32,-8,18,20,2},BE3={30,-34,16,18,3},
        BS1={-19,-58,20,14,3},BS2={14,-60,24,16,2},BS3={-4,-53,9,8,4},
        BN1={-16,50,20,14,2},BN2={14,52,22,16,3},
    }
    assert(layout.street.z_min==-58 and layout.street.z_max==46)
    assert(#layout.buildings==20 and #layout.routes==5)
    for _,b in ipairs(layout.buildings) do
        local e=assert(expected[b.id],b.id)
        for i,k in ipairs({"x","z","w","d","floors"}) do assert(b[k]==e[i],b.id.."/"..k) end
        expected[b.id]=nil
    end
    assert(next(expected)==nil)
end)

test("all intended floors have shared room audio, lighting and navigation",function()
    local world=generate(24)
    local nodes={}
    for _,n in ipairs(world.navigation.nodes) do nodes[n.id]=n end
    assert(#world.navigation.stairs==5 and #world.lighting_volumes==8)
    for _,id in ipairs({"W2/upper_room","E1/upper_room","E1/floor2/upper_room",
        "E2/upper_room","E2/floor2/upper_room","E3/room","E1/alley_door"}) do assert(nodes[id],id) end
    for _,n in ipairs(world.navigation.nodes) do
        assert(not n.id:match("^E3/") or n.layer==0,"E3 must not invent upstairs access")
        if n.id:match("/room$") or n.id:match("/upper_room$") then
            local contained=false
            for _,light in ipairs(world.lights) do
                if light.kind=="room" and n.x>=light.minimum.x and n.x<=light.maximum.x
                    and n.y>=light.minimum.y and n.y<=light.maximum.y
                    and n.z>=light.minimum.z and n.z<=light.maximum.z then contained=true end
            end
            assert(contained,"Room acoustic bounds missing: "..n.id)
        end
    end
end)

test("full-map minimap never loses distant geometry and fits the visible node pool",function()
    local world=generate(24)
    local hud=require "game.ui.hud"
    assert(#world.minimap>hud.map_limit,"Fixture must exercise more stored shapes than GUI nodes")
    local maximum=0
    for x=-84,84,4 do for z=-84,84,4 do
        for _,y in ipairs({0,3.345,6.545}) do
            maximum=math.max(maximum,#hud.map_visible(world.minimap,x,y,z,148))
        end
    end end
    for _,n in ipairs(world.navigation.nodes) do hud.map_visible(world.minimap,n.x,n.y,n.z,148) end
    assert(maximum>0 and maximum<=hud.map_limit)
    local tower
    for _,s in ipairs(world.minimap) do if s.id=="gate/tower" then tower=s end end
    assert(tower and hud.map_rect(tower,0,0,-42.5,148))
end)

test("spawn and patrol anchors have floor support and standing clearance",function()
    local world=generate(24)
    local points={layout.spawn}
    for _,p in ipairs(world.spawn_anchors) do points[#points+1]=p end
    for _,p in ipairs(world.spawn_points) do
        points[#points+1]=p.position
        if p.patrol then points[#points+1]=p.patrol end
    end
    for _,p in ipairs(points) do
        local supported=false
        for _,s in ipairs(world.colliders) do
            if math.abs(p.x-s.x)<=s.w/2+.32 and math.abs(p.z-s.z)<=s.d/2+.32 then
                assert(s.y+s.h/2<=p.y+.43 or s.y-s.h/2>=p.y+1.78,
                    "Blocked spawn/patrol by "..s.id)
            end
            if math.abs(p.x-s.x)<=s.w/2 and math.abs(p.z-s.z)<=s.d/2 then
                supported=supported or math.abs(s.y+s.h/2-p.y)<1e-7
            end
        end
        assert(supported,"Unsupported spawn/patrol")
    end
end)

test("architecture and all authored dressing families survive generation",function()
    local world=generate(24)
    local shapes={};for _,s in ipairs(world.shapes) do shapes[s.id]=s end
    for _,id in ipairs({"W2/detail/terrace","W1/detail/arch/1/1/0","E1/detail/balcony/1/1/slab",
        "E3/ruin/slab/back","W3/ruin/roof/remnant","E1/furnishing/storage",
        "W2/furnishing/shop_wall/lintel/1","gate/arch/0","gate/arch/15","gate/walkway",
        "stall/8/table","dressing/jersey/8/core","dressing/bags/4/core",
        "dressing/wreck/3/body","dressing/palm/7/frond/8","dressing/lamp/5/head",
        "dressing/cable/6/12","dressing/laundry/6/cloth/4","dressing/tyres/4/3",
        "dressing/rubble/5/14","dressing/courtyard/rug"}) do assert(shapes[id],id) end
    assert(not shapes["E3/upper/mass"] and not shapes["E3/coping"],"Ruin collapse filled in")
    assert(shapes["W2/coping"].w<15 and shapes["W2/floor"].w==15,"Missing setback")
    assert(shapes["gate/arch/0"].y-shapes["gate/arch/0"].h/2>2)
    assert(shapes["gate/arch/7"].y-shapes["gate/arch/7"].h/2>4)
    for _,s in ipairs(world.shapes) do
        if s.kind=="frond" then assert(not s.surface and s.material=="foliage") end
    end
    for _,b in ipairs(world.batches) do
        if b.material=="foliage" then
            for i=4,#b.colors,4 do assert(b.colors[i]==1,"Geometric leaflets must not use the broadleaf card mask") end
        end
    end
end)

test("curved and rotated decoration cannot cut rectangular holes in adjacent walls",function()
    local faces=require "game.world.visible_faces"
    local bounds={faces.bounds({x=0,y=0,z=0,w=2,h=2,d=2}),
        faces.bounds({x=1,y=0,z=0,w=2,h=2,d=2,kind="torus"}),
        faces.bounds({x=-1,y=0,z=0,w=2,h=2,d=2,rotation_y=.5})}
    assert(faces.for_box(2,bounds)==nil and faces.for_box(3,bounds)==nil)
    for _,rects in ipairs(faces.for_box(1,bounds)) do assert(#rects==1 and rects[1][1]==-1 and rects[1][3]==1) end
end)

print(count .. " world tests passed")
