local events = require "game.events"
local M = {}

function M.new()
    return { actors = {}, pending = {} }
end

function M.register(combat, id, health, regeneration)
    assert(not combat.actors[id], "Actor already registered: " .. id)
    assert(health > 0 and health < math.huge, "Health must be positive and finite")
    local actor = { id = id, health = health, max_health = health, alive = true,
        regeneration = regeneration, since_damage = 0, regenerating = false }
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
    -- Keep the firing origin, not the impact on the victim, for direction cues.
    local function copy(p) return p and {x=p.x,y=p.y,z=p.z} end
    combat.pending[#combat.pending + 1] = {
        actor = actor, amount = hit.amount, source = hit.source,
        headshot = hit.headshot == true, point = copy(hit.point), impulse = copy(hit.impulse),
        from = copy(hit.from), kind = hit.kind, round = hit.round,
    }
    return true
end

function M.fixed_update(ctx, dt)
    local combat = ctx.combat
    local damaged = {}
    local pending = combat.pending
    combat.pending = {} -- Hits requested by notifications run next tick.
    for _, hit in ipairs(pending) do
        local actor = hit.actor
        if combat.actors[actor.id] == actor and actor.alive then
            local amount = math.min(hit.amount, actor.health)
            -- The only runtime owner of health and alive writes.
            actor.health = actor.health - amount
            actor.alive = actor.health > 0
            actor.since_damage, actor.regenerating = 0, false
            damaged[actor] = true
            local notification = {
                target = actor.id, source = hit.source, amount = amount,
                health = actor.health, killed = not actor.alive,
                headshot = hit.headshot, point = hit.point, from = hit.from,
                kind = hit.kind, round = hit.round,
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
    -- Damage wins this tick. Recovery uses simulation time, never wall time or
    -- presentation frames, and cannot heal an actor that has died/replaced.
    if not ctx.world.ready or not ctx.player.enabled then return end
    for _, actor in pairs(combat.actors) do
        local r = actor.regeneration
        if r and actor.alive and not damaged[actor] then
            actor.since_damage = actor.since_damage + (dt or ctx.time.fixed_dt)
            local ramp = math.max(0, math.min(1, (actor.since_damage-r.delay)/r.ramp))
            actor.regenerating = actor.health < actor.max_health and ramp > 1e-9
            if actor.regenerating then
                actor.health = math.min(actor.max_health, actor.health+r.rate*ramp*(dt or ctx.time.fixed_dt))
                actor.regenerating = actor.health < actor.max_health
            end
        end
    end
end

return M
