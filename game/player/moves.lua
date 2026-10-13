-- Sprint/slide decisions and velocity, independent of geometry and rendering.
local T = require "game.player.tuning"
local M = {}
local function speed(m) return math.sqrt(m.velocity.x^2+m.velocity.z^2) end

function M.init(m)
    m.tactical, m.tactical_time, m.tactical_cooldown = false, 0, 0
    m.sprint_tap, m.tactical_request = 0, false
    m.sliding, m.slide_time, m.slide_air, m.slide_cooldown = false, 0, 0, 0
    m.slide_started, m.slide_ended, m.slide_jump = false, false, false
    m.previous_sprint, m.previous_crouch = false, false
end

local function stop_tactical(m)
    if m.tactical then m.tactical_cooldown = T.tactical.recovery end
    m.tactical, m.tactical_time, m.tactical_request = false, 0, false
end

function M.end_slide(m, jumping)
    m.sliding, m.slide_ended, m.slide_jump = false, true, jumping or false
    m.slide_cooldown = T.slide.cooldown
    if jumping then
        local s = speed(m)
        if s > T.slide.jump_speed_cap then
            local scale = T.slide.jump_speed_cap/s
            m.velocity.x, m.velocity.z = m.velocity.x*scale, m.velocity.z*scale
        end
    end
end

function M.cancel(m)
    stop_tactical(m)
    m.sprinting, m.sprint_tap = false, 0
    if m.sliding then M.end_slide(m) end
end

function M.tick(m, input, dt)
    m.slide_started, m.slide_ended, m.slide_jump = false, false, false
    m.slide_cooldown = math.max(0, m.slide_cooldown-dt)
    m.tactical_cooldown = math.max(0, m.tactical_cooldown-dt)
    m.sprint_tap = math.max(0, m.sprint_tap-dt)
    m.crouch_edge = input.crouch_pressed or (input.crouch and not m.previous_crouch)
    local press = input.sprint_pressed or (input.sprint and not m.previous_sprint)
    m.previous_sprint, m.previous_crouch = input.sprint, input.crouch
    if press then
        m.tactical_request = m.sprint_tap > 0 and m.tactical_cooldown == 0
        m.sprint_tap = T.tactical.tap_window
    end
    if m.sliding then
        m.slide_time = m.slide_time+dt
        m.slide_air = m.grounded and 0 or m.slide_air+dt
    end
    if input.enabled == false then
        M.cancel(m)
        m.jump_buffer = 0
    end
end

function M.decide(m, input)
    if input.enabled == false then return end
    local can_jump = m.jump_buffer > 0 and m.coyote > 0 and m.jump_cooldown == 0
    if m.sliding then
        if can_jump and not input.prone then M.end_slide(m, true)
        elseif m.crouch_edge or input.prone or m.slide_time >= T.slide.duration
            or m.slide_air > T.slide.air_grace or speed(m) < T.slide.exit_speed then M.end_slide(m) end
    elseif m.crouch_edge and not input.prone and not input.aim and m.sprinting and m.grounded
        and speed(m) >= T.slide.min_speed and m.slide_cooldown == 0 and m.mantle_cooldown == 0 then
        local s = speed(m)
        local burst = math.max(T.slide.min_entry, math.min(T.slide.entry_speed, s*1.3))
        m.velocity.x, m.velocity.z = m.velocity.x/s*burst, m.velocity.z/s*burst
        m.sliding, m.slide_started, m.slide_time, m.slide_air = true, true, 0, 0
    end
    local want = input.sprint and input.move_z < -0.55 and not input.aim
        and not input.crouch and not input.prone and m.stance == "stand"
        and not m.sliding and not m.slide_jump and (m.grounded or m.sprinting)
    m.sprinting = want or false
    if not want then stop_tactical(m)
    elseif m.tactical_request and m.tactical_cooldown == 0 then
        m.tactical, m.tactical_time = true, 0
    end
    m.tactical_request = false
end

function M.accelerate_slide(m, input, dt)
    local v, t = m.velocity, T.slide
    local s = speed(m)
    if s < 1e-6 then return end
    local x, z = v.x/s, v.z/s
    local wx = math.cos(m.yaw)*input.move_x+math.sin(m.yaw)*input.move_z
    local wz = -math.sin(m.yaw)*input.move_x+math.cos(m.yaw)*input.move_z
    local turn = (-z*wx+x*wz)*t.steer*dt
    local nx, nz = x-z*turn, z+x*turn
    local len = math.sqrt(nx*nx+nz*nz)
    x, z = nx/len, nz/len
    -- The horizontal component of the upward ground normal points downhill.
    if m.grounded then s = s+(m.ground.x*x+m.ground.z*z)*t.slope_assist*dt end
    s = math.max(0, math.min(t.entry_speed, s*math.exp(-t.drag*dt)-t.brake*dt))
    v.x, v.z = x*s, z*s
end

function M.sprint_time(m, dt)
    if m.tactical then
        m.tactical_time = m.tactical_time+dt
        if m.tactical_time >= T.tactical.duration then stop_tactical(m) end
    end
end

return M
