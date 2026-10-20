local runtime = require "game.runtime"
local input = require "game.input"
local controls = require "game.ui.controls"
local audio = require "game.systems.audio"
local renderer = require "game.render.settings"
local hud = require "game.ui.hud"
local touch = require "game.touch"
local M = {}

function M.snapshot(self)
    return { paused=self.ctx.paused, focused=self.focused, sensitivity=self.ui.sensitivity,
        audio=self.ctx.audio.settings, renderer=self.renderer_settings,
        touch_controls=self.touch and self.touch.enabled or false }
end

function M.publish(self)
    msg.post("/hud#gui", "menu_state", M.snapshot(self))
end

function M.pause(self, paused)
    if not paused and not self.focused then return end
    controls.quarantine(self.ui)
    if self.touch then touch.reset(self.touch,self.ctx.input) end
    input.reset(self.ctx.input)
    runtime.set_paused(self.ctx, paused)
    window.set_mouse_lock(false)
    if self.focused then audio.ui(self.ctx) end
    M.publish(self)
end

function M.configure(self, data)
    if data.kind == "audio" then audio.configure(self.ctx, { [data.key]=data.value })
    elseif data.kind == "renderer" then
        self.renderer_settings = renderer.configure(self.renderer_settings, { [data.key]=data.value })
        msg.post("@render:", "renderer_configure", self.renderer_settings)
        if data.key=="hour" or data.key=="lighting" then
            msg.post("@render:", "renderer_atmosphere_seek", {hour=self.renderer_settings.hour})
        end
    elseif data.kind == "input" and data.key == "sensitivity" then controls.configure(self.ui, data.value)
    else error("Unknown setting") end
    audio.ui(self.ctx)
    M.publish(self)
    return M.snapshot(self)
end

function M.init(self, restart)
    self.ui, self.focused = controls.new(), true
    local system=sys.get_sys_info().system_name
    self.touch_override=sys.get_config_int("touch_controls.enabled",-1)
    local browser_touch=system=="HTML5" and html5 and html5.run("navigator.maxTouchPoints > 0 ? '1' : '0'")=="1"
    self.touch=touch.new(touch.default_enabled(system,browser_touch,self.touch_override))
    M.sync_touch(self)
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

function M.sync_touch(self)
    if not self.touch then return end
    local width,height=window.get_size()
    local safe=window.get_safe_area and window.get_safe_area() or {}
    local key=table.concat({width,height,safe.inset_left or 0,safe.inset_right or 0,
        safe.inset_bottom or 0,safe.inset_top or 0},":")
    local active=self.touch.enabled and self.focused and not self.ctx.paused
        and self.ctx.world.ready and self.ctx.player.actor.alive and self.ctx.player.enabled
        and not self.capture and not self.view or false
    if key~=self.touch_layout_key or active~=self.touch.active then
        touch.reset(self.touch,self.ctx.input)
        self.touch_layout_key=key
        self.touch_layout=touch.layout(width,height,safe)
        self.touch.active=active
    end
end

function M.touch_input(self, action)
    if self.touch_override==0 then return true end
    if not self.touch.enabled then
        self.touch.enabled=true
        window.set_mouse_lock(false)
        M.publish(self)
    end
    M.sync_touch(self)
    if not self.focused then return true end
    if self.ctx.paused then
        -- Only one fresh menu finger owns clicks/sliders. Existing gameplay
        -- fingers and extra touches cannot activate or drag menu controls.
        for _,point in ipairs(action.touch or {}) do
            if point.pressed and not self.touch.menu_id then self.touch.menu_id=point.id end
            if self.touch.menu_id==point.id then
                M.menu_input(self,hash("pointer"),point)
                if point.pressed or point.released then M.menu_input(self,hash("fire"),point) end
                if point.released then self.touch.menu_id=nil end
            end
        end
    elseif touch.handle(self.touch,self.ctx.input,action.touch or {},self.touch_layout,
        self.touch.active,self.ui.sensitivity)=="pause" then M.pause(self,true) end
    return true
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
