local M = {}

function M.init(ctx)
    ctx.weapons = { equipped = nil, intent = {} }
end

function M.fixed_update(ctx, dt)
    local buttons, intent = ctx.input.buttons, ctx.weapons.intent
    local alive = ctx.player.actor.alive
    intent.fire = alive and (buttons.fire.held or buttons.fire.pressed)
    intent.aim = alive and buttons.aim.held
    intent.reload = alive and buttons.reload.pressed
    intent.inspect = alive and buttons.inspect.pressed
    -- Weapon definitions and ballistics arrive in step 4. No synthetic hit events.
end

function M.final(ctx)
    ctx.weapons = nil
end

return M
