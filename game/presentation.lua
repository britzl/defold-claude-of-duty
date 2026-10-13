local lean = require "game.player.lean"
local M = {}

function M.new()
    return { position = { x = 0, y = 0, z = 0 }, camera = { x = 0, y = 0, z = 0 }, health = 100 }
end

function M.update(ctx)
    local a, b = ctx.player.previous, ctx.player.position
    local out, alpha = ctx.presentation, ctx.time.alpha
    out.position.x = a.x + (b.x - a.x) * alpha
    out.position.y = a.y + (b.y - a.y) * alpha
    out.position.z = a.z + (b.z - a.z) * alpha
    local player, motion = ctx.player, ctx.player.motion
    local eye = math.min(motion.height-0.1, player.previous_eye + (lean.eye(motion)-player.previous_eye)*alpha)
    out.camera.x, out.camera.y, out.camera.z = out.position.x, out.position.y + eye, out.position.z
    out.yaw = player.previous_yaw + (motion.yaw-player.previous_yaw)*alpha
    out.pitch = player.previous_pitch + (motion.pitch-player.previous_pitch)*alpha
    local amount = player.previous_lean+(motion.lean-player.previous_lean)*alpha
    -- Recheck the interpolated camera every frame as position/yaw may have
    -- changed since the fixed query. Collision may shorten a lean immediately.
    out.camera.x, out.camera.y, out.camera.z, out.roll = lean.apply(ctx.services.capsule, out.camera, out.yaw, amount)
    local weapons = ctx.weapons
    if weapons then
        out.pitch = out.pitch + weapons.previous_recoil.pitch + (weapons.recoil.pitch.x-weapons.previous_recoil.pitch)*alpha
        out.yaw = out.yaw + weapons.previous_recoil.yaw + (weapons.recoil.yaw.x-weapons.previous_recoil.yaw)*alpha
    end
    out.health = ctx.player.actor.health
end

return M
