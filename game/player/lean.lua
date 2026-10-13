local T = require "game.player.tuning"
local M = {}

function M.eye(m)
    -- A shrinking capsule may enter headroom before its eye spring settles.
    return math.min(m.eye-m.step_offset, m.height-0.1)
end

function M.apply(query, base, yaw, amount)
    local offset = amount*T.lean.offset
    local dx, dy, dz = math.cos(yaw)*offset, -math.abs(amount)*T.lean.drop, -math.sin(yaw)*offset
    local fraction = 1
    if math.abs(amount) > 1e-6 then
        fraction = query:camera_fraction(base, dx, dy, dz, T.lean.radius)
    end
    return base.x+dx*fraction, base.y+dy*fraction, base.z+dz*fraction,
        -amount*fraction*T.lean.roll, amount*fraction
end

function M.update(m, input, dt, query)
    local want = input.lean or 0
    if input.enabled == false or m.sprinting or m.sliding or m.mantle or not m.grounded or m.stance == "prone" then want = 0 end
    local amount = m.lean+(want-m.lean)*(1-math.exp(-dt/T.lean.tau))
    if math.abs(amount) < 0.0001 then amount = 0 end
    local base = { x = m.position.x, y = m.position.y+M.eye(m), z = m.position.z }
    local _, _, _, _, allowed = M.apply(query, base, m.yaw, amount)
    m.lean = allowed
end

return M
