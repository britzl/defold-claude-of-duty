-- Run from the project root with Lua 5.1+ or LuaJIT: lua tests/runtime_test.lua
package.path = "./?.lua;" .. package.path
local runtime = require "game.runtime"
local events = require "game.events"
local input = require "game.input"
local combat = require "game.combat"
local h = 1 / 120
local count = 0

local function near(actual, expected)
    assert(math.abs(actual - expected) < 1e-7, tostring(actual) .. " != " .. tostring(expected))
end

local function test(name, run)
    run()
    count = count + 1
    print("PASS " .. name)
end

test("a quick press/release survives render frames and is consumed once", function()
    local ctx = runtime.new()
    input.button(ctx.input, "jump", { pressed = true })
    input.button(ctx.input, "jump", { released = true })
    input.look(ctx.input, 4, -2)
    input.look(ctx.input, 3, 1)
    runtime.update(ctx, h / 2)
    assert(ctx.input.buttons.jump.pressed)
    runtime.fixed_update(ctx, h)
    assert(ctx.player.intent.jump)
    near(ctx.player.intent.look_x, 7)
    near(ctx.player.intent.look_y, -1)
    runtime.fixed_update(ctx, h)
    assert(not ctx.player.intent.jump)
    near(ctx.player.intent.look_x, 0)
end)

test("held actions survive ticks; key repeat does not retrigger an edge", function()
    local ctx = runtime.new()
    input.button(ctx.input, "forward", { pressed = true })
    input.button(ctx.input, "right", { pressed = true })
    input.button(ctx.input, "reload", { pressed = true })
    runtime.fixed_update(ctx, h)
    near(ctx.player.intent.move_x, 1 / math.sqrt(2))
    near(ctx.player.intent.move_z, -1 / math.sqrt(2))
    assert(ctx.weapons.intent.reload)
    input.button(ctx.input, "reload", { repeated = true, value = 1 })
    runtime.fixed_update(ctx, h)
    assert(not ctx.weapons.intent.reload)
    near(ctx.player.intent.move_z, -1 / math.sqrt(2))
    input.reset(ctx.input)
    runtime.fixed_update(ctx, h)
    near(ctx.player.intent.move_z, 0)
end)

test("render updates never advance gameplay or apply damage", function()
    local ctx = runtime.new()
    assert(combat.request(ctx.combat, { target = "player", amount = 25 }))
    for _ = 1, 5 do runtime.update(ctx, 1 / 60) end
    assert(ctx.time.tick == 0 and ctx.player.actor.health == 100)
    runtime.fixed_update(ctx, h)
    assert(ctx.player.actor.health == 75)
    runtime.fixed_update(ctx, h)
    assert(ctx.player.actor.health == 75)
end)

test("damage has one owner, clamps health, and emits one death", function()
    local ctx = runtime.new()
    local dealt, taken, deaths = 0, 0, 0
    events.on(ctx.events, events.DAMAGE_DEALT, ctx, function(_, hit)
        dealt = dealt + hit.amount
    end)
    events.on(ctx.events, events.DAMAGE_TAKEN, ctx, function() taken = taken + 1 end)
    events.on(ctx.events, events.ACTOR_DEATH, ctx, function() deaths = deaths + 1 end)
    combat.request(ctx.combat, { target = "player", amount = 25 })
    combat.request(ctx.combat, { target = "player", amount = 200 })
    combat.request(ctx.combat, { target = "player", amount = 50 })
    runtime.fixed_update(ctx, h)
    assert(ctx.player.actor.health == 0 and not ctx.player.actor.alive)
    assert(dealt == 100 and taken == 2 and deaths == 1)
    assert(not combat.request(ctx.combat, { target = "player", amount = 1 }))
    assert(ctx.fx.damage_flash > 0 and ctx.fx.hitmarker == 0)
    input.button(ctx.input, "fire", { pressed = true })
    input.button(ctx.input, "jump", { pressed = true })
    runtime.fixed_update(ctx, h)
    assert(not ctx.weapons.intent.fire and not ctx.player.intent.jump)
    -- Notifications cannot re-apply damage.
    local other = combat.register(ctx.combat, "enemy", 100)
    events.emit(ctx.events, events.DAMAGE_DEALT, { target = "enemy", amount = 99, source = "player" })
    assert(other.health == 100 and ctx.fx.hitmarker > 0)
end)

test("invalid hits are rejected and pending hits cannot damage a replacement actor", function()
    local ctx = runtime.new()
    for _, amount in ipairs({ 0, -1, math.huge, 0 / 0, "10" }) do
        assert(not combat.request(ctx.combat, { target = "player", amount = amount }))
    end
    assert(not combat.request(ctx.combat, { target = "missing", amount = 10 }))
    combat.register(ctx.combat, "enemy", 100)
    combat.request(ctx.combat, { target = "enemy", amount = 10 })
    combat.remove(ctx.combat, "enemy")
    local replacement = combat.register(ctx.combat, "enemy", 100)
    runtime.fixed_update(ctx, h)
    assert(replacement.health == 100)
end)

test("damage requested from notifications is deferred to the next tick", function()
    local ctx = runtime.new()
    events.on(ctx.events, events.DAMAGE_TAKEN, ctx, function()
        combat.request(ctx.combat, { target = "player", amount = 10 })
    end)
    combat.request(ctx.combat, { target = "player", amount = 10 })
    runtime.fixed_update(ctx, h)
    assert(ctx.player.actor.health == 90)
    runtime.fixed_update(ctx, h)
    assert(ctx.player.actor.health == 80)
end)

test("event subscriptions support safe removal and registration during delivery", function()
    local bus, first, second, third = events.new(), {}, {}, {}
    local calls = {}
    events.on(bus, "test", first, function()
        calls[#calls + 1] = "first"
        events.off_owner(bus, first)
        events.off_owner(bus, second)
        events.on(bus, "test", third, function() calls[#calls + 1] = "third" end)
    end)
    events.on(bus, "test", second, function() calls[#calls + 1] = "second" end)
    events.emit(bus, "test", {})
    assert(table.concat(calls, ",") == "first")
    events.emit(bus, "test", {})
    assert(table.concat(calls, ",") == "first,third")
end)

test("interpolation remains separate from authoritative actor state", function()
    local ctx = runtime.new()
    runtime.fixed_update(ctx, h)
    ctx.player.position.x = 2
    runtime.update(ctx, h * 1.5)
    near(ctx.time.alpha, 0.5)
    near(ctx.presentation.position.x, 1)
    near(ctx.presentation.camera.y, 1.66)
    near(ctx.player.position.x, 2)
    runtime.update(ctx, h / 4)
    near(ctx.presentation.position.x, 1.5)
end)

test("120 Hz simulation stays aligned at 30, 60 and 144 rendered frames per second", function()
    for _, fps in ipairs({ 30, 60, 144 }) do
        local ctx, accumulated = runtime.new(), 0
        for _ = 1, fps * 3 do
            accumulated = accumulated + 1 / fps
            while accumulated + 1e-10 >= h do
                runtime.fixed_update(ctx, h)
                accumulated = accumulated - h
            end
            runtime.update(ctx, 1 / fps)
            assert(ctx.time.alpha >= 0 and ctx.time.alpha <= 1)
            near(ctx.time.alpha, math.max(0, accumulated / h))
        end
        assert(ctx.time.tick == 360)
        near(ctx.time.elapsed, 3)
    end
end)

test("sessions are independent and teardown removes state and subscriptions", function()
    local first, second = runtime.new(), runtime.new()
    combat.request(first.combat, { target = "player", amount = 25 })
    runtime.fixed_update(first, h)
    assert(second.player.actor.health == 100 and second.time.tick == 0)
    local fx = first.fx
    runtime.final(first)
    assert(first.player == nil and first.world == nil and first.audio == nil)
    assert(next(first.events.listeners) == nil and next(first.combat.actors) == nil)
    events.emit(first.events, events.DAMAGE_TAKEN, {})
    assert(fx.damage_flash == 0.2)
    assert(second.player.actor.health == 100)
end)

print(string.format("%d tests passed", count))
