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
    -- Loading has its own budget; cheap jobs should fill it instead of waiting
    -- a frame after just a handful of objects. Individual uploads are sliced.
    local deadline = started + 0.004
    local adapter = world.adapter
    if profiler then profiler.scope_begin("loading.world." .. world.phase) end
    if world.phase == "geometry" then
        generator.step(world, 4096, deadline, os.clock)
    elseif world.phase == "meshes" then
        for _ = 1, 128 do
            if os.clock() >= deadline then break end
            local batch = world.batches[world.cursor]
            if not batch then world.phase, world.cursor = "collision", 1; break end
            local complete=true
            if adapter then
                if adapter.api.step_batch then complete=adapter.api.step_batch(adapter,batch,512)
                else adapter.api.add_batch(adapter, batch) end
            end
            if complete then world.cursor = world.cursor + 1 end
        end
    elseif world.phase == "collision" then
        for _ = 1, 128 do
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
    if profiler then profiler.scope_end() end
    local elapsed = os.clock() - started
    world.work_seconds = world.work_seconds + elapsed
    world.peak_job_seconds = math.max(world.peak_job_seconds, elapsed)
end

function M.final(ctx)
    if ctx.world.adapter then ctx.world.adapter.api.final(ctx.world.adapter) end
    ctx.world = nil
end

return M
