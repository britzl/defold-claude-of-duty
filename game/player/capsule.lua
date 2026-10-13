-- Engine-independent kinematic controller. Positions are at the capsule's feet.
-- Queries supply sweep(), contacts(), fits() and sync(); none step physics.
local T = require "game.player.tuning"
local M = {}
local EPS = 0.000001

local function copy(out, p) out.x, out.y, out.z = p.x, p.y, p.z end
local function length(x, y, z) return math.sqrt(x*x + y*y + z*z) end

function M.new(position)
    return { position = position, velocity = { x = 0, y = 0, z = 0 },
        safe = { x = position.x, y = position.y, z = position.z },
        stance = "stand", height = T.stances.stand.height, eye = T.stances.stand.eye,
        yaw = 0, pitch = 0, grounded = false, ground = { x = 0, y = 1, z = 0 },
        surface = "concrete", coyote = 0, jump_buffer = 0, jump_cooldown = 0,
        step_offset = 0, sprinting = false, jumped = false, landed = false,
        impact_speed = 0, travel = 0, recovery_failed = false }
end

function M.reset(m, point, yaw)
    local fresh = M.new(m.position)
    for key, value in pairs(fresh) do m[key] = value end
    copy(m.position, point)
    copy(m.safe, point)
    m.yaw = yaw or 0
    m.step_support = nil
end

local function clip_velocity(m, nx, ny, nz)
    local v = m.velocity
    local dot = v.x*nx + v.y*ny + v.z*nz
    if dot < 0 then v.x, v.y, v.z = v.x-nx*dot, v.y-ny*dot, v.z-nz*dot end
end

local function recover(m, query)
    for _ = 1, 6 do
        local deepest
        for _, c in ipairs(query:contacts(m.position, m.height)) do
            if c.distance < -0.0001 and (not deepest or c.distance < deepest.distance) then deepest = c end
        end
        if not deepest then m.recovery_failed = false; return true end
        local push = math.min(0.5, -deepest.distance + T.skin)
        local p = m.position
        p.x, p.y, p.z = p.x + deepest.nx*push, p.y + deepest.ny*push, p.z + deepest.nz*push
        clip_velocity(m, deepest.nx, deepest.ny, deepest.nz)
    end
    -- Never integrate out of an unresolved overlap. The last clear position is
    -- a bounded fallback for contradictory contacts or invalid teleports.
    copy(m.position, m.safe)
    m.velocity.x, m.velocity.y, m.velocity.z = 0, 0, 0
    m.recovery_failed = true
    query:sync(m.position, m.height)
    return false
end

local function ground(m, query, distance)
    local hit = query:sweep(m.position, m.height, 0, -distance, 0)
    local support = m.step_support
    -- A capsule touches the rounded edge before its centre reaches a tread.
    -- A nearby, verified walkable tread may support this short transition.
    local edge = hit and hit.ny > 0.01 and support
        and (m.position.x-support.x)^2+(m.position.z-support.z)^2 <= (T.radius+0.02)^2
        and m.position.y <= support.y+T.skin
        and m.position.y >= support.y-T.stances[m.stance].step-T.skin
    if hit and (hit.ny >= T.slope_cos or edge) then
        m.position.y = m.position.y - math.max(0, hit.fraction*distance - T.skin)
        if edge then m.ground.x, m.ground.y, m.ground.z = 0, 1, 0
        else m.ground.x, m.ground.y, m.ground.z = hit.nx, hit.ny, hit.nz end
        m.surface = hit.surface or "concrete"
        return true
    end
    return false
end

local function slide(m, query, dx, dy, dz)
    local blocked = false
    for _ = 1, T.iterations do
        local distance = length(dx, dy, dz)
        if distance < EPS then break end
        local hit = query:sweep(m.position, m.height, dx, dy, dz)
        if not hit then
            m.position.x, m.position.y, m.position.z = m.position.x+dx, m.position.y+dy, m.position.z+dz
            break
        end
        local fraction = math.max(0, hit.fraction - T.skin/distance)
        m.position.x, m.position.y, m.position.z = m.position.x+dx*fraction, m.position.y+dy*fraction, m.position.z+dz*fraction
        dx, dy, dz = dx*(1-fraction), dy*(1-fraction), dz*(1-fraction)
        local nx, ny, nz = hit.nx, hit.ny, hit.nz
        if ny < T.slope_cos and ny > -0.01 then
            blocked = true
            -- Horizontal input cannot produce uphill lift. Gravity still
            -- slides down a steep face instead of leaving the capsule hanging.
            local horizontal = length(nx, 0, nz)
            if horizontal > EPS then
                local hx, hz = nx/horizontal, nz/horizontal
                local into = dx*hx+dz*hz
                if into < 0 then dx, dz = dx-hx*into, dz-hz*into end
                clip_velocity(m, hx, 0, hz)
                if ny > 0 then
                    local fall = math.min(0, dy)*ny
                    dx, dy, dz = dx-nx*fall, dy-ny*fall, dz-nz*fall
                    local v = m.velocity
                    fall = math.min(0, v.y)*ny
                    v.x, v.y, v.z = v.x-nx*fall, v.y-ny*fall, v.z-nz*fall
                end
            end
        else
            local into = dx*nx + dy*ny + dz*nz
            if into < 0 then dx, dy, dz = dx-nx*into, dy-ny*into, dz-nz*into end
            local falling = m.velocity.y <= 0 or m.grounded
            clip_velocity(m, nx, ny, nz)
            -- Slope displacement is handled by the support plane, not upward
            -- ballistic velocity carried into the next tick.
            if ny >= T.slope_cos and falling then m.velocity.y = 0 end
        end
    end
    return blocked
end

local function step(m, query, origin, dx, dz, step_height, slide_progress)
    local horizontal = length(dx, 0, dz)
    if horizontal < EPS then return false end
    local up = query:sweep(origin, m.height, 0, step_height, 0)
    local rise = up and math.max(0, up.fraction*step_height-T.skin) or step_height
    if rise < T.skin then return false end
    local candidate = { x = origin.x, y = origin.y+rise, z = origin.z }
    local forward = query:sweep(candidate, m.height, dx, 0, dz)
    local fraction = forward and math.max(0, forward.fraction-T.skin/horizontal) or 1
    candidate.x, candidate.z = candidate.x+dx*fraction, candidate.z+dz*fraction
    local down_distance = rise + T.ground_snap
    local down = query:sweep(candidate, m.height, 0, -down_distance, 0)
    if not down or down.ny <= 0.01 then return false end
    local support
    if down.ny < T.slope_cos then
        support = { x = candidate.x+dx/horizontal*T.radius,
            y = candidate.y, z = candidate.z+dz/horizontal*T.radius }
        if not query:fits(support, m.height) then return false end
        local top = query:sweep(support, m.height, 0, -down_distance, 0)
        if not top or top.ny < T.slope_cos then return false end
        support.y = support.y-math.max(0, top.fraction*down_distance-T.skin)
        if support.y-origin.y > step_height+T.skin then return false end
    end
    candidate.y = candidate.y - math.max(0, down.fraction*down_distance-T.skin)
    local gain = candidate.y-origin.y
    local progress = (candidate.x-origin.x)*dx + (candidate.z-origin.z)*dz
    if gain < -T.skin or gain > step_height+T.skin or progress <= slide_progress+EPS then return false end
    if not query:fits(candidate, m.height) then return false end
    copy(m.position, candidate)
    m.step_support = support
    m.step_offset = m.step_offset + math.max(0, gain)
    m.surface = down.surface or m.surface
    return true
end

local function accelerate(m, input, dt)
    local stance, v = T.stances[m.stance], m.velocity
    m.sprinting = m.stance == "stand" and input.sprint and input.move_z < -0.55 and not input.aim or false
    local speed = m.sprinting and T.sprint_speed or stance.speed
    if input.aim then speed = speed * T.ads_scale end
    local x = input.move_x * T.strafe_scale
    local z = input.move_z * (input.move_z > 0 and T.back_scale or 1)
    local cosine, sine = math.cos(m.yaw), math.sin(m.yaw)
    local wx, wz = cosine*x + sine*z, -sine*x + cosine*z
    if not m.grounded then
        if x*x+z*z < EPS then return end
        -- Air steering preserves takeoff momentum, but cannot grow its speed.
        speed = math.max(T.air_speed, length(v.x, 0, v.z))
    end
    local ax, az = wx*speed-v.x, wz*speed-v.z
    local delta = length(ax, 0, az)
    local rate = m.grounded and ((x*x+z*z > EPS) and T.acceleration or T.deceleration) or T.air_acceleration
    if delta > EPS then
        local factor = math.min(1, rate*dt/delta)
        v.x, v.z = v.x+ax*factor, v.z+az*factor
    end
end

function M.update(m, input, dt, query)
    m.jumped, m.landed = false, false
    m.travel = 0
    m.yaw = m.yaw - (input.look_x or 0)*T.mouse_sensitivity
    m.pitch = math.max(-T.pitch_limit, math.min(T.pitch_limit, m.pitch+(input.look_y or 0)*T.mouse_sensitivity))
    m.step_offset = m.step_offset * math.exp(-dt/0.08)
    local requested = input.prone and "prone" or (input.crouch and "crouch" or "stand")
    local target = T.stances[requested]
    -- Shrinking can itself resolve a ceiling overlap; expansion needs clearance.
    if target.height < m.height then m.stance, m.height = requested, target.height end
    if not recover(m, query) then m.grounded = false; return end
    if requested ~= m.stance and query:fits(m.position, target.height) then
        m.stance, m.height = requested, target.height
    end
    m.eye = m.eye + (T.stances[m.stance].eye-m.eye)*(1-math.exp(-dt/0.072))
    local was_grounded = m.grounded
    m.grounded = m.velocity.y <= 0 and ground(m, query, T.ground_probe)
    m.coyote = m.grounded and T.coyote_time or math.max(0, m.coyote-dt)
    m.jump_buffer = input.jump and T.jump_buffer or math.max(0, m.jump_buffer-dt)
    m.jump_cooldown = math.max(0, m.jump_cooldown-dt)
    accelerate(m, input, dt)
    if m.jump_buffer > 0 and m.coyote > 0 and m.jump_cooldown == 0 and m.stance ~= "prone" then
        m.velocity.y = T.jump_speed
        m.grounded, m.jumped = false, true
        m.step_support = nil
        m.jump_buffer, m.coyote, m.jump_cooldown = 0, 0, T.jump_cooldown
    end
    local v = m.velocity
    if m.grounded then v.y = 0 else v.y = math.max(-T.terminal_speed, v.y+T.gravity*dt) end
    local fall_speed = -v.y
    local dx, dy, dz = v.x*dt, v.y*dt, v.z*dt
    if m.grounded then
        -- Travel along the supporting plane at the requested surface speed.
        local n = m.ground
        local dot = dx*n.x + dz*n.z
        local px, py, pz = dx-n.x*dot, -n.y*dot, dz-n.z*dot
        local projected = length(px, py, pz)
        if projected > EPS then
            local scale = length(dx, 0, dz)/projected
            dx, dy, dz = px*scale, py*scale, pz*scale
        end
    end
    local origin = { x = m.position.x, y = m.position.y, z = m.position.z }
    local vx, vz = v.x, v.z
    local blocked = slide(m, query, dx, dy, dz)
    if blocked and m.grounded and not m.jumped then
        local progress = (m.position.x-origin.x)*dx + (m.position.z-origin.z)*dz
        if step(m, query, origin, dx, dz, T.stances[m.stance].step, progress) then v.x, v.z = vx, vz end
    end
    m.grounded = v.y <= 0 and ground(m, query, (was_grounded and not m.jumped) and T.ground_snap or T.ground_probe)
    if m.grounded then
        v.y = 0
        m.landed = not was_grounded and not m.jumped
        m.impact_speed = fall_speed
    end
    m.travel = length(m.position.x-origin.x, 0, m.position.z-origin.z)
    if query:fits(m.position, m.height) then copy(m.safe, m.position) end
    query:sync(m.position, m.height)
end

return M
