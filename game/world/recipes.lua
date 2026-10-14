local interior = require "game.world.interior"
local M = {}

local function box(id, material, x, y, z, w, h, d, surface, cover)
    assert(w > 0 and h > 0 and d > 0, "Invalid box: " .. id)
    coroutine.yield({ id = id, material = material, x = x, y = y, z = z,
        w = w, h = h, d = d, surface = surface, cover = cover })
end

local function window(b, floor, z, base, storey)
    local front = b.x + b.side * b.w / 2
    local y = base + floor * storey + 1.8
    local prefix = b.id .. "/window/" .. floor .. "/" .. z
    box(prefix, "dark", front + b.side * 0.025, y, z, 0.06, 1.65, 1.25)
    box(prefix .. "/shutter", "shutters", front + b.side * 0.07, y, z, 0.06, 1.5, 1.1)
    for _, sign in ipairs({ -1, 1 }) do
        box(prefix .. "/jamb/" .. sign, "trim", front + b.side * 0.08, y, z + sign * 0.7, 0.16, 1.85, 0.14)
    end
    box(prefix .. "/sill", "trim", front + b.side * 0.15, y - 0.9, z, 0.4, 0.16, 1.55)
    box(prefix .. "/lintel", "trim", front + b.side * 0.08, y + 0.9, z, 0.18, 0.16, 1.55)
end

local function awning(id, x, y, z, width, depth, side)
    side = side or 1
    local strips = math.ceil(depth / 0.3)
    for i = 1, strips do
        local key = i % 2 == 0 and "awning_red" or "awning_cream"
        local sz = z - depth / 2 + (i - 0.5) * depth / strips
        box(id .. "/stripe/" .. i, key, x, y, sz, width, 0.07, depth / strips)
        box(id .. "/valance/" .. i, key, x + side * (width / 2 - 0.04), y - 0.17, sz, 0.08, 0.34, depth / strips)
    end
end

local function building(layout, b)
    local base, wall, slab, storey = layout.street.walk_height, layout.wall, layout.slab, layout.storey
    local x0, x1, z0, z1 = b.x - b.w / 2, b.x + b.w / 2, b.z - b.d / 2, b.z + b.d / 2
    local height = b.floors * storey
    if b.room then
        assert(b.side == 1 or b.side == -1)
        local front = b.x+b.side*(b.w/2-wall/2)
        local facade = b.x+b.side*b.w/2
        -- Split the street-facing wall around a true doorway on either side.
        box(b.id .. "/floor", "concrete", b.x, base - slab / 2, b.z, b.w, slab, b.d, "concrete")
        box(b.id .. (b.side == 1 and "/west" or "/east"), "plaster_inside", b.x-b.side*(b.w/2-wall/2), base + storey / 2, b.z, wall, storey, b.d, "plaster")
        box(b.id .. "/north", b.material, b.x, base + storey / 2, z1 - wall / 2, b.w, storey, wall, "plaster")
        box(b.id .. "/south", b.material, b.x, base + storey / 2, z0 + wall / 2, b.w, storey, wall, "plaster")
        local door = b.door
        local lo, hi = door.z - door.width / 2, door.z + door.width / 2
        box(b.id .. "/front_left", b.material, front, base + storey / 2, (z0 + lo) / 2, wall, storey, lo - z0, "plaster")
        box(b.id .. "/front_right", b.material, front, base + storey / 2, (hi + z1) / 2, wall, storey, z1 - hi, "plaster")
        box(b.id .. "/door_lintel", b.material, front, base + (storey + door.height) / 2,
            door.z, wall, storey - door.height, door.width, "plaster")
        interior.geometry(layout, b, box)
        local counter, shelves = b.counter, b.shelves
        local counter_x, counter_z = x0 + counter.x * b.w, z0 + counter.z * b.d
        box(b.id .. "/counter", "wood", counter_x, base + 0.45, counter_z, counter.w, 0.9, counter.d, "wood")
        box(b.id .. "/counter_top", "trim", counter_x, base + 0.93, counter_z, counter.w + 0.1, 0.06, counter.d + 0.1)
        for i = 1, 3 do
            box(b.id .. "/shelf/" .. i, "wood", x0 + shelves.x * b.w, base + i * 0.6, z0 + shelves.z * b.d, shelves.w, 0.09, shelves.d)
        end
        awning(b.id .. "/awning", facade + b.side * 0.85, base + 2.95, door.z, 1.7, 4.4, b.side)
        for _, sign in ipairs({ -1, 1 }) do
            box(b.id .. "/door_frame/" .. sign, "wood", facade + b.side * 0.015, base + door.height / 2,
                door.z + sign * (door.width / 2 + 0.07), 0.16, door.height, 0.14)
        end
    else
        -- Closed footprints meet road-level alleys as well as raised pavements.
        box(b.id .. "/mass", b.material, b.x, (base + height) / 2, b.z, b.w, base + height, b.d, "plaster")
        -- Closed shops face the street on either side and fit the footprint.
        local front, bays = b.x+b.side*b.w/2, math.max(1,math.floor(b.d/4))
        for i = 1, bays do
            local z = z0 + (i-.5)*b.d/bays
            box(b.id .. "/shop/" .. i, "metal", front+b.side*.025, base + 1.25, z, 0.06, 2.5, 2.9)
            for j = 1, 10 do
                box(b.id .. "/slat/" .. i .. "/" .. j, "shutters", front+b.side*.065, base + j * 0.23, z, 0.06, 0.035, 2.85)
            end
        end
    end
    for floor = 1, b.floors - 1 do
        if b.room then
            -- Exterior trim must not span the open stairwell like the old solid facade.
            for _, sign in ipairs({-1,1}) do
                box(b.id.."/belt/"..floor.."/x/"..sign,"trim",b.x+sign*b.w/2,base+floor*storey,b.z,.2,.18,b.d+.2)
                box(b.id.."/belt/"..floor.."/z/"..sign,"trim",b.x,base+floor*storey,b.z+sign*b.d/2,b.w,.18,.2)
            end
        else
            box(b.id .. "/belt/" .. floor, "trim", b.x, base + floor * storey, b.z, b.w + 0.2, 0.18, b.d + 0.2)
        end
        for i = 1, 4 do window(b, floor, z0 + (i - 0.5) * b.d / 4, base, storey) end
    end
    box(b.id .. "/coping", "trim", b.x, base + height + 0.07, b.z, b.w + 0.25, 0.14, b.d + 0.25)
    for _, sign in ipairs({ -1, 1 }) do
        box(b.id .. "/parapet_x/" .. sign, b.material, b.x + sign * (b.w / 2 - 0.13), base + height + 0.4, b.z, 0.26, 0.7, b.d, "plaster")
        box(b.id .. "/parapet_z/" .. sign, b.material, b.x, base + height + 0.4, b.z + sign * (b.d / 2 - 0.13), b.w, 0.7, 0.26, "plaster")
    end
end

function M.generate(layout, detail)
    local s = layout.street
    -- Ground is tiled into chunks, not a single enormous culling bound.
    for z = s.z_min, s.z_max - 0.001, 7 do
        local depth = math.min(7, s.z_max - z)
        box("road/" .. z, "asphalt", 0, -0.15, z + depth / 2, 2 * s.half_width, 0.3, depth, "concrete")
        for _, side in ipairs({ -1, 1 }) do
            local width = s.kerb - s.half_width
            box("walk/" .. side .. "/" .. z, "concrete", side * (s.half_width + width / 2),
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
    for _, b in ipairs(layout.buildings) do building(layout, b) end
    for _, wall in ipairs(layout.walls or {}) do
        box("boundary/"..wall.id,"plaster_sand",wall.x,wall.h/2,wall.z,wall.w,wall.h,wall.d,"plaster")
    end
    for i, stall in ipairs(layout.stalls) do
        local id = "stall/" .. i
        box(id .. "/table", "wood", stall.x, 0.45, stall.z, stall.w, 0.9, 1.15, "wood")
        awning(id .. "/canopy", stall.x, 2.35, stall.z, stall.w + 0.15, 1.6)
        for _, sign in ipairs({ -1, 1 }) do
            box(id .. "/post/" .. sign, "wood", stall.x + sign * (stall.w / 2 - 0.05), 1.2, stall.z - 0.6, 0.08, 2.4, 0.08)
        end
        if detail then
            for j = 1, 8 do
                box(id .. "/produce/" .. j, "produce", stall.x - stall.w / 2 + j * stall.w / 9, 0.99, stall.z, 0.16, 0.18, 0.5)
            end
        end
    end
    for i, crate in ipairs(layout.crates) do
        local base = crate.y or s.walk_height
        local cover = {normal_x=crate.normal_x or -1,normal_z=crate.normal_z or 0}
        box("crate/" .. i, "wood", crate.x, base + 0.5, crate.z, 0.95, 1, 0.95, "wood", cover)
        if detail then
            for _, sign in ipairs({ -1, 1 }) do
                box("crate/" .. i .. "/strap/" .. sign, "metal", crate.x, base + 0.5, crate.z + sign * 0.32, 0.97, 1.02, 0.055)
            end
        end
    end
    for _, cover in ipairs(layout.covers or {}) do
        box("cover/"..cover.id,"concrete",cover.x,(cover.y or 0)+cover.h/2,cover.z,
            cover.w,cover.h,cover.d,"concrete",cover)
    end
end

return M
