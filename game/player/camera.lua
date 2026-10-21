-- Reference camera tuning, advanced only by fixed simulation ticks.
local T = require "game.player.tuning"
local V = require "game.weapons.math"
local lean = require "game.player.lean"
local defs = require "game.weapons.defs"
local C = T.camera
local M = {}
local fields = { "x", "y", "z", "pitch", "yaw", "roll", "fov" }
local channels = { damage = {0.045, 0.024, 0.035, 0.22},
    suppression = {0.012, 0.009, 0.012, 0.12}, explosion = {0.07, 0.045, 0.06, 0.6} }
local function approach(a, b, tau, dt) return a+(b-a)*(1-math.exp(-dt/tau)) end
local function clamp01(x) return V.clamp(x, 0, 1) end
local function smooth(x) x = clamp01(x); return x*x*(3-2*x) end
local function output()
    return { x=0, y=0, z=0, pitch=0, yaw=0, roll=0, fov=C.fov.base }
end
local function kick(axis, amount, share, limit)
    local value = axis.x+(axis.residual or 0)
    local delta = V.clamp(value+amount, -limit, limit)-value
    axis.x = axis.x+delta*(1-share)
    axis.residual = (axis.residual or 0)+delta*share
end

function M.new()
    return { previous=output(), current=output(), dip=V.spring(), step=V.spring(),
        pitch=V.spring(), yaw=V.spring(), roll=V.spring(), phase=0, breath=0, shake_time=0,
        weight=0, strafe=0, turn=0, slide=0, slide_roll=0, air=0, side=1,
        trauma=0, suppression=0, fov_move=1, fov_ads=1 }
end

function M.reset(rig)
    for k, v in pairs(M.new()) do rig[k] = v end
end

function M.land(rig, speed)
    local mag = clamp01((speed-C.land.min_speed)/(C.land.full_speed-C.land.min_speed))^0.72
    rig.dip.v = rig.dip.v-C.land.impulse*mag
    kick(rig.pitch, C.land.pitch*mag, 0.34, 0.25)
    kick(rig.roll, C.land.roll*mag*rig.side, 0.24, 0.25)
    rig.trauma = clamp01(rig.trauma+C.land.trauma*mag*mag)
end

function M.footstep(rig, running, stance)
    local scale = stance == "crouch" and 0.55 or stance == "prone" and 0.3 or 1
    rig.step.v = rig.step.v-C.step.impulse*(running and C.step.sprint_scale or 1)*scale
end

-- Direction points toward the source in world space; channels never apply damage.
function M.impulse(rig, kind, strength, direction, yaw)
    local c = assert(channels[kind], "Unknown camera impulse channel")
    assert(type(strength) == "number" and strength == strength and strength >= 0 and strength < math.huge,
        "Camera strength must be finite and nonnegative")
    strength = clamp01(strength)
    local right, forward = 0, 1
    if direction then
        for _, k in ipairs({"x", "y", "z"}) do
            local n = direction[k] or 0
            assert(type(n) == "number" and n == n and math.abs(n) < math.huge, "Invalid camera direction")
        end
        local x, z = direction.x or 0, direction.z or 0
        local length = math.sqrt(x*x+z*z)
        if length > 1e-6 then
            right = (math.cos(yaw)*x-math.sin(yaw)*z)/length
            forward = (-math.sin(yaw)*x-math.cos(yaw)*z)/length
        end
    end
    kick(rig.pitch, c[1]*strength*forward, 0.34, 0.25)
    kick(rig.yaw, -c[2]*strength*right, 0.34, 0.18)
    kick(rig.roll, -c[3]*strength*right, 0.24, 0.25)
    rig.trauma = clamp01(rig.trauma+c[4]*strength)
    if kind == "suppression" then rig.suppression = clamp01(rig.suppression+strength) end
end

function M.update(ctx, dt)
    local player, w = ctx.player, ctx.weapons
    local rig, m = player.camera, player.motion
    for _, k in ipairs(fields) do rig.previous[k] = rig.current[k] end
    local ads = w and V.smooth(w.ads) or 0
    local speed = math.sqrt(m.velocity.x^2+m.velocity.z^2)
    local moving = m.grounded and not m.sliding and not m.mantle and not m.mantle_completed
    if moving then rig.phase = (rig.phase+m.travel/T.stances[m.stance].stride*math.pi)%(4*math.pi) end
    local weight = moving and math.min(C.bob.speed_cap, (speed/4.57)^C.bob.speed_exp) or 0
    weight = weight*(1-(1-C.bob.ads_scale)*ads)*(m.stance == "prone" and 0.35 or 1)
    rig.weight = approach(rig.weight, weight, C.bob.tau, dt)
    if m.slide_started then
        rig.side = player.intent.move_x < 0 and -1 or 1
        rig.dip.v = rig.dip.v-0.9
        rig.trauma = clamp01(rig.trauma+0.12)
    end
    if m.mantle_started then
        rig.trauma = clamp01(rig.trauma+(m.vault_started and 0.08 or 0.14))
    end
    V.step(rig.dip, dt, C.land.frequency, C.land.damping)
    V.step(rig.step, dt, C.step.frequency, C.step.damping)
    V.step(rig.pitch, dt, 9.5, 0.5)
    V.step(rig.yaw, dt, 9.5*1.08, 0.56)
    V.step(rig.roll, dt, 9.5*0.86, 0.6)
    for _, k in ipairs({"pitch", "yaw", "roll"}) do
        rig[k].residual = (rig[k].residual or 0)*math.exp(-dt/0.28)
    end
    local R = C.roll
    rig.strafe = approach(rig.strafe, -player.intent.move_x*R.strafe*(m.grounded and 1 or 0.45)*(1-0.6*ads), R.tau, dt)
    rig.turn = approach(rig.turn, V.clamp((m.yaw-player.previous_yaw)/dt*R.yaw_rate, -R.turn_max, R.turn_max)*(1-0.5*ads), R.tau*1.4, dt)
    rig.slide_roll = approach(rig.slide_roll, m.sliding and -rig.side*R.slide or 0, 0.1, dt)
    rig.air = approach(rig.air, m.grounded and 0 or V.clamp(-m.velocity.y*0.02, -1, 1)*R.air, 0.22, dt)
    local slide_target = m.sliding and 1-0.45*clamp01(m.slide_time/T.slide.duration) or 0
    rig.slide = approach(rig.slide, slide_target, m.sliding and 0.045 or 0.09, dt)
    rig.trauma = math.max(0, rig.trauma-1.85*dt)
    rig.suppression = math.max(0, rig.suppression-dt*0.8)
    rig.shake_time = (rig.shake_time+dt*22)%(2*math.pi*100)
    -- Deterministic, decorrelated shake never consumes a gameplay random stream.
    local shake, t = rig.trauma^2, rig.shake_time
    local sx = math.sin(t*1.3+13.3)*shake*0.022
    local sy = math.sin(t*1.7+71.9)*shake*0.022
    local sp = math.sin(t*2.3+11)*shake*math.rad(1.35)
    local sw = math.sin(t*1.9+23)*shake*math.rad(1.35)
    local sr = math.sin(t*2.7+37)*shake*math.rad(1.35)*0.7
    local B, move = C.breath, clamp01(speed/2.2)
    local health = clamp01(player.actor.health/player.actor.max_health)
    local amp = B.amplitude*(1+(B.ads_scale-1)*ads)*(1+(B.health_scale-1)*(1-health))
        *(1+(B.suppression_scale-1)*math.max(rig.suppression,
            player.health_state and player.health_state.suppression or 0))*(1-B.move_damp*move)
    rig.breath = (rig.breath+dt)%200 -- Both reference frequencies repeat after 200 seconds.
    local ba, bb = math.sin(rig.breath*2*math.pi*B.a), math.sin(rig.breath*2*math.pi*B.b+1.7)
    local my, mf, mp, mr = 0, 0, 0, 0
    if m.mantle then
        local path = m.mantle
        local u = clamp01(path.time/path.duration)
        local arc = math.sin(u*math.pi)
        if path.kind == "vault" then
            my, mf, mp, mr = -0.045*arc, 0.04*arc, -math.rad(3.1)*arc, (path.side or 1)*math.rad(2.3)*arc
        else
            local load = math.sin(clamp01(u/0.34)*math.pi)*(1-smooth((u-0.5)/0.5))
            my = -0.075*load+0.03*math.sin(clamp01((u-0.55)/0.45)*math.pi)
            mf, mp = 0.05*arc, -math.rad(5.2)*load+math.rad(2.1)*smooth((u-0.6)/0.4)
            -- Settle the final pitch before releasing the rooted move.
            mp = mp*(1-smooth((u-0.9)/0.1))
            mr = (path.side or 1)*math.rad(3.2)*arc
        end
    end
    local phase, wt, out = rig.phase+math.pi*0.5, rig.weight, rig.current
    out.x = math.sin(phase)*C.bob.x*wt+sx
    out.y = math.sin(phase*2)*C.bob.y*wt+rig.dip.x+rig.step.x+sy+my
        +(ba*0.6+bb*0.4)*B.position*(1-0.8*move)-rig.slide*0.1
    out.z = math.cos(phase*2)*C.bob.z*wt+mf+rig.slide*0.045
    out.pitch = rig.pitch.x+rig.pitch.residual+(ba*0.7+bb*0.3)*amp+math.cos(phase*2)*C.bob.pitch*wt+sp+mp
    out.yaw = rig.yaw.x+rig.yaw.residual+(bb*0.75-ba*0.25)*amp*1.15+sw
    out.roll = rig.strafe+rig.turn+rig.slide_roll+rig.air-math.sin(phase)*C.bob.roll*wt+rig.roll.x+rig.roll.residual+sr+mr
    local F = C.fov
    local target = m.sliding and F.slide or m.tactical and F.tactical or m.sprinting and F.sprint
        or (not m.grounded and m.velocity.y < -6) and F.air or 1
    rig.fov_move = approach(rig.fov_move, target, F.move_tau, dt)
    rig.fov_ads = approach(rig.fov_ads, 1+((w and defs[w.equipped].adsFov or 1)-1)*ads, F.ads_tau, dt)
    out.fov = math.rad(ctx.preferences and ctx.preferences.fov or math.deg(F.base))*rig.fov_move*rig.fov_ads
end

-- The rendered eye and authoritative firing eye share the same composition.
function M.compose(ctx, alpha, out)
    local p, m = ctx.player, ctx.player.motion
    local rig = p.camera
    local function sample(k) return rig and V.lerp(rig.previous[k], rig.current[k], alpha) or 0 end
    local position = out.position or {}
    for _, k in ipairs({"x", "y", "z"}) do position[k] = V.lerp(p.previous[k], p.position[k], alpha) end
    out.position = position
    local eye = math.min(m.height-0.1, V.lerp(p.previous_eye, lean.eye(m), alpha))
    local yaw = V.lerp(p.previous_yaw, m.yaw, alpha)
    local base = out.camera or {}
    base.x, base.y, base.z = position.x, position.y+eye, position.z
    local amount = V.lerp(p.previous_lean, m.lean, alpha)
    base.x, base.y, base.z, out.roll = lean.apply(ctx.services.capsule, base, yaw, amount)
    local x, y, z = sample("x"), sample("y"), sample("z")
    y = V.clamp(y, position.y+C.wall_radius+T.skin-base.y, position.y+m.height-0.1-base.y)
    local dx, dz = math.cos(yaw)*x-math.sin(yaw)*z, -math.sin(yaw)*x-math.cos(yaw)*z
    local fraction = 1
    if ctx.services.capsule and dx*dx+y*y+dz*dz > 1e-12 then
        fraction = ctx.services.capsule:camera_fraction(base, dx, y, dz, C.wall_radius)
    end
    base.x, base.y, base.z = base.x+dx*fraction, base.y+y*fraction, base.z+dz*fraction
    out.camera, out.yaw = base, yaw+sample("yaw")
    out.pitch = V.clamp(V.lerp(p.previous_pitch, m.pitch, alpha)+sample("pitch"), -T.pitch_limit, T.pitch_limit)
    out.roll = out.roll+sample("roll")
    out.fov = rig and sample("fov") or C.fov.base
    return out
end

return M
