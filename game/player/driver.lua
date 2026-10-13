-- Deterministic traversal inputs consumed by real Defold fixed updates.
local M = {}
local flags = { "sprint", "crouch", "prone", "aim" }

function M.new(segments)
    assert(type(segments) == "table" and #segments > 0 and #segments <= 32, "Expected 1-32 input segments")
    local total = 0
    for _, s in ipairs(segments) do
        assert(type(s.ticks) == "number" and s.ticks >= 1 and s.ticks == math.floor(s.ticks), "ticks must be a positive integer")
        total = total + s.ticks
        for _, key in ipairs({ "move_x", "move_z", "look_x", "look_y" }) do
            local v = s[key] or 0
            assert(type(v) == "number" and v == v and math.abs(v) < 10000, "Invalid " .. key)
        end
    end
    assert(total <= 2400, "Traversal drive is limited to 2400 ticks")
    return { segments = segments, index = 1, tick = 0, complete = false, ticks = 0,
        jumps = 0, landings = 0, grounded_ticks = 0, max_y = -math.huge, min_y = math.huge }
end

function M.input(drive, intent)
    local s = drive.segments[drive.index]
    intent.move_x = math.max(-1, math.min(1, s.move_x or 0))
    intent.move_z = math.max(-1, math.min(1, s.move_z or 0))
    local len = math.sqrt(intent.move_x^2 + intent.move_z^2)
    if len > 1 then intent.move_x, intent.move_z = intent.move_x/len, intent.move_z/len end
    for _, flag in ipairs(flags) do intent[flag] = s[flag] == true end
    intent.jump = s.jump == true and drive.tick == 0
    intent.look_x, intent.look_y = s.look_x or 0, s.look_y or 0
end

function M.record(drive, motion)
    drive.ticks, drive.tick = drive.ticks+1, drive.tick+1
    drive.max_y, drive.min_y = math.max(drive.max_y, motion.position.y), math.min(drive.min_y, motion.position.y)
    if motion.jumped then drive.jumps = drive.jumps+1 end
    if motion.landed then drive.landings = drive.landings+1 end
    if motion.grounded then drive.grounded_ticks = drive.grounded_ticks+1 end
    if drive.tick == drive.segments[drive.index].ticks then
        drive.index, drive.tick = drive.index+1, 0
        drive.complete = drive.index > #drive.segments
        if drive.complete then
            drive.result = { x = motion.position.x, y = motion.position.y, z = motion.position.z,
                grounded = motion.grounded, stance = motion.stance, height = motion.height,
                yaw = motion.yaw, pitch = motion.pitch, recovery_failed = motion.recovery_failed,
                max_y = drive.max_y, min_y = drive.min_y, jumps = drive.jumps,
                landings = drive.landings, grounded_ticks = drive.grounded_ticks, ticks = drive.ticks }
        end
    end
end

return M
