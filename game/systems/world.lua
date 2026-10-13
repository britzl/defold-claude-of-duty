local generator = require "game.world.generator"
local layout = require "game.world.layout"
local M = {}

function M.init(ctx)
    ctx.world = generator.new(layout)
    ctx.world.adapter = ctx.services.world
    ctx.world.cursor = 1
    ctx.world.work_seconds = 0
    ctx.world.peak_job_seconds = 0
end

function M.update(ctx, dt)
    local world = ctx.world
    if world.ready then return end
    local started = os.clock()
    local deadline = started + 0.002
    local adapter = world.adapter
    if world.phase == "geometry" then
        generator.step(world, 24, deadline, os.clock)
    elseif world.phase == "meshes" then
        local batch = world.batches[world.cursor]
        if batch then
            if adapter then adapter.api.add_batch(adapter, batch) end
            world.cursor = world.cursor + 1
        else
            world.phase, world.cursor = "collision", 1
        end
    elseif world.phase == "collision" then
        for _ = 1, 8 do
            if os.clock() >= deadline then break end
            local shape = world.colliders[world.cursor]
            if not shape then world.phase = "settle"; break end
            if adapter then adapter.api.add_collision(adapter, shape) end
            world.cursor = world.cursor + 1
        end
    elseif world.phase == "settle" then
        -- Factory-created collision objects have entered the physics world.
        if not ctx.audio or ctx.audio.ready then world.phase, world.ready = "ready", true end
    end
    local elapsed = os.clock() - started
    world.work_seconds = world.work_seconds + elapsed
    world.peak_job_seconds = math.max(world.peak_job_seconds, elapsed)
end

function M.final(ctx)
    if ctx.world.adapter then ctx.world.adapter.api.final(ctx.world.adapter) end
    ctx.world = nil
end

return M
