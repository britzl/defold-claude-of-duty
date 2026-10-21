local M = {}

M.actions = {
    "forward", "back", "left", "right", "sprint", "crouch", "prone",
    "jump", "fire", "aim", "reload", "inspect", "lean_left", "lean_right",
    "weapon_rifle", "weapon_smg", "weapon_pistol", "next_weapon", "previous_weapon", "fire_mode",
}

function M.new()
    local input = { buttons = {}, movement = {}, look_x = 0, look_y = 0, move_x = 0, move_z = 0 }
    for _, name in ipairs(M.actions) do
        input.buttons[name] = { held = false, pressed = false, released = false, sources = {} }
    end
    return input
end

function M.move(buffer, source, x, z)
    buffer.movement[source] = (x~=0 or z~=0) and {x=x,z=z} or nil
    local mx,mz=0,0
    for _,v in pairs(buffer.movement) do mx,mz=mx+v.x,mz+v.z end
    local length=math.max(1,math.sqrt(mx*mx+mz*mz))
    buffer.move_x,buffer.move_z=mx/length,mz/length
end

function M.release_source(buffer, source)
    for name in pairs(buffer.buttons) do M.button(buffer,name,{released=true},source) end
    M.move(buffer,source,0,0)
end

function M.button(input, name, action, source)
    local button = input.buttons[name]
    if not button then return false end
    source = source or "desktop"
    local function set(held)
        button.sources[source] = held or nil
        local active = next(button.sources) ~= nil
        if active and not button.held then button.pressed = true end
        if not active and button.held then button.released = true end
        button.held = active
    end
    if action.pressed then set(true) end
    if action.released then set(false) end
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
    input.move_x, input.move_z = 0, 0
    input.movement = {}
    for _, button in pairs(input.buttons) do button.held, button.sources = false, {} end
end

return M
