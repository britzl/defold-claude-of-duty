-- Source: Claude-of-Duty src/player/tuning.js, metres and seconds.
return {
    radius = 0.32,
    gravity = -20.6,
    jump_speed = math.sqrt(2 * 20.6 * 0.6),
    jump_buffer = 0.13, coyote_time = 0.09, jump_cooldown = 0.28,
    acceleration = 92, deceleration = 82, air_acceleration = 23,
    air_speed = 3.4, terminal_speed = 55, sprint_speed = 7.01,
    strafe_scale = 0.92, back_scale = 0.8, ads_scale = 0.5,
    mouse_sensitivity = 0.0022, pitch_limit = math.rad(88),
    -- Controller tolerances; slope limit and skin are port-specific.
    skin = 0.004, slope_cos = math.cos(math.rad(45)),
    ground_probe = 0.06, ground_snap = 0.34, iterations = 5,
    stances = {
        stand = { height = 1.78, eye = 1.66, speed = 4.57, step = 0.42, stride = 1.48 },
        crouch = { height = 1.12, eye = 1.02, speed = 2.44, step = 0.3, stride = 1.05 },
        prone = { height = 0.70, eye = 0.40, speed = 1.01, step = 0.14, stride = 0.78 },
    },
}
