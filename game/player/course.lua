-- Separate optional traversal fixture, away from the authored street.
local mesh = require "game.world.mesh"
local adapter_api = require "game.world.defold"
local M = {}

function M.create()
    local adapter = adapter_api.new("#world_mesh", "#world_collision")
    local batches = {}
    local function box(id, x, y, z, w, h, d, rotation)
        local material = id == "floor" and "concrete" or "plaster_blue"
        local shape = { id = "course/"..id, x = x, y = y, z = z, w = w, h = h, d = d,
            rotation_x = rotation, material = material, surface = "concrete" }
        local batch = batches[material]
        if not batch then batch = mesh.new(material, material, 0, 0); batches[material] = batch end
        mesh.box(batch, shape, 1)
        adapter_api.add_collision(adapter, shape)
    end
    box("floor", 78, -0.15, -7, 68, 0.3, 28)
    box("thin_wall", 50, 1.5, -4, 4, 3, 0.1)
    box("corner", 48, 1.5, -2, 0.1, 3, 4)
    for i = 1, 3 do box("step/"..i, 56, i*0.1, -3.5-(i-1), 4, i*0.2, 1) end
    box("high_step", 62, 0.325, -4, 4, 0.65, 2)
    box("slope_30", 70, 1.5, -5, 4, 0.2, 6, math.rad(30))
    box("slope_60", 78, 3*math.sin(math.rad(60)), -5, 4, 0.2, 6, math.rad(60))
    box("low_ceiling", 86, 2.125, -4, 4, 1.75, 4)
    -- A second row supplies high ledges, insufficient headroom, and narrow
    -- tops. It stays clear of the original capsule regression lanes.
    box("mantle", 56, 0.6, -15, 4, 1.2, 3)
    box("mantle_high", 62, 0.9, -15, 4, 1.8, 3)
    box("mantle_too_high", 70, 1.35, -15, 4, 2.7, 3)
    box("mantle_roof_base", 78, 0.6, -15, 4, 1.2, 3)
    box("mantle_roof", 78, 2.65, -15, 4, 1, 3)
    box("mantle_crouch_base", 86, 0.6, -15, 4, 1.2, 3)
    box("mantle_crouch_roof", 86, 2.725, -15, 4, 0.25, 3)
    box("mantle_thin", 94, 0.6, -14, 4, 1.2, 0.15)
    box("mantle_beam_base", 102, 0.6, -15, 4, 1.2, 3)
    box("mantle_approach_beam", 102, 2.025, -12.9, 4, 0.25, 0.6)
    for _, spec in ipairs({ { x = 94, gap = 0.55 }, { x = 102, gap = 1.1 } }) do
        for _, side in ipairs({ -1, 1 }) do
            box("door/"..spec.x.."/"..side, spec.x+side*(spec.gap/2+1), 1.5, -4, 2, 3, 0.2)
        end
    end
    for _, batch in pairs(batches) do adapter_api.add_batch(adapter, batch) end
    return adapter
end

function M.final(adapter) adapter_api.final(adapter) end
return M
