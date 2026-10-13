local combat = require "game.combat"
local capsule = require "game.player.capsule"
local tuning = require "game.player.tuning"
local events = require "game.events"
local driver = require "game.player.driver"
local M = {}

function M.init(ctx)
    local spawn = ctx.world.spawn
    ctx.player = {
        actor = combat.register(ctx.combat, "player", ctx.config.player_health),
        previous = { x = spawn.x, y = spawn.y, z = spawn.z },
        position = { x = spawn.x, y = spawn.y, z = spawn.z },
        intent = { move_x = 0, move_z = 0, look_x = 0, look_y = 0 },
        enabled = true, footstep_distance = 0,
        previous_yaw = 0, previous_pitch = 0, previous_eye = ctx.config.eye_height,
    }
    ctx.player.motion = capsule.new(ctx.player.position)
end

function M.reset(ctx, point, yaw)
    local player = ctx.player
    capsule.reset(player.motion, point, yaw)
    player.previous.x, player.previous.y, player.previous.z = point.x, point.y, point.z
    player.previous_yaw, player.previous_pitch = player.motion.yaw, 0
    player.previous_eye = player.motion.eye
    player.footstep_distance = 0
    if ctx.services.capsule then ctx.services.capsule:sync(player.position, player.motion.height) end
end

function M.fixed_update(ctx, dt)
    local player = ctx.player
    local previous, position = player.previous, player.position
    previous.x, previous.y, previous.z = position.x, position.y, position.z
    local motion = player.motion
    player.previous_yaw, player.previous_pitch = motion.yaw, motion.pitch
    player.previous_eye = motion.eye-motion.step_offset
    local buttons, intent = ctx.input.buttons, player.intent
    local alive = player.actor.alive and player.enabled
    intent.move_x = alive and ((buttons.right.held and 1 or 0) - (buttons.left.held and 1 or 0)) or 0
    intent.move_z = alive and ((buttons.back.held and 1 or 0) - (buttons.forward.held and 1 or 0)) or 0
    local length = math.sqrt(intent.move_x * intent.move_x + intent.move_z * intent.move_z)
    if length > 1 then
        intent.move_x, intent.move_z = intent.move_x / length, intent.move_z / length
    end
    intent.look_x, intent.look_y = alive and ctx.input.look_x or 0, alive and ctx.input.look_y or 0
    intent.jump = alive and buttons.jump.pressed
    intent.sprint = alive and buttons.sprint.held
    intent.crouch = alive and buttons.crouch.held
    intent.prone = alive and buttons.prone.held
    intent.aim = alive and buttons.aim.held
    intent.lean = alive and ((buttons.lean_right.held and 1 or 0) - (buttons.lean_left.held and 1 or 0)) or 0
    local drive = player.drive
    if drive and not drive.complete and alive then driver.input(drive, intent) end
    if not ctx.world.ready or not ctx.services.capsule then return end
    capsule.update(motion, intent, dt, ctx.services.capsule)
    if drive and not drive.complete then driver.record(drive, motion) end
    if motion.landed then
        events.emit(ctx.events, events.PLAYER_LAND, { velocity = motion.impact_speed, surface = motion.surface })
        player.footstep_distance = 0
    end
    if motion.grounded then
        player.footstep_distance = player.footstep_distance + motion.travel
        if player.footstep_distance >= tuning.stances[motion.stance].stride then
            player.footstep_distance = player.footstep_distance % tuning.stances[motion.stance].stride
            events.emit(ctx.events, events.PLAYER_FOOTSTEP, { position = position, surface = motion.surface, running = motion.sprinting })
        end
    end
    if player.last_stance ~= motion.stance or player.last_sprint ~= motion.sprinting or player.last_aim ~= intent.aim then
        player.last_stance, player.last_sprint, player.last_aim = motion.stance, motion.sprinting, intent.aim
        events.emit(ctx.events, events.PLAYER_STATE, { stance = motion.stance, sprinting = motion.sprinting, sliding = false, ads = intent.aim })
    end
    -- The excerpt has open map edges. Recover a fall without changing health.
    if position.y < -12 and player.actor.alive then M.reset(ctx, ctx.world.spawn, 0) end
end

function M.final(ctx)
    combat.remove(ctx.combat, "player")
    ctx.player = nil
end

return M
