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

print(count.." movement tests passed")
