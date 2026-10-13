local M = {
    WEAPON_FIRE = "weapon:fire",
    WEAPON_RELOAD = "weapon:reload",
    WEAPON_SHELL = "weapon:shell",
    BULLET_IMPACT = "bullet:impact",
    BULLET_TRACER = "bullet:tracer",
    DAMAGE_DEALT = "damage:dealt",
    DAMAGE_TAKEN = "damage:taken",
    ACTOR_DEATH = "actor:death",
    PLAYER_LAND = "player:land",
    PLAYER_FOOTSTEP = "player:footstep",
    PLAYER_STATE = "player:state",
    EXPLOSION = "explosion",
}

function M.new()
    return { listeners = {} }
end

function M.on(bus, name, owner, callback)
    local listeners = bus.listeners[name]
    if not listeners then
        listeners = {}
        bus.listeners[name] = listeners
    end
    listeners[#listeners + 1] = { owner = owner, callback = callback }
end

function M.off_owner(bus, owner)
    for _, listeners in pairs(bus.listeners) do
        for i = 1, #listeners do
            if listeners[i].owner == owner then
                -- Keep indices stable if a listener unsubscribes during emit.
                listeners[i].callback = nil
                listeners[i].owner = nil
            end
        end
    end
end

function M.emit(bus, name, payload)
    local listeners = bus.listeners[name]
    if not listeners then return end
    -- Synchronous, registration order. New listeners start on the next emit.
    -- Payloads are read-only notifications, never damage application requests.
    for i = 1, #listeners do
        local listener = listeners[i]
        if listener.callback then listener.callback(listener.owner, payload) end
    end
end

function M.clear(bus)
    bus.listeners = {}
end

return M
