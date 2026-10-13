local combat = require "game.combat"
local M = {}

function M.init(ctx)
    ctx.ai = { actors = {} }
end

function M.final(ctx)
    for id in pairs(ctx.ai.actors) do combat.remove(ctx.combat, id) end
    ctx.ai = nil
end

return M
