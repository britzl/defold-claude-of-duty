local runtime = require "game.runtime"
local input = require "game.input"
local controls = require "game.ui.controls"
local audio = require "game.systems.audio"
local renderer = require "game.render.settings"
local hud = require "game.ui.hud"
local M = {}

function M.snapshot(self)
    return { paused=self.ctx.paused, focused=self.focused, sensitivity=self.ui.sensitivity,
        audio=self.ctx.audio.settings, renderer=self.renderer_settings }
end

function M.publish(self)
    msg.post("/hud#gui", "menu_state", M.snapshot(self))
end

function M.pause(self, paused)
    if not paused and not self.focused then return end
    controls.quarantine(self.ui)
    input.reset(self.ctx.input)
    runtime.set_paused(self.ctx, paused)
    window.set_mouse_lock(false)
    M.publish(self)
end

function M.configure(self, data)
    if data.kind == "audio" then audio.configure(self.ctx, { [data.key]=data.value })
    elseif data.kind == "renderer" then
        self.renderer_settings = renderer.configure(self.renderer_settings, { [data.key]=data.value })
        msg.post("@render:", "renderer_configure", self.renderer_settings)
    elseif data.kind == "input" and data.key == "sensitivity" then controls.configure(self.ui, data.value)
    else error("Unknown setting") end
    M.publish(self)
    return M.snapshot(self)
end

function M.init(self, restart)
    self.ui, self.focused = controls.new(), true
    if automation_bridge then
        automation_bridge.command("ui.snapshot", function()
            local state = M.snapshot(self)
            state.hud = hud.snapshot(self.ctx)
            state.map_rectangles = #self.ctx.world.minimap
            return state
        end)
        automation_bridge.command("ui.pause", function(data)
            assert(type(data.paused)=="boolean", "paused must be boolean")
            M.pause(self, data.paused)
            return M.snapshot(self)
        end)
        automation_bridge.command("ui.focus", function(data)
            assert(type(data.focused)=="boolean", "focused must be boolean")
            M.focus(self, data.focused)
            return M.snapshot(self)
        end)
        automation_bridge.command("ui.configure", function(data) return M.configure(self, data) end)
        for name, description in pairs({
            ["ui.snapshot"]="Read pause/focus, live settings, compass, damage feedback, killfeed and minimap count.",
            ["ui.pause"]="Pause/resume simulation with {paused}; releases the cursor and clears held gameplay inputs.",
            ["ui.focus"]="Simulate a window focus callback with {focused} for automation; returning focus still requires explicit resume.",
            ["ui.configure"]="Set one live {kind=audio|renderer|input,key,value}; input supports sensitivity 0.25..3.",
        }) do
            automation_bridge.describe("command", name, {description=description,
                input_schema={type="object"}, output_schema={type="object"}})
        end
    end
    self.ui_restart = restart
    M.publish(self)
end

function M.action(self, data)
    if not self.ctx.paused or not self.focused then return end
    if data.action == "resume" then M.pause(self, false)
    elseif data.action == "restart" and self.ctx.world.ready then
        self.ui_restart(self)
        M.pause(self, false)
    elseif data.action == "setting" then M.configure(self, data) end
end

function M.focus(self, focused)
    self.focused = focused
    if not focused then
        M.pause(self, true)
        -- Platforms may omit key-up events outside the window. A new press on
        -- return is a fresh gesture, while repeats still cannot become presses.
        self.ui.held, self.ui.blocked = {}, {}
    else M.publish(self) end
end

function M.menu_input(self, action_id, action)
    if not self.ctx.paused then return false end
    if self.focused then
        msg.post("/hud#gui", "menu_input", { id=action_id or hash("pointer"),
            x=action.x or 0, y=action.y or 0, screen_x=action.screen_x or 0, screen_y=action.screen_y or 0,
            dx=action.dx or 0, dy=action.dy or 0, pressed=action.pressed or false,
            released=action.released or false, repeated=action.repeated or false })
    end
    return true
end
return M
