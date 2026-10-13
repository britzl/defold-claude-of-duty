local config = require "game.config"
local events = require "game.events"
local input = require "game.input"
local combat = require "game.combat"
local presentation = require "game.presentation"

-- Explicit dependency order. Modules hold no mutable session state.
local systems = {
    require "game.systems.world",
    require "game.systems.player",
    require "game.systems.weapons",
    require "game.systems.ai",
    require "game.systems.fx",
    (require "game.systems.audio"),
}
local M = {}

function M.new()
    local ctx = {
        config = config, events = events.new(), input = input.new(),
        combat = combat.new(), presentation = presentation.new(),
        time = { tick = 0, elapsed = 0, frame = 0, frame_elapsed = 0,
            fixed_dt = 1 / config.fixed_frequency, remainder = 0, alpha = 0 },
    }
    for _, system in ipairs(systems) do system.init(ctx) end
    presentation.update(ctx)
    return ctx
end

function M.fixed_update(ctx, dt)
    local time = ctx.time
    time.tick = time.tick + 1
    time.elapsed = time.elapsed + dt
    time.fixed_dt = dt
    -- Observe Defold's steps for presentation only. Never step Bullet ourselves.
    time.remainder = time.remainder - dt
    combat.fixed_update(ctx)
    for _, system in ipairs(systems) do
        if system.fixed_update then system.fixed_update(ctx, dt) end
    end
    input.end_tick(ctx.input)
end

function M.update(ctx, dt)
    local time = ctx.time
    time.frame = time.frame + 1
    time.frame_elapsed = time.frame_elapsed + dt
    -- Defold calls fixed_update zero or more times before update each frame.
    time.remainder = time.remainder + dt
    time.alpha = math.max(0, math.min(1, time.remainder / time.fixed_dt))
    for _, system in ipairs(systems) do
        if system.update then system.update(ctx, dt) end
    end
    presentation.update(ctx)
end

function M.final(ctx)
    for i = #systems, 1, -1 do
        if systems[i].final then systems[i].final(ctx) end
    end
    input.reset(ctx.input)
    events.clear(ctx.events)
    ctx.combat.pending = {}
end

return M
