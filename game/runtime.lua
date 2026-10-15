local config = require "game.config"
local events = require "game.events"
local input = require "game.input"
local combat = require "game.combat"
local presentation = require "game.presentation"
local hud = require "game.ui.hud"
local audio = require "game.systems.audio"

-- Explicit dependency order. Modules hold no mutable session state.
local systems = {
    require "game.systems.world",
    require "game.systems.player",
    require "game.systems.weapons",
    require "game.systems.ai",
    require "game.systems.fx",
    (require "game.systems.audio"),
}
local fixed_scopes={"fixed.world","fixed.player","fixed.weapons","fixed.ai","fixed.fx","fixed.audio"}
local M = {}

function M.new(services)
    local ctx = {
        config = config, services = services or {}, events = events.new(), input = input.new(),
        combat = combat.new(), presentation = presentation.new(), paused = false,
        time = { tick = 0, elapsed = 0, frame = 0, frame_elapsed = 0,
            fixed_dt = 1 / config.fixed_frequency, remainder = 0, alpha = 0 },
    }
    for _, system in ipairs(systems) do system.init(ctx) end
    hud.init(ctx)
    presentation.update(ctx)
    return ctx
end

function M.set_paused(ctx, paused)
    assert(type(paused) == "boolean", "paused must be boolean")
    if ctx.paused == paused then return end
    ctx.paused = paused
    input.reset(ctx.input)
    -- Clear stale intents without changing momentum, jump/mantle progress,
    -- reload timelines or in-flight rounds. These continue only after resume.
    ctx.player.intent = { move_x=0, move_z=0, look_x=0, look_y=0 }
    ctx.weapons.intent = {}
    ctx.time.remainder = 0
    audio.suspend(ctx, paused)
end

function M.fixed_update(ctx, dt)
    if ctx.paused then return end
    local time = ctx.time
    time.tick = time.tick + 1
    time.elapsed = time.elapsed + dt
    time.fixed_dt = dt
    -- Observe Defold's steps for presentation only. Never step Bullet ourselves.
    time.remainder = time.remainder - dt
    combat.fixed_update(ctx)
    for i, system in ipairs(systems) do
        if system.fixed_update then
            if profiler then profiler.scope_begin(fixed_scopes[i]) end
            system.fixed_update(ctx, dt)
            if profiler then profiler.scope_end() end
        end
    end
    input.end_tick(ctx.input)
end

function M.update(ctx, dt)
    local time = ctx.time
    time.frame = time.frame + 1
    time.frame_elapsed = time.frame_elapsed + dt
    if ctx.paused then
        -- Loading and sound completion callbacks must remain live in the menu.
        systems[1].update(ctx, dt)
        audio.update(ctx, dt)
        return
    end
    -- Defold calls fixed_update zero or more times before update each frame.
    time.remainder = time.remainder + dt
    time.alpha = math.max(0, math.min(1, time.remainder / time.fixed_dt))
    for _, system in ipairs(systems) do
        if system.update then system.update(ctx, dt) end
    end
    presentation.update(ctx)
    hud.update(ctx, dt)
end

function M.final(ctx)
    hud.final(ctx)
    for i = #systems, 1, -1 do
        if systems[i].final then systems[i].final(ctx) end
    end
    input.reset(ctx.input)
    events.clear(ctx.events)
    ctx.combat.pending = {}
end

return M
