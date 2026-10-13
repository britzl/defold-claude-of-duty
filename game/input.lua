local M = {}

M.actions = {
    "forward", "back", "left", "right", "sprint", "crouch", "prone",
    "jump", "fire", "aim", "reload", "inspect", "lean_left", "lean_right",
}

function M.new()
    local input = { buttons = {}, look_x = 0, look_y = 0 }
    for _, name in ipairs(M.actions) do
        input.buttons[name] = { held = false, pressed = false, released = false }
    end
    return input
end

function M.button(input, name, action)
    local button = input.buttons[name]
    if not button then return false end
    if action.pressed then
        if not button.held then button.pressed = true end
        button.held = true
    end
    if action.released then
        button.held = false
        button.released = true
    end
    return true
end

function M.look(input, dx, dy)
    input.look_x = input.look_x + dx
    input.look_y = input.look_y + dy
end

function M.end_tick(input)
    for _, button in pairs(input.buttons) do
        button.pressed = false
        button.released = false
    end
    input.look_x, input.look_y = 0, 0
end

function M.reset(input)
    M.end_tick(input)
    for _, button in pairs(input.buttons) do button.held = false end
end

return M
