local camera = require "game.player.camera"
local tuning = require "game.player.tuning"
local M = {}

function M.new()
    return { position = { x = 0, y = 0, z = 0 }, camera = { x = 0, y = 0, z = 0 }, health = 100 }
end

function M.update(ctx)
    local out, alpha = ctx.presentation, ctx.time.alpha
    camera.compose(ctx, alpha, out)
    local weapons = ctx.weapons
    if weapons then
        out.pitch = out.pitch + weapons.previous_recoil.pitch + (weapons.recoil.pitch.x-weapons.previous_recoil.pitch)*alpha
        out.yaw = out.yaw + weapons.previous_recoil.yaw + (weapons.recoil.yaw.x-weapons.previous_recoil.yaw)*alpha
    end
    out.pitch = math.max(-tuning.pitch_limit, math.min(tuning.pitch_limit, out.pitch))
    out.health = ctx.player.actor.health
end

return M
