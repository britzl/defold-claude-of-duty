local events = require "game.events"
local M = {}

function M.init(ctx)
    ctx.fx = { hitmarker = 0, damage_flash = 0 }
    events.on(ctx.events, events.DAMAGE_DEALT, ctx.fx, function(state, hit)
        if hit.source == "player" and hit.target ~= "player" then
            state.hitmarker = 0.12
        end
    end)
    events.on(ctx.events, events.DAMAGE_TAKEN, ctx.fx, function(state)
        state.damage_flash = 0.2
    end)
end

function M.update(ctx, dt)
    ctx.fx.hitmarker = math.max(0, ctx.fx.hitmarker - dt)
    ctx.fx.damage_flash = math.max(0, ctx.fx.damage_flash - dt)
end

function M.final(ctx)
    events.off_owner(ctx.events, ctx.fx)
    ctx.fx = nil
end

return M
