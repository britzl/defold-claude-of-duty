-- Engine-independent presentation state. Notifications never apply damage.
local events = require "game.events"
local M = { feed_limit = 4, feed_seconds = 6, map_limit = 256, map_range = 22 }
local function name(id)
    if id == "player" then return "YOU" end
    if id and id:match("^enemy") then return "HOSTILE" end
    return id and "TARGET" or "WORLD"
end

function M.init(ctx)
    ctx.hud = { feed = {}, damage = 0, source = false, headshot = false }
    events.on(ctx.events, events.DAMAGE_DEALT, ctx.hud, function(state, hit)
        if hit.source == "player" and hit.target ~= "player" then state.headshot = hit.headshot end
        if hit.killed then
            table.insert(state.feed, 1, { remaining = M.feed_seconds,
                text = name(hit.source).."  >  "..name(hit.target)..(hit.headshot and "  [HEAD]" or "") })
            if #state.feed > M.feed_limit then table.remove(state.feed) end
        end
    end)
    events.on(ctx.events, events.DAMAGE_TAKEN, ctx.hud, function(state, hit)
        state.damage = 1
        local source = ctx.ai.actors[hit.source]
        local p = source and source.position
        state.source = p and { x = p.x, z = p.z } or false
    end)
end

function M.update(ctx, dt)
    local state = ctx.hud
    state.damage = math.max(0, state.damage - dt * 1.8)
    for i = #state.feed, 1, -1 do
        state.feed[i].remaining = state.feed[i].remaining - dt
        if state.feed[i].remaining <= 0 then table.remove(state.feed, i) end
    end
end

function M.reset(ctx)
    ctx.hud.feed, ctx.hud.damage, ctx.hud.source, ctx.hud.headshot = {}, 0, false, false
end

function M.heading(yaw)
    return (-math.deg(yaw)) % 360
end

function M.snapshot(ctx)
    local state, out = ctx.hud, ctx.presentation
    local lines = {}
    for i, entry in ipairs(state.feed) do lines[i] = entry.text end
    local direction = ""
    if state.source and state.damage > 0 then
        local dx, dz = state.source.x - out.position.x, state.source.z - out.position.z
        local c, s = math.cos(out.yaw), math.sin(out.yaw)
        local right, forward = dx*c-dz*s, -dx*s-dz*c
        if math.abs(right) > math.abs(forward) then direction = right > 0 and "right" or "left"
        else direction = forward >= 0 and "front" or "back" end
    end
    return { feed = table.concat(lines, "\n"), feed_count = #lines, damage = state.damage,
        damage_direction = direction, headshot = state.headshot or false,
        heading = M.heading(out.yaw), x = out.position.x, y = out.position.y, z = out.position.z,
        yaw = out.yaw, alive = ctx.player.actor.alive }
end

-- Clip a north-up, player-centred map to its square and the player's floor.
-- A horizontal slice avoids drawing roofs over the enterable room.
function M.map_rect(shape, x, y, z, size)
    if shape.bottom > y + 1.25 or shape.top < y - .3 then return nil end
    local range = M.map_range
    local left, right = math.max(-range, shape.x-shape.w/2-x), math.min(range, shape.x+shape.w/2-x)
    local bottom, top = math.max(-range, z-shape.z-shape.d/2), math.min(range, z-shape.z+shape.d/2)
    if left >= right or bottom >= top then return nil end
    local scale = size / (range*2)
    return { x=(left+right)*.5*scale, y=(bottom+top)*.5*scale,
        w=(right-left)*scale, h=(top-bottom)*scale, floor=shape.top <= y+.3 }
end

function M.final(ctx)
    events.off_owner(ctx.events, ctx.hud)
    ctx.hud = nil
end
return M
