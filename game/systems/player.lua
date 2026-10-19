local combat = require "game.combat"
local capsule = require "game.player.capsule"
local tuning = require "game.player.tuning"
local events = require "game.events"
local driver = require "game.player.driver"
local lean = require "game.player.lean"
local camera = require "game.player.camera"
local health = require "game.player.health"
local health_tuning = require "game.player.health_tuning"
local M = {}

function M.camera_impulse(ctx, kind, strength, direction)
    if ctx.paused or not ctx.world.ready or not ctx.player.enabled or not ctx.player.actor.alive then return false end
    camera.impulse(ctx.player.camera, kind, strength, direction, ctx.player.motion.yaw)
    return true
end

function M.init(ctx)
    local spawn = ctx.world.spawn
    ctx.player = {
        actor = combat.register(ctx.combat, "player", ctx.config.player_health, health_tuning.regeneration),
        previous = { x = spawn.x, y = spawn.y, z = spawn.z },
        position = { x = spawn.x, y = spawn.y, z = spawn.z },
        intent = { move_x = 0, move_z = 0, look_x = 0, look_y = 0 },
        enabled = true, footstep_distance = 0,
        previous_yaw = 0, previous_pitch = 0, previous_eye = ctx.config.eye_height,
        previous_lean = 0,
    }
    ctx.player.motion = capsule.new(ctx.player.position)
    ctx.player.camera = camera.new()
    health.init(ctx)
    events.on(ctx.events, events.CAMERA_IMPULSE, ctx.player, function(_, cue)
        M.camera_impulse(ctx, cue.kind, cue.strength, cue.direction)
    end)
end

function M.reset(ctx, point, yaw)
    local player = ctx.player
    capsule.reset(player.motion, point, yaw)
    player.previous.x, player.previous.y, player.previous.z = point.x, point.y, point.z
    player.previous_yaw, player.previous_pitch = player.motion.yaw, 0
    player.previous_eye = player.motion.eye
    player.previous_lean = 0
    player.footstep_distance = 0
    camera.reset(player.camera)
    if ctx.weapons then ctx.weapons.motion=require("game.weapons.motion").new() end
    player.camera_disabled = false
    -- Reset must also place the displayed eye when a paused frame skips update.
    camera.compose(ctx, 1, ctx.presentation)
    ctx.presentation.health = player.actor.health
    if ctx.services.capsule then ctx.services.capsule:sync(player.position, player.motion.height) end
end

function M.fixed_update(ctx, dt)
    local player = ctx.player
    local previous, position = player.previous, player.position
    previous.x, previous.y, previous.z = position.x, position.y, position.z
    local motion = player.motion
    player.previous_yaw, player.previous_pitch = motion.yaw, motion.pitch
    player.previous_eye, player.previous_lean = lean.eye(motion), motion.lean
    local buttons, intent = ctx.input.buttons, player.intent
    local alive = player.actor.alive and player.enabled
    if not alive and not player.camera_disabled then camera.reset(player.camera) end
    player.camera_disabled = not alive
    health.fixed_update(ctx, dt)
    intent.enabled = alive
    intent.move_x = alive and (ctx.input.move_x + (buttons.right.held and 1 or 0) - (buttons.left.held and 1 or 0)) or 0
    intent.move_z = alive and (ctx.input.move_z + (buttons.back.held and 1 or 0) - (buttons.forward.held and 1 or 0)) or 0
    local length = math.sqrt(intent.move_x * intent.move_x + intent.move_z * intent.move_z)
    if length > 1 then
        intent.move_x, intent.move_z = intent.move_x / length, intent.move_z / length
    end
    intent.look_x, intent.look_y = alive and ctx.input.look_x or 0, alive and ctx.input.look_y or 0
    intent.jump = alive and buttons.jump.pressed
    intent.jump_held = alive and buttons.jump.held
    intent.sprint = alive and buttons.sprint.held
    intent.sprint_pressed = alive and buttons.sprint.pressed
    intent.crouch = alive and buttons.crouch.held
    intent.crouch_pressed = alive and buttons.crouch.pressed
    intent.prone = alive and buttons.prone.held
    intent.aim = alive and buttons.aim.held
    intent.lean = alive and ((buttons.lean_right.held and 1 or 0) - (buttons.lean_left.held and 1 or 0)) or 0
    local drive = player.drive
    if drive and not drive.complete and alive then driver.input(drive, intent) end
    if not ctx.world.ready or not ctx.services.capsule then return end
    capsule.update(motion, intent, dt, ctx.services.capsule)
    if drive and not drive.complete then driver.record(drive, motion) end
    if player.gait_stance ~= motion.stance then
        player.footstep_distance, player.camera.phase, player.gait_stance = 0, 0, motion.stance
    end
    if motion.landed then
        if alive then camera.land(player.camera, motion.impact_speed) end
        if alive and motion.impact_speed > health_tuning.fall_speed then
            combat.request(ctx.combat,{target="player",kind="fall",
                amount=(motion.impact_speed-health_tuning.fall_speed)*health_tuning.fall_damage_per_speed})
        end
        events.emit(ctx.events, events.PLAYER_LAND, { velocity = motion.impact_speed, surface = motion.surface })
        player.footstep_distance = 0
        player.camera.phase = 0
    end
    if motion.grounded and not motion.sliding and not motion.mantle and not motion.mantle_completed then
        player.footstep_distance = player.footstep_distance + motion.travel
        if player.footstep_distance >= tuning.stances[motion.stance].stride then
            player.footstep_distance = player.footstep_distance % tuning.stances[motion.stance].stride
            if alive then camera.footstep(player.camera, motion.sprinting, motion.stance) end
            events.emit(ctx.events, events.PLAYER_FOOTSTEP, { position = position, surface = motion.surface, running = motion.sprinting })
        end
    end
    if motion.slide_started or motion.slide_ended or motion.mantle_started or motion.mantle_completed or motion.mantle_aborted then
        player.footstep_distance = 0
        player.camera.phase = 0
    end
    if player.last_stance ~= motion.stance or player.last_sprint ~= motion.sprinting or player.last_aim ~= intent.aim
        or player.last_slide ~= motion.sliding or player.last_tactical ~= motion.tactical or player.last_mantle ~= (motion.mantle ~= false) then
        player.last_stance, player.last_sprint, player.last_aim = motion.stance, motion.sprinting, intent.aim
        player.last_slide, player.last_tactical, player.last_mantle = motion.sliding, motion.tactical, motion.mantle ~= false
        events.emit(ctx.events, events.PLAYER_STATE, { stance = motion.stance, sprinting = motion.sprinting,
            sliding = motion.sliding, tactical = motion.tactical, mantling = motion.mantle ~= false,
            vaulting = motion.mantle and motion.mantle.kind == "vault" or false, ads = intent.aim })
    end
    -- The excerpt has open map edges. Recover a fall without changing health.
    if position.y < -12 and player.actor.alive then M.reset(ctx, ctx.world.spawn, 0) end
end

function M.final(ctx)
    events.off_owner(ctx.events, ctx.player)
    combat.remove(ctx.combat, "player")
    ctx.player = nil
end

return M
