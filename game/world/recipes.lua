local M = {}

local function box(id, material, x, y, z, w, h, d, surface)
    assert(w > 0 and h > 0 and d > 0, "Invalid box: " .. id)
    coroutine.yield({ id = id, material = material, x = x, y = y, z = z,
        w = w, h = h, d = d, surface = surface })
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

local function awning(id, x, y, z, width, depth)
    local strips = math.ceil(depth / 0.3)
    for i = 1, strips do
        local key = i % 2 == 0 and "awning_red" or "awning_cream"
        local sz = z - depth / 2 + (i - 0.5) * depth / strips
        box(id .. "/stripe/" .. i, key, x, y, sz, width, 0.07, depth / strips)
        box(id .. "/valance/" .. i, key, x + width / 2 - 0.04, y - 0.17, sz, 0.08, 0.34, depth / strips)
    end
end

local function building(layout, b)
    local base, wall, slab, storey = layout.street.walk_height, layout.wall, layout.slab, layout.storey
    local x0, x1, z0, z1 = b.x - b.w / 2, b.x + b.w / 2, b.z - b.d / 2, b.z + b.d / 2
    local height = b.floors * storey
    if b.room then
        assert(b.side == 1, "The first room recipe opens on the east side")
        -- Floor top coincides with the pavement. Walls are separate solids;
        -- splitting the east wall leaves the doorway open all the way through.
        box(b.id .. "/floor", "concrete", b.x, base - slab / 2, b.z, b.w, slab, b.d, "concrete")
        box(b.id .. "/west", "plaster_inside", x0 + wall / 2, base + storey / 2, b.z, wall, storey, b.d, "plaster")
        box(b.id .. "/north", b.material, b.x, base + storey / 2, z1 - wall / 2, b.w, storey, wall, "plaster")
        box(b.id .. "/south", b.material, b.x, base + storey / 2, z0 + wall / 2, b.w, storey, wall, "plaster")
        local door = b.door
        local lo, hi = door.z - door.width / 2, door.z + door.width / 2
        box(b.id .. "/front_left", b.material, x1 - wall / 2, base + storey / 2, (z0 + lo) / 2, wall, storey, lo - z0, "plaster")
        box(b.id .. "/front_right", b.material, x1 - wall / 2, base + storey / 2, (hi + z1) / 2, wall, storey, z1 - hi, "plaster")
        box(b.id .. "/door_lintel", b.material, x1 - wall / 2, base + (storey + door.height) / 2,
            door.z, wall, storey - door.height, door.width, "plaster")
        box(b.id .. "/upper", b.material, b.x, base + storey + (height - storey) / 2,
            b.z, b.w, height - storey, b.d, "plaster")
        local counter, shelves = b.counter, b.shelves
        local counter_x, counter_z = x0 + counter.x * b.w, z0 + counter.z * b.d
        box(b.id .. "/counter", "wood", counter_x, base + 0.45, counter_z, counter.w, 0.9, counter.d, "wood")
        box(b.id .. "/counter_top", "trim", counter_x, base + 0.93, counter_z, counter.w + 0.1, 0.06, counter.d + 0.1)
        for i = 1, 3 do
            box(b.id .. "/shelf/" .. i, "wood", x0 + shelves.x * b.w, base + i * 0.6, z0 + shelves.z * b.d, shelves.w, 0.09, shelves.d)
        end
        awning(b.id .. "/awning", x1 + 0.85, base + 2.95, door.z, 1.7, 4.4)
        for _, sign in ipairs({ -1, 1 }) do
            box(b.id .. "/door_frame/" .. sign, "wood", x1 + 0.015, base + door.height / 2,
                door.z + sign * (door.width / 2 + 0.07), 0.16, door.height, 0.14)
        end
    else
        box(b.id .. "/mass", b.material, b.x, base + height / 2, b.z, b.w, height, b.d, "plaster")
        -- Closed ground-floor shops in the opposing facade.
        for i = 1, 3 do
            local z = z0 + 2 + (i - 1) * 4.4
            box(b.id .. "/shop/" .. i, "metal", x0 - 0.025, base + 1.25, z, 0.06, 2.5, 2.9)
            for j = 1, 10 do
                box(b.id .. "/slat/" .. i .. "/" .. j, "shutters", x0 - 0.065, base + j * 0.23, z, 0.06, 0.035, 2.85)
            end
        end
    end
    for floor = 1, b.floors - 1 do
        box(b.id .. "/belt/" .. floor, "trim", b.x, base + floor * storey, b.z, b.w + 0.2, 0.18, b.d + 0.2)
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
    for _, b in ipairs(layout.buildings) do building(layout, b) end
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
        local base = s.walk_height
        box("crate/" .. i, "wood", crate.x, base + 0.5, crate.z, 0.95, 1, 0.95, "wood")
        if detail then
            for _, sign in ipairs({ -1, 1 }) do
                box("crate/" .. i .. "/strap/" .. sign, "metal", crate.x, base + 0.5, crate.z + sign * 0.32, 0.97, 1.02, 0.055)
            end
        end
    end
    -- One cover solid, dimensions also feed the cover and minimap output.
    box("cover/barrier", "concrete", 1.6, 0.45, -2.5, 0.6, 0.9, 2.5, "concrete")
end

return M
