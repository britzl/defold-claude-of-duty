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
    out.camera.x, out.camera.y, out.camera.z = out.position.x, out.position.y + ctx.config.eye_height, out.position.z
    out.health = ctx.player.actor.health
end

return M
