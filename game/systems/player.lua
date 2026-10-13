local combat = require "game.combat"
local M = {}

function M.init(ctx)
    local spawn = ctx.world.spawn
    ctx.player = {
        actor = combat.register(ctx.combat, "player", ctx.config.player_health),
        previous = { x = spawn.x, y = spawn.y, z = spawn.z },
        position = { x = spawn.x, y = spawn.y, z = spawn.z },
        intent = { move_x = 0, move_z = 0, look_x = 0, look_y = 0 },
    }
end

function M.fixed_update(ctx, dt)
    local player = ctx.player
    local previous, position = player.previous, player.position
    previous.x, previous.y, previous.z = position.x, position.y, position.z
    local buttons, intent = ctx.input.buttons, player.intent
    local alive = player.actor.alive
    intent.move_x = alive and ((buttons.right.held and 1 or 0) - (buttons.left.held and 1 or 0)) or 0
    intent.move_z = alive and ((buttons.back.held and 1 or 0) - (buttons.forward.held and 1 or 0)) or 0
    local length = math.sqrt(intent.move_x * intent.move_x + intent.move_z * intent.move_z)
    if length > 1 then
        intent.move_x, intent.move_z = intent.move_x / length, intent.move_z / length
    end
    intent.look_x, intent.look_y = ctx.input.look_x, ctx.input.look_y
    intent.jump = alive and buttons.jump.pressed
    intent.sprint = alive and buttons.sprint.held
    intent.crouch = alive and buttons.crouch.held
    intent.prone = alive and buttons.prone.held
    intent.lean = alive and ((buttons.lean_right.held and 1 or 0) - (buttons.lean_left.held and 1 or 0)) or 0
    -- The capsule controller will consume intent here. Do not move without queries.
end

function M.final(ctx)
    combat.remove(ctx.combat, "player")
    ctx.player = nil
end

return M
