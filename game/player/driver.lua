-- Deterministic traversal inputs consumed by real Defold fixed updates.
local M = {}
local flags = { "sprint", "crouch", "prone", "aim" }

function M.new(segments)
    assert(type(segments) == "table" and #segments > 0 and #segments <= 32, "Expected 1-32 input segments")
    local total = 0
    for _, s in ipairs(segments) do
        assert(type(s.ticks) == "number" and s.ticks >= 1 and s.ticks == math.floor(s.ticks), "ticks must be a positive integer")
        total = total + s.ticks
        for _, key in ipairs({ "move_x", "move_z", "look_x", "look_y", "lean" }) do
            local v = s[key] or 0
            assert(type(v) == "number" and v == v and math.abs(v) < 10000, "Invalid " .. key)
        end
    end
    assert(total <= 2400, "Traversal drive is limited to 2400 ticks")
    return { segments = segments, index = 1, tick = 0, complete = false, ticks = 0,
        jumps = 0, landings = 0, grounded_ticks = 0, max_y = -math.huge, min_y = math.huge,
        slides = 0, slide_ticks = 0, tactical_ticks = 0, mantles = 0, mantle_completions = 0,
        mantle_aborts = 0, vaults = 0, vault_completions = 0, vault_aborts = 0,
        max_speed = 0, max_lean = 0, slide_jump_speed = 0 }
end

function M.input(drive, intent)
    local s = drive.segments[drive.index]
    intent.move_x = math.max(-1, math.min(1, s.move_x or 0))
    intent.move_z = math.max(-1, math.min(1, s.move_z or 0))
    local len = math.sqrt(intent.move_x^2 + intent.move_z^2)
    if len > 1 then intent.move_x, intent.move_z = intent.move_x/len, intent.move_z/len end
    for _, flag in ipairs(flags) do intent[flag] = s[flag] == true end
    intent.jump = s.jump == true and drive.tick == 0
    intent.jump_held = s.jump_held == true or s.jump == true
    -- Hold transitions are detected by the movement state machine. Explicit
    -- edges also support a quick press/release entirely within one fixed tick.
    intent.sprint_pressed = s.sprint_pressed == true and drive.tick == 0
    intent.crouch_pressed = s.crouch_pressed == true and drive.tick == 0
    intent.lean = math.max(-1, math.min(1, s.lean or 0))
    intent.look_x, intent.look_y = s.look_x or 0, s.look_y or 0
end

function M.record(drive, motion)
    drive.ticks, drive.tick = drive.ticks+1, drive.tick+1
    drive.max_y, drive.min_y = math.max(drive.max_y, motion.position.y), math.min(drive.min_y, motion.position.y)
    if motion.jumped then drive.jumps = drive.jumps+1 end
    if motion.landed then drive.landings = drive.landings+1 end
    if motion.grounded then drive.grounded_ticks = drive.grounded_ticks+1 end
    if motion.slide_started then drive.slides = drive.slides+1 end
    if motion.sliding then drive.slide_ticks = drive.slide_ticks+1 end
    if motion.tactical then drive.tactical_ticks = drive.tactical_ticks+1 end
    if motion.mantle_started then drive.mantles = drive.mantles+1 end
    if motion.mantle_completed then drive.mantle_completions = drive.mantle_completions+1 end
    if motion.mantle_aborted then drive.mantle_aborts = drive.mantle_aborts+1 end
    if motion.vault_started then drive.vaults = drive.vaults+1 end
    if motion.vault_completed then drive.vault_completions = drive.vault_completions+1 end
    if motion.vault_aborted then drive.vault_aborts = drive.vault_aborts+1 end
    drive.max_speed = math.max(drive.max_speed, math.sqrt(motion.velocity.x^2+motion.velocity.z^2))
    if motion.jumped and motion.slide_jump then
        drive.slide_jump_speed = math.sqrt(motion.velocity.x^2+motion.velocity.z^2)
    end
    drive.max_lean = math.max(drive.max_lean, math.abs(motion.lean))
    if drive.tick == drive.segments[drive.index].ticks then
        drive.index, drive.tick = drive.index+1, 0
        drive.complete = drive.index > #drive.segments
        if drive.complete then
            drive.result = { x = motion.position.x, y = motion.position.y, z = motion.position.z,
                grounded = motion.grounded, stance = motion.stance, height = motion.height,
                yaw = motion.yaw, pitch = motion.pitch, recovery_failed = motion.recovery_failed,
                max_y = drive.max_y, min_y = drive.min_y, jumps = drive.jumps,
                landings = drive.landings, grounded_ticks = drive.grounded_ticks, ticks = drive.ticks }
            local r = drive.result
            for _, key in ipairs({ "slides", "slide_ticks", "tactical_ticks", "mantles", "mantle_completions", "mantle_aborts", "max_speed", "max_lean", "slide_jump_speed" }) do r[key] = drive[key] end
            for _, key in ipairs({ "vaults", "vault_completions", "vault_aborts" }) do r[key] = drive[key] end
            r.sliding, r.tactical, r.mantling, r.lean = motion.sliding, motion.tactical, motion.mantle ~= false, motion.lean
        end
    end
end

return M
