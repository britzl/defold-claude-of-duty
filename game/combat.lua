local events = require "game.events"
local M = {}

function M.new()
    return { actors = {}, pending = {} }
end

function M.register(combat, id, health)
    assert(not combat.actors[id], "Actor already registered: " .. id)
    assert(health > 0 and health < math.huge, "Health must be positive and finite")
    local actor = { id = id, health = health, max_health = health, alive = true }
    combat.actors[id] = actor
    return actor
end

function M.remove(combat, id)
    combat.actors[id] = nil
end

function M.request(combat, hit)
    if type(hit) ~= "table" or type(hit.target) ~= "string" or type(hit.amount) ~= "number"
        or not (hit.amount > 0 and hit.amount < math.huge) then
        return false
    end
    local actor = combat.actors[hit.target]
    if not actor or not actor.alive then return false end
    -- Copy scalar data so an emitter can reuse its hit record immediately.
    combat.pending[#combat.pending + 1] = {
        actor = actor, amount = hit.amount, source = hit.source,
        headshot = hit.headshot == true, point = hit.point, impulse = hit.impulse,
    }
    return true
end

function M.fixed_update(ctx)
    local combat = ctx.combat
    if #combat.pending == 0 then return end
    local pending = combat.pending
    combat.pending = {} -- Hits requested by notifications run next tick.
    for _, hit in ipairs(pending) do
        local actor = hit.actor
        if combat.actors[actor.id] == actor and actor.alive then
            local amount = math.min(hit.amount, actor.health)
            -- The only runtime owner of health and alive writes.
            actor.health = actor.health - amount
            actor.alive = actor.health > 0
            local notification = {
                target = actor.id, source = hit.source, amount = amount,
                health = actor.health, killed = not actor.alive,
                headshot = hit.headshot, point = hit.point,
            }
            events.emit(ctx.events, events.DAMAGE_DEALT, notification)
            if actor.id == "player" then
                events.emit(ctx.events, events.DAMAGE_TAKEN, notification)
            end
            if not actor.alive then
                events.emit(ctx.events, events.ACTOR_DEATH, {
                    actor = actor.id, source = hit.source,
                    point = hit.point, impulse = hit.impulse,
                })
            end
        end
    end
end

return M
