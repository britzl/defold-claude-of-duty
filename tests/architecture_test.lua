package.path = "./?.lua;" .. package.path
local layout = require "game.world.layout"
local recipes = require "game.world.recipes"

local function check_patches(seed)
    local walls, patches, buildings = {}, {}, {}
    for _, b in ipairs(layout.buildings) do
        buildings[b.id], walls[b.id] = b, {}
    end
    local job = coroutine.create(function() recipes.generate(layout, true, seed) end)
    while coroutine.status(job) ~= "dead" do
        local ok, shape = coroutine.resume(job)
        assert(ok, shape)
        if shape then
            local id = shape.id:match("^([^/]+)")
            if shape.surface == "plaster" and walls[id] then
                walls[id][#walls[id]+1] = shape
            end
            if shape.id:find("/detail/spall/", 1, true) then patches[#patches+1] = shape end
        end
    end

    local function inside_wall(id, x, y, z)
        for _, wall in ipairs(walls[id]) do
            if math.abs(x-wall.x) <= wall.w/2 and math.abs(y-wall.y) <= wall.h/2
                and math.abs(z-wall.z) <= wall.d/2 then return true end
        end
        return false
    end

    local count = {}
    for _, patch in ipairs(patches) do
        local id = patch.id:match("^([^/]+)")
        local side = buildings[id].side
        count[id] = (count[id] or 0)+1
        local c, s = math.cos(patch.rotation_x or 0), math.sin(patch.rotation_x or 0)
        -- Probe the centre, edges and corners on both sides of the thin patch.
        -- Actual structural boxes must back the whole rotated patch, with its
        -- outward face exposed. This also rejects patches buried in a setback
        -- building or bridging an open doorway.
        for _, dy in ipairs({-.5, 0, .5}) do
            for _, dz in ipairs({-.5, 0, .5}) do
                local y = patch.y+dy*patch.h*c-dz*patch.d*s
                local z = patch.z+dy*patch.h*s+dz*patch.d*c
                local message = patch.id .. " seed=" .. seed
                assert(inside_wall(id, patch.x-side*.02, y, z), "Unsupported brick patch: " .. message)
                assert(not inside_wall(id, patch.x+side*.02, y, z), "Buried brick patch: " .. message)
            end
        end
    end
    for _, b in ipairs(layout.buildings) do
        if not b.ruin and b.facade_axis ~= "z" then
            assert(count[b.id] == 4, "Missing brick decoration on " .. b.id)
        end
    end
    return #patches
end

local checked = check_patches(layout.seed)
print("PASS all " .. checked .. " brick patches attach to their building's exterior walls")
for seed = 1, 32 do check_patches(seed) end
print("PASS arcade, setback and doorway attachment across 32 additional seeds")
