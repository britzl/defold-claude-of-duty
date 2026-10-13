-- Fast movement rules tests; actual Bullet geometry is covered by movement_smoke.py.
package.path = "./?.lua;" .. package.path
local capsule = require "game.player.capsule"
local tuning = require "game.player.tuning"
local runtime = require "game.runtime"
local input = require "game.input"
local events = require "game.events"
local h, count = 1/120, 0
local function test(name, run)
    run(); count = count+1; print("PASS "..name)
end
local function near(a, b, tolerance) assert(math.abs(a-b) < (tolerance or 1e-7), a.." != "..b) end

-- Analytic horizontal planes keep timing tests independent of the controller
-- and engine. Native tests exercise edges, corners, stairs and rotated boxes.
local function planes()
    local q = { floor = true, ceiling = math.huge, calls = 0 }
    function q:sync() self.calls = self.calls+1 end
    function q:ray() return nil end
    function q:camera_fraction() return 1 end
    function q:contacts(p, height)
        self.calls = self.calls+1
        local out = {}
        if self.floor and p.y < 0 then out[#out+1] = { distance = p.y, nx = 0, ny = 1, nz = 0 } end
        if p.y+height > self.ceiling then
            out[#out+1] = { distance = self.ceiling-p.y-height, nx = 0, ny = -1, nz = 0 }
        end
        return out
    end
    function q:fits(p, height) return (not self.floor or p.y >= -0.0001) and p.y+height <= self.ceiling+0.0001 end
    function q:sweep(p, height, dx, dy, dz)
        self.calls = self.calls+1
        local fraction, normal
        if self.floor and dy < 0 and p.y+dy <= 0 and p.y >= 0 then fraction, normal = -p.y/dy, 1 end
        if dy > 0 and p.y+height+dy >= self.ceiling then fraction, normal = (self.ceiling-p.y-height)/dy, -1 end
        if fraction then return { fraction = fraction, nx = 0, ny = normal, nz = 0, surface = "concrete" } end
    end
    return q
end
local function idle(extra)
    local i = { move_x = 0, move_z = 0 }
    for k, v in pairs(extra or {}) do i[k] = v end
    return i
end
local function new()
    local m, q = capsule.new({ x = 0, y = tuning.skin, z = 0 }), planes()
    capsule.update(m, idle(), h, q)
    return m, q
end

test("jump has the tuned apex, lands once and cannot repeat without an edge", function()
    local m, q = new()
    local apex, jumps, lands = 0, 0, 0
    for tick = 1, 240 do
        capsule.update(m, idle({ jump = tick == 1 }), h, q)
        apex = math.max(apex, m.position.y)
        jumps, lands = jumps+(m.jumped and 1 or 0), lands+(m.landed and 1 or 0)
    end
    near(apex, 0.6, 0.025)
    assert(jumps == 1 and lands == 1 and m.grounded)
end)

test("a buffered press just before landing jumps on the following tick", function()
    local m, q = new()
    capsule.reset(m, { x = 0, y = 0.15, z = 0 })
    m.velocity.y = -1
    local jumped = false
    for tick = 1, 20 do
        capsule.update(m, idle({ jump = tick == 1 }), h, q)
        jumped = jumped or m.jumped
    end
    assert(jumped and m.position.y > 0.25)
end)

test("coyote jump works within grace and fails after grace expires", function()
    for _, delay in ipairs({ 4, 16 }) do
        local m, q = new()
        q.floor = false
        for _ = 1, delay do capsule.update(m, idle(), h, q) end
        capsule.update(m, idle({ jump = true }), h, q)
        assert(m.jumped == (delay == 4))
    end
end)

test("stance clearance keeps feet fixed and allows expansion when the ceiling clears", function()
    local m, q = new()
    capsule.update(m, idle({ crouch = true }), h, q)
    q.ceiling = 1.25
    for _ = 1, 30 do capsule.update(m, idle(), h, q) end
    assert(m.stance == "crouch" and m.height == 1.12)
    near(m.position.y, tuning.skin)
    q.ceiling = math.huge
    capsule.update(m, idle(), h, q)
    assert(m.stance == "stand" and m.height == 1.78)
    capsule.update(m, idle({ prone = true, jump = true }), h, q)
    assert(m.stance == "prone" and not m.jumped)
end)

test("look uses pixels once, clamps pitch, and rotates the movement basis", function()
    local m, q = new()
    capsule.update(m, idle({ look_x = -math.pi/2/tuning.mouse_sensitivity, look_y = 100000 }), h, q)
    near(m.yaw, math.pi/2); near(m.pitch, tuning.pitch_limit)
    for _ = 1, 120 do capsule.update(m, idle({ move_z = -1 }), h, q) end
    assert(m.position.x < -4.4 and math.abs(m.position.z) < 1e-6)
end)

test("loading gates physics queries and movement", function()
    local q = planes()
    local ctx = runtime.new({ capsule = q })
    input.button(ctx.input, "forward", { pressed = true })
    for _ = 1, 120 do runtime.fixed_update(ctx, h) end
    assert(q.calls == 0 and ctx.player.position.z == ctx.world.spawn.z)
    ctx.world.ready = true
    runtime.fixed_update(ctx, h)
    assert(q.calls > 0 and ctx.player.position.z < ctx.world.spawn.z)
    runtime.final(ctx)
end)

test("movement and notifications agree at 30, 60 and 144 rendered frames per second", function()
    local reference
    for _, fps in ipairs({ 30, 60, 144 }) do
        local ctx = runtime.new({ capsule = planes() })
        ctx.world.ready = true
        local steps, lands, aim_changes = 0, 0, 0
        events.on(ctx.events, events.PLAYER_FOOTSTEP, ctx, function() steps = steps+1 end)
        events.on(ctx.events, events.PLAYER_LAND, ctx, function() lands = lands+1 end)
        events.on(ctx.events, events.PLAYER_STATE, ctx, function(_, state) if state.ads then aim_changes = aim_changes+1 end end)
        input.button(ctx.input, "forward", { pressed = true })
        local accumulated = 0
        for _ = 1, fps*3 do
            accumulated = accumulated+1/fps
            while accumulated+1e-10 >= h do
                if ctx.time.tick == 60 then input.button(ctx.input, "jump", { pressed = true }) end
                if ctx.time.tick == 240 then input.button(ctx.input, "aim", { pressed = true }) end
                runtime.fixed_update(ctx, h)
                accumulated = accumulated-h
            end
            runtime.update(ctx, 1/fps)
        end
        local p = ctx.player.position
        if reference then near(p.x, reference.x); near(p.y, reference.y); near(p.z, reference.z)
        else reference = { x = p.x, y = p.y, z = p.z } end
        assert(steps >= 5 and lands == 2 and aim_changes == 1)
        assert(ctx.player.motion.grounded and ctx.presentation.camera.y > 1.6)
        runtime.final(ctx)
    end
end)

test("double-tap sprint is bounded, requires forward input and cannot bypass recovery", function()
    local m, q = new()
    local sprint = idle({ sprint = true, move_z = -1 })
    for _ = 1, 12 do capsule.update(m, sprint, h, q) end
    assert(not m.tactical)
    capsule.update(m, idle({ move_z = -1 }), h, q)
    for _ = 1, 30 do capsule.update(m, sprint, h, q) end
    assert(m.tactical); near(-m.velocity.z, 8.38)
    for _ = 1, 720 do capsule.update(m, sprint, h, q) end
    assert(not m.tactical and m.tactical_cooldown > 1)
    capsule.update(m, idle(), h, q)
    capsule.update(m, sprint, h, q)
    assert(not m.tactical)
    for _ = 1, 240 do capsule.update(m, idle(), h, q) end
    capsule.update(m, sprint, h, q)
    capsule.update(m, idle(), h, q)
    capsule.update(m, sprint, h, q)
    assert(m.tactical)
    capsule.update(m, idle({ sprint = true, move_z = -1, aim = true }), h, q)
    assert(not m.tactical and not m.sprinting and m.tactical_cooldown > 1.5)
    for _ = 1, 240 do capsule.update(m, idle(), h, q) end
    capsule.update(m, idle({ sprint = true, move_z = 1 }), h, q)
    capsule.update(m, idle(), h, q)
    capsule.update(m, idle({ sprint = true, move_z = 1 }), h, q)
    assert(not m.tactical and not m.sprinting)
end)

local function begin_slide()
    local m, q = new()
    for _ = 1, 30 do capsule.update(m, idle({ move_z = -1, sprint = true }), h, q) end
    capsule.update(m, idle({ move_z = -1, sprint = true, crouch = true }), h, q)
    assert(m.sliding and m.slide_started and m.height == 1.12)
    return m, q
end

test("slide bursts once, decays, steers without reversing and ends on time", function()
    local m, q = begin_slide()
    assert(-m.velocity.z > 8.7 and -m.velocity.z <= tuning.slide.entry_speed)
    for _ = 1, 50 do capsule.update(m, idle({ move_z = 1, crouch = true }), h, q) end
    assert(m.sliding and m.velocity.z < -4)
    for _ = 1, 75 do
        capsule.update(m, idle({ move_z = -1, sprint = true, crouch = true }), h, q)
        assert(not m.slide_started)
    end
    assert(not m.sliding and m.stance == "crouch")
end)

test("slide jumps cap momentum; a held crouch cannot chain new bursts", function()
    local m, q = begin_slide()
    capsule.update(m, idle({ jump = true, move_z = -1 }), h, q)
    assert(m.jumped and m.slide_ended and not m.sliding)
    assert(math.sqrt(m.velocity.x^2+m.velocity.z^2) <= tuning.slide.jump_speed_cap+1e-7)
    assert(m.slide_cooldown > 0)
    for _ = 1, 180 do
        capsule.update(m, idle({ move_z = -1, sprint = true, crouch = true }), h, q)
        assert(not m.slide_started)
    end
end)

test("slide requires sprint momentum and cancels when controls are disabled", function()
    local m, q = new()
    capsule.update(m, idle({ sprint = true, crouch = true, move_z = -1 }), h, q)
    assert(not m.sliding)
    m, q = begin_slide()
    capsule.update(m, idle({ enabled = false }), h, q)
    assert(not m.sliding and not m.tactical and not m.sprinting)
end)

test("gravity helps a downhill slide and slows an uphill slide", function()
    local moves = require "game.player.moves"
    local a, b = new(), new()
    a.ground.y, a.ground.z = math.cos(math.rad(30)), math.sin(math.rad(30))
    b.ground.y, b.ground.z = a.ground.y, a.ground.z
    a.velocity.z, b.velocity.z = 7, -7
    moves.accelerate_slide(a, idle(), h)
    moves.accelerate_slide(b, idle(), h)
    assert(a.velocity.z > -b.velocity.z)
end)

test("lean keeps the capsule fixed, retracts on obstruction and returns to centre", function()
    local m, q = new()
    for _ = 1, 120 do capsule.update(m, idle({ lean = 1 }), h, q) end
    assert(m.lean > 0.999)
    near(m.position.x, 0); near(m.position.z, 0)
    function q:camera_fraction(origin, dx)
        if dx <= 0 then return 1 end
        return math.max(0, math.min(1, (0.25-origin.x-tuning.lean.radius-tuning.skin)/dx))
    end
    capsule.update(m, idle({ lean = 1 }), h, q)
    assert(m.lean*tuning.lean.offset <= 0.25-tuning.lean.radius-tuning.skin+1e-7)
    for _ = 1, 120 do capsule.update(m, idle(), h, q) end
    near(m.lean, 0)
    for _ = 1, 120 do capsule.update(m, idle({ lean = 1, sprint = true, move_z = -1 }), h, q) end
    near(m.lean, 0)
end)

test("a blocked or disabled mantle stops at its last clear position", function()
    local mantle = require "game.player.mantle"
    for _, mode in ipairs({ "sweep", "overlap", "disabled" }) do
        local m, q = new()
        m.mantle = { start = { x = 0, y = 0, z = 0 }, up = { x = 0, y = 1.2, z = 0 },
            over = { x = 0, y = 1.2, z = -1 }, target = { x = 0, y = 1.204, z = -1 },
            time = 0, duration = 0.62, finish_stance = "stand", fx = 0, fz = -1 }
        for _ = 1, 10 do mantle.update(m, idle(), h, q) end
        local y, z = m.position.y, m.position.z
        if mode == "sweep" then
            function q:sweep() return { fraction = 0.2, nx = 0, ny = -1, nz = 0 } end
        elseif mode == "overlap" then
            function q:fits(p) return p ~= m.position end
        end
        mantle.update(m, idle({ enabled = mode ~= "disabled" }), h, q)
        assert(not m.mantle and m.mantle_aborted and not m.grounded)
        near(m.position.y, y); near(m.position.z, z)
    end
end)

test("render interpolation rechecks leaned camera clearance without moving the actor", function()
    local q = planes()
    local ctx = runtime.new({ capsule = q })
    ctx.player.position.x, ctx.player.previous.x = 0, -0.1
    ctx.player.motion.lean, ctx.player.previous_lean, ctx.time.alpha = 1, 1, 0.5
    local probes = 0
    function q:camera_fraction(origin, dx)
        probes = probes+1
        return math.max(0, math.min(1, (0.25-origin.x-tuning.lean.radius-tuning.skin)/dx))
    end
    require("game.presentation").update(ctx)
    near(ctx.player.position.x, 0)
    assert(probes == 1 and ctx.presentation.camera.x <= 0.25-tuning.lean.radius-tuning.skin+1e-7)
    assert(ctx.presentation.roll < 0)
    runtime.final(ctx)
end)

test("tactical/slide edges and lean stay identical at 30, 60 and 144 presentation FPS", function()
    local reference
    for _, fps in ipairs({ 30, 60, 144 }) do
        local ctx = runtime.new({ capsule = planes() })
        ctx.world.ready = true
        local states = {}
        events.on(ctx.events, events.PLAYER_STATE, ctx, function(_, s)
            if s.sliding then states.slide = true end
            if s.tactical then states.tactical = true end
        end)
        local changes = {
            [0] = { {"forward", true}, {"sprint", true} }, [12] = { {"sprint", false} },
            [20] = { {"sprint", true} }, [60] = { {"crouch", true} }, [70] = { {"crouch", false} },
            [80] = { {"jump", true} }, [81] = { {"jump", false} },
            [200] = { {"forward", false}, {"sprint", false} }, [240] = { {"lean_left", true} },
        }
        local accumulated = 0
        for _ = 1, fps*3 do
            accumulated = accumulated+1/fps
            while accumulated+1e-10 >= h do
                for _, change in ipairs(changes[ctx.time.tick] or {}) do
                    input.button(ctx.input, change[1], { pressed = change[2], released = not change[2] })
                end
                runtime.fixed_update(ctx, h)
                accumulated = accumulated-h
            end
            runtime.update(ctx, 1/fps)
        end
        local m = ctx.player.motion
        assert(states.slide and states.tactical and m.lean < -0.999 and m.grounded)
        if reference then near(m.position.z, reference.z); near(m.lean, reference.lean)
        else reference = { z = m.position.z, lean = m.lean } end
        runtime.final(ctx)
    end
end)

print(count.." movement tests passed")
