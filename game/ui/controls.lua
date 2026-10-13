-- Track physical holds separately from gameplay, including while a menu owns
-- input. A transition quarantines held buttons until their actual release.
local M = {}
function M.new()
    return { held = {}, blocked = {}, sensitivity = 1 }
end
function M.observe(state, name, action)
    if not name then return end
    if action.pressed then state.held[name] = true end
    if action.released then state.held[name], state.blocked[name] = nil, nil end
end
function M.quarantine(state)
    for name in pairs(state.held) do state.blocked[name] = true end
end
function M.allowed(state, name)
    return not state.blocked[name]
end
function M.configure(state, value)
    assert(type(value) == "number" and value == value and value >= .25 and value <= 3,
        "Sensitivity must be 0.25..3")
    state.sensitivity = value
end
return M
