local interior = require "game.world.interior"
local architecture=require "game.world.architecture"
local kit=require "game.world.kit"
local M = {}

local box=kit.box

local function window(b, floor, z, base, storey, box)
    local front = b.x + b.side * b.w / 2
    local y = base + floor * storey + 1.8
    local prefix = b.id .. "/window/" .. floor .. "/" .. z
    box(prefix, "dark", front - b.side * .23, y, z, 0.04, 1.65, 1.25,"wood")
    box(prefix .. "/shutter", "shutters", front - b.side * .18, y, z+.3, 0.08, 1.5, .55,nil,nil,{unclipped=true})
    for _, sign in ipairs({ -1, 1 }) do
        box(prefix .. "/jamb/" .. sign, "trim", front + b.side * 0.08, y, z + sign * 0.7, 0.16, 1.85, 0.14)
    end
    box(prefix .. "/sill", "trim", front + b.side * 0.15, y - 0.9, z, 0.4, 0.16, 1.55)
    box(prefix .. "/lintel", "trim", front + b.side * 0.08, y + 0.9, z, 0.18, 0.16, 1.55)
end

local function awning(id, x, y, z, width, depth, side)
    side = side or 1
    local variant=0
    for i=1,#id do variant=variant+id:byte(i) end
    local colour=({"awning_red","awning_sage","awning_blue"})[variant%3+1]
    local sag=.10+(variant%4)*.025
    local strips = math.ceil(depth / 0.3)
    for i = 1, strips do
        local key = i % 3 == 0 and "awning_cream" or colour
        local sz = z - depth / 2 + (i - 0.5) * depth / strips
        -- Four shallow cloth spans share their edges and hang between supports.
        -- Convex profiles preserve both native/Lua triangulation and shadows.
        local function height(t) return y+.025-sag*4*t*(1-t)-.045*(i-1)/strips end
        for j=1,4 do
            local a,b=(j-1)/4,j/4
            local xa,xb=x-width/2+a*width,x-width/2+b*width
            local ya,yb=height(a),height(b)
            kit.prism(id.."/stripe/"..i.."/"..j,key,
                {{xa,ya-.018},{xb,yb-.018},{xb,yb+.018},{xa,ya+.018}},sz,depth/strips)
        end
        local hem=.15+.055*math.sin(i*1.7+variant)
        box(id .. "/valance/" .. i, key, x + side * (width / 2 - .015), height(1)-hem/2, sz, .03, hem, depth / strips)
    end
end

local function building(layout, b, emit)
    local box = emit or box
    local base, wall, slab, storey = layout.street.walk_height, layout.wall, layout.slab, layout.storey
    local x0, x1, z0, z1 = b.x - b.w / 2, b.x + b.w / 2, b.z - b.d / 2, b.z + b.d / 2
    local height = b.floors * storey
    -- Slabs own the top of each storey. X walls own the corners; Z walls
    -- butt against them. Overlapping faces used to depend on batch draw order.
    local wall_height = storey - slab
    if b.room then
        assert(b.side == 1 or b.side == -1)
        local front = b.x+b.side*(b.w/2-wall/2)
        local facade = b.x+b.side*b.w/2
        -- Split the street-facing wall around a true doorway on either side.
        box(b.id .. "/floor", "concrete_floor", b.x, base - slab / 2, b.z, b.w, slab, b.d, "concrete")
        box(b.id .. (b.side == 1 and "/west" or "/east"), "plaster_inside", b.x-b.side*(b.w/2-wall/2), base + wall_height / 2, b.z, wall, wall_height, b.d, "plaster")
        box(b.id .. "/north", b.material, b.x, base + wall_height / 2, z1 - wall / 2, b.w-2*wall, wall_height, wall, "plaster")
        if b.secondary_door then
            local door=b.secondary_door
            local lo,hi=door.x-door.width/2,door.x+door.width/2
            box(b.id.."/south/left",b.material,(x0+wall+lo)/2,base+wall_height/2,z0+wall/2,lo-x0-wall,wall_height,wall,"plaster")
            box(b.id.."/south/right",b.material,(hi+x1-wall)/2,base+wall_height/2,z0+wall/2,x1-wall-hi,wall_height,wall,"plaster")
            box(b.id.."/south/lintel",b.material,door.x,base+(wall_height+door.height)/2,z0+wall/2,door.width,wall_height-door.height,wall,"plaster")
        else
            box(b.id .. "/south", b.material, b.x, base + wall_height / 2, z0 + wall / 2, b.w-2*wall, wall_height, wall, "plaster")
        end
        local door = b.door
        local lo, hi = door.z - door.width / 2, door.z + door.width / 2
        box(b.id .. "/front_left", b.material, front, base + wall_height / 2, (z0 + lo) / 2, wall, wall_height, lo - z0, "plaster")
        box(b.id .. "/front_right", b.material, front, base + wall_height / 2, (hi + z1) / 2, wall, wall_height, z1 - hi, "plaster")
        box(b.id .. "/door_lintel", b.material, front, base + (wall_height + door.height) / 2,
            door.z, wall, wall_height - door.height, door.width, "plaster")
        interior.geometry(layout, b, box)
        local counter, shelves = b.counter, b.shelves
        if counter then
            local counter_x, counter_z = x0 + counter.x * b.w, z0 + counter.z * b.d
            box(b.id .. "/counter", "wood", counter_x, base + 0.45, counter_z, counter.w, 0.9, counter.d, "wood")
            box(b.id .. "/counter_top", "tile", counter_x, base + 0.93, counter_z, counter.w + 0.1, 0.06, counter.d + 0.1)
        end
        if shelves then
            for i = 1, 3 do
                box(b.id .. "/shelf/" .. i, "wood", x0 + shelves.x * b.w, base + i * 0.6, z0 + shelves.z * b.d, shelves.w, 0.09, shelves.d)
            end
        end
        local a=interior.awning(layout,b)
        awning(b.id .. "/awning",a.x,a.y,a.z,a.w,a.d,a.side)
        for _, sign in ipairs({ -1, 1 }) do
            box(b.id .. "/door_frame/" .. sign, "wood", facade + b.side * 0.08, base + door.height / 2,
                door.z + sign * (door.width / 2 + 0.07), 0.16, door.height, 0.14)
        end
    else
        -- Closed footprints meet road-level alleys as well as raised pavements.
        if b.arcade then
            box(b.id.."/mass",b.material,b.x-b.side*b.arcade/2,(base+storey-slab)/2,b.z,
                b.w-b.arcade,base+storey-slab,b.d,"plaster")
            box(b.id.."/upper/mass",b.material,b.x-b.side*.2,base+(storey-slab+height)/2,b.z,
                b.w-.4,height-storey+slab,b.d,"plaster")
            for level=1,b.floors-1 do architecture.window_wall(layout,b,level,box) end
        else
            box(b.id .. "/mass", b.material, b.x, (base + storey) / 2, b.z, b.w, base + storey, b.d, "plaster")
            for level=1,b.floors-1 do
                local f=architecture.floor_spec(b,level)
                if not b.ruin then
                    box(b.id.."/mass/"..level,b.material,f.x-b.side*.2,base+(level+.5)*storey,b.z,f.w-.4,storey,b.d,"plaster")
                    architecture.window_wall(layout,f,level,box)
                end
            end
        end
        -- Closed shops face the street on either side and fit the footprint.
        local front, bays = b.x+b.side*b.w/2, math.max(1,math.floor(b.d/4))
        for i = 1, b.arcade and 0 or bays do
            local z = z0 + (i-.5)*b.d/bays
            box(b.id .. "/shop/" .. i, "metal_painted", front+b.side*.025, base + 1.25, z, 0.06, 2.5, 2.9)
            for j = 1, 10 do
                box(b.id .. "/slat/" .. i .. "/" .. j, "shutters", front+b.side*.065, base + j * 0.23, z, 0.06, 0.035, 2.85)
            end
        end
    end
    for floor = 1, b.floors - 1 do
        local f=architecture.floor_spec(b,floor)
        if b.room then
            -- Exterior trim must not span the open stairwell like the old solid facade.
            for _, sign in ipairs({-1,1}) do
                box(b.id.."/belt/"..floor.."/x/"..sign,"trim",f.x+sign*f.w/2,base+floor*storey,b.z,.2,.18,b.d+.2)
                box(b.id.."/belt/"..floor.."/z/"..sign,"trim",f.x,base+floor*storey,b.z+sign*b.d/2,f.w-.2,.18,.2)
            end
        else
            box(b.id .. "/belt/" .. floor, "trim", f.x, base + floor * storey, b.z, f.w + 0.2, 0.18, b.d + 0.2)
        end
        if not b.ruin then for i = 1, 4 do window(f, floor, z0 + (i - 0.5) * b.d / 4, base, storey, box) end end
    end
    if b.ruin then return end
    b=architecture.floor_spec(b,b.floors-1)
    box(b.id .. "/coping", "trim", b.x, base + height + 0.07, b.z, b.w + 0.25, 0.14, b.d + 0.25)
    for _, sign in ipairs({ -1, 1 }) do
        box(b.id .. "/parapet_x/" .. sign, b.material, b.x + sign * (b.w / 2 - 0.13), base + height + 0.4, b.z, 0.26, 0.7, b.d, "plaster")
        box(b.id .. "/parapet_z/" .. sign, b.material, b.x, base + height + 0.4, b.z + sign * (b.d / 2 - 0.13), b.w-.52, 0.7, 0.26, "plaster")
    end
end

local function structure(layout, detail, seed)
    local random=require("game.rng").new(seed or layout.seed,"dressing")
    local s = layout.street
    -- Ground is tiled into chunks, not a single enormous culling bound.
    for z = s.z_min, s.z_max - 0.001, 7 do
        local depth = math.min(7, s.z_max - z)
        box("road/" .. z, "asphalt", 0, -0.15, z + depth / 2, 2 * s.half_width, 0.3, depth, "concrete")
        for _, side in ipairs({ -1, 1 }) do
            local width = s.kerb - s.half_width
            box("walk/" .. side .. "/" .. z, "concrete_floor", side * (s.half_width + width / 2),
                s.walk_height / 2 - 0.1, z + depth / 2, width, s.walk_height + 0.2, depth, "concrete")
        end
    end
    for _, ground in ipairs(layout.ground or {}) do
        for x = ground.x0, ground.x1-.001, 7 do
            for z = ground.z0, ground.z1-.001, 7 do
                local w,d = math.min(7,ground.x1-x),math.min(7,ground.z1-z)
                box("ground/"..ground.id.."/"..x.."/"..z,ground.material,x+w/2,ground.y-.15,z+d/2,w,.3,d,ground.surface)
            end
        end
    end
    local terrain=layout.terrain
    if terrain then
        for x=terrain.x0,terrain.x1-.001,layout.chunk_size do
            for z=terrain.z0,terrain.z1-.001,layout.chunk_size do
                local w,d=math.min(layout.chunk_size,terrain.x1-x),math.min(layout.chunk_size,terrain.z1-z)
                box("terrain/"..x.."/"..z,"sand",x+w/2,-.15,z+d/2,w,.3,d,"sand")
            end
        end
        -- Visible boundary walls prevent falling off the finite terrain.
        for _,side in ipairs({-1,1}) do
            box("boundary/terrain/x/"..side,"brick",side<0 and terrain.x0 or terrain.x1,1.5,(terrain.z0+terrain.z1)/2,.4,3,terrain.z1-terrain.z0,"plaster")
            box("boundary/terrain/z/"..side,"brick",(terrain.x0+terrain.x1)/2,1.5,side<0 and terrain.z0 or terrain.z1,terrain.x1-terrain.x0,3,.4,"plaster")
        end
    end
    for _, b in ipairs(layout.buildings) do
        if b.facade_axis=="z" then
            local rotated={}
            for k,v in pairs(b) do rotated[k]=v end
            rotated.x,rotated.z,rotated.w,rotated.d=b.z,b.x,b.d,b.w
            building(layout,rotated,function(id,material,x,y,z,w,h,d,surface,cover,extra)
                box(id,material,z,y,x,d,h,w,surface,cover,extra)
            end)
        else
            building(layout,b)
        end
        architecture.details(layout,b,detail,random)
    end
    architecture.gate(layout,detail)
    for _, wall in ipairs(layout.walls or {}) do
        box("boundary/"..wall.id,"brick",wall.x,wall.h/2,wall.z,wall.w,wall.h,wall.d,"plaster")
    end
    for i, stall in ipairs(layout.stalls) do
        local id = "stall/" .. i
        local depth=stall.d or 1.15
        box(id .. "/table", "wood", stall.x, .84, stall.z, stall.w, .12, depth, "wood")
        for _,x in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
            box(id.."/leg/"..x.."/"..z,"wood",stall.x+x*(stall.w/2-.06),.4,stall.z+z*(depth/2-.06),.1,.8,.1,"wood")
        end end
        awning(id .. "/canopy", stall.x, 2.35, stall.z, stall.w + 0.15, depth+.45)
        for _, sign in ipairs({ -1, 1 }) do
            box(id .. "/post/" .. sign, "wood", stall.x + sign * (stall.w / 2 - 0.05), 1.2, stall.z - depth/2-.025, 0.08, 2.4, 0.08)
        end
    end
    for i, crate in ipairs(layout.crates) do
        local base = crate.y or s.walk_height
        local cover = {normal_x=crate.normal_x or -1,normal_z=crate.normal_z or 0}
        box("crate/" .. i, "wood", crate.x, base + 0.5, crate.z, 0.95, 1, 0.95, "wood", cover)
        if detail then
            for _, sign in ipairs({ -1, 1 }) do
                box("crate/" .. i .. "/strap/" .. sign, "metal_rust", crate.x, base + 0.5, crate.z + sign * 0.32, 0.97, 1.02, 0.055)
            end
        end
    end
    for _, cover in ipairs(layout.covers or {}) do
        box("cover/"..cover.id,"concrete",cover.x,(cover.y or 0)+cover.h/2,cover.z,
            cover.w,cover.h,cover.d,"concrete",cover)
    end
end

function M.generate(layout,detail,seed)
    -- Give suspended dressing the actual generated walls, including recesses,
    -- openings and ruins, rather than inferring a facade from its footprint.
    local supports={}
    local job=coroutine.create(function() structure(layout,detail,seed) end)
    while coroutine.status(job)~="dead" do
        local ok,shape=coroutine.resume(job)
        assert(ok,shape)
        if shape then
            if shape.surface=="plaster" and not shape.kind then supports[#supports+1]=shape end
            coroutine.yield(shape)
        end
    end
    require("game.world.dressing").generate(layout,detail,seed,supports)
end

return M
