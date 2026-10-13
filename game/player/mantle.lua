-- Ledge detection and a swept, up-then-forward climb. Defold owns all stepping.
local T = require "game.player.tuning"
local M = {}
local function point(x, y, z) return { x = x, y = y, z = z } end
local function clear(query, a, b, height)
    -- Sweeps omit initial overlaps, so check both ends explicitly as well.
    return query:fits(a, height) and query:fits(b, height)
        and not query:sweep(a, height, b.x-a.x, b.y-a.y, b.z-a.z)
end

function M.cancel(m)
    if not m.mantle then return end
    m.mantle, m.mantle_aborted, m.grounded = false, true, false
    m.mantle_cooldown = T.mantle.cooldown
    m.velocity.x, m.velocity.y, m.velocity.z = 0, 0, 0
end

function M.try_begin(m, input, query)
    local t, p = T.mantle, m.position
    if input.enabled == false or m.sliding or m.stance == "prone" or m.mantle_cooldown > 0
        or input.move_z >= -0.4 or not (input.jump or input.jump_held)
        or (m.mantle_probe > 0 and not input.jump) then return false end
    m.mantle_probe = t.probe_interval
    local fx, fz = -math.sin(m.yaw), -math.cos(m.yaw)
    local reach = T.radius+t.reach
    local face = query:ray(point(p.x, p.y+math.max(t.min_height, T.stances[m.stance].step)+0.05, p.z), fx*reach, 0, fz*reach)
    if not face or math.abs(face.ny) > 0.2 or face.nx*fx+face.nz*fz > -0.5 then return false end
    local lip = point(face.x+fx*0.06, p.y+t.max_height+0.1, face.z+fz*0.06)
    local top = query:ray(lip, 0, -(t.max_height+0.15), 0)
    if not top or top.ny < T.slope_cos then return false end
    local rise = top.y-p.y
    if rise < math.max(t.min_height, T.stances[m.stance].step+0.07) or rise > t.max_height then return false end
    local target = point(face.x+fx*t.land_depth, top.y+T.skin, face.z+fz*t.land_depth)
    local support = query:ray(point(target.x, top.y+0.1, target.z), 0, -0.2, 0)
    if not support or support.ny < T.slope_cos or math.abs(support.y-top.y) > 0.05 then return false end
    target.y = support.y+T.skin
    local finish_stance = "stand"
    if not query:fits(target, T.stances.stand.height) then
        finish_stance = "crouch"
        if not query:fits(target, T.stances.crouch.height) then return false end
    end
    local start = point(p.x, p.y, p.z)
    local up = point(p.x, math.max(top.y, support.y)+t.clearance, p.z)
    local over = point(target.x, up.y, target.z)
    local climb_stance
    for _, stance in ipairs({ "stand", "crouch" }) do
        local height = T.stances[stance].height
        if query:fits(start, height) and clear(query, start, up, height)
            and clear(query, up, over, height) and clear(query, over, target, height) then
            climb_stance = stance
            break
        end
    end
    if not climb_stance then return false end
    local duration = rise <= t.low_height and t.low_time
        or t.time+(t.high_time-t.time)*(rise-t.low_height)/(t.max_height-t.low_height)
    m.mantle = { start = start, up = up, over = over, target = target, time = 0,
        duration = duration, finish_stance = finish_stance, fx = fx, fz = fz, surface = top.surface }
    m.mantle_started, m.grounded, m.step_support = true, false, nil
    m.stance, m.height = climb_stance, T.stances[climb_stance].height
    m.jump_buffer, m.coyote = 0, 0
    m.velocity.x, m.velocity.y, m.velocity.z = 0, 0, 0
    return true
end

function M.update(m, input, dt, query)
    local path = m.mantle
    if input.enabled == false then M.cancel(m); return end
    path.time = math.min(path.duration, path.time+dt)
    local u = path.time/path.duration
    local a, b, phase
    if u < 0.55 then a, b, phase = path.start, path.up, u/0.55
    elseif u < 0.95 then a, b, phase = path.up, path.over, (u-0.55)/0.4
    else a, b, phase = path.over, path.target, (u-0.95)/0.05 end
    local smooth = phase*phase*(3-2*phase)
    local next_position = point(a.x+(b.x-a.x)*smooth, a.y+(b.y-a.y)*smooth, a.z+(b.z-a.z)*smooth)
    -- Revalidate each tick: a newly blocked route cancels at the current clear
    -- position, never teleports the player to the far end of the obstacle.
    if not clear(query, m.position, next_position, m.height) then M.cancel(m); return end
    m.position.x, m.position.y, m.position.z = next_position.x, next_position.y, next_position.z
    m.safe.x, m.safe.y, m.safe.z = next_position.x, next_position.y, next_position.z
    m.grounded = false
    if u == 1 then
        local stance = input.crouch and "crouch" or path.finish_stance
        if query:fits(m.position, T.stances[stance].height) then
            m.stance, m.height = stance, T.stances[stance].height
        end
        m.mantle, m.mantle_completed, m.grounded = false, true, true
        m.mantle_cooldown, m.jump_buffer = T.mantle.cooldown, 0
        m.surface = path.surface or "concrete"
        m.ground.x, m.ground.y, m.ground.z = 0, 1, 0
        m.velocity.x, m.velocity.z = path.fx*1.35, path.fz*1.35
    end
end

return M
