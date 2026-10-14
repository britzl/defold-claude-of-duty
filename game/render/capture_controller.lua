local shots=require "game.render.capture"
local laboratory=require "game.render.laboratory"
local input=require "game.input"
local audio=require "game.systems.audio"
local settings=require "game.render.settings"
local M={}
function M.snapshot(self)
    if not self.capture then return {active=false} end
    local c=self.capture
    return {active=true,temporal_live=c.temporal_live or false,playing=c.playing or false,shot=c.shot.id,frame=c.frame,camera=shots.camera(c.shot,c.frame),
        weapon=c.shot.weapon or "hidden",laboratory=c.shot.laboratory or false,
        simulation_tick=self.ctx.time.tick,lab_meshes=self.capture_lab and #self.capture_lab.objects or 0,
        lab_vertices=self.capture_lab and self.capture_lab.vertices or 0,
        lighting={mode="fixed_presets",rig=require("game.render.daylight").snapshot(self.renderer_settings.lighting),clouds=self.renderer_settings.clouds,exposure=self.renderer_settings.exposure},catalog_version=shots.version}
end
function M.finish(self)
    if not self.capture then return M.snapshot(self) end
    local saved=self.capture.saved
    self.capture=nil
    require("game.render.combat_fx_defold").fixture(self.combat_visuals,false)
    self.renderer_settings=saved.settings
    msg.post("@render:","renderer_configure",saved.settings)
    msg.post("@render:","capture_configure",{active=false,laboratory=false})
    self.active_lights=nil
    input.reset(self.ctx.input)
    audio.suspend(self.ctx,self.ctx.paused)
    if self.capture_lab then laboratory.final(self.capture_lab);self.capture_lab=nil end
    return M.snapshot(self)
end
function M.select(self,data)
    assert(self.ctx.world.ready and self.renderer_stats.ready,"Wait for world and renderer loading")
    local shot=shots.select(data.name)
    local frame=data.frame or 0
    shots.camera(shot,frame)
    if shot.laboratory and not self.capture_lab then self.capture_lab=laboratory.create() end
    local saved=self.capture and self.capture.saved or {settings=self.renderer_settings}
    require("game.render.combat_fx_defold").fixture(self.combat_visuals,shot.combat_fixture)
    self.capture={shot=shot,frame=frame,saved=saved,actors=data.actors==true,temporal_live=data.temporal_live==true}
    self.renderer_settings=settings.configure(settings.defaults(),{lighting=shot.lighting or "daylight",clouds=shot.clouds~=false,auto_exposure=false})
    self.active_lights=nil
    input.reset(self.ctx.input)
    window.set_mouse_lock(false)
    audio.suspend(self.ctx,true)
    msg.post("@render:","renderer_configure",self.renderer_settings)
    msg.post("@render:","capture_configure",{active=true,laboratory=shot.laboratory or false,actors=self.capture.actors,temporal_live=self.capture.temporal_live})
    return M.snapshot(self)
end
function M.install(self)
    automation_bridge.command("capture.catalog",shots.catalog)
    automation_bridge.command("capture.snapshot",function() return M.snapshot(self) end)
    automation_bridge.command("capture.shot",function(data) return M.select(self,data) end)
    automation_bridge.command("capture.frame",function(data)
        assert(self.capture,"Select a capture shot first")
        assert(type(data.frame)=="number","frame is required")
        shots.camera(self.capture.shot,data.frame)
        self.capture.playing=false
        self.capture.frame=data.frame
        if not self.capture.temporal_live then msg.post("@render:","renderer_reset_history",{reason="capture_frame"}) end
        return M.snapshot(self)
    end)
    automation_bridge.command("capture.play",function(data)
        assert(self.capture and self.capture.temporal_live,"Select a shot with temporal_live=true first")
        self.capture.playing=data.playing~=false
        self.capture.direction=1
        return M.snapshot(self)
    end)
    automation_bridge.command("capture.end",function() return M.finish(self) end)
    for name,description in pairs({
        ["capture.catalog"]="Versioned visual baseline shots, unsupported states and output contract.",
        ["capture.shot"]="Freeze gameplay; select HUD-free name from capture.catalog, optional integer frame 0..120. Settings restored by capture.end.",
        ["capture.frame"]="Address a deterministic 30 FPS camera sweep with integer frame 0..120; never advances gameplay.",
        ["capture.snapshot"]="Read active capture camera, frame, lighting and fixture resource counts.",
        ["capture.play"]="Run or stop a continuous frame-counted camera sweep; requires temporal_live=true when selecting the shot.",
        ["capture.end"]="Leave capture mode, free its fixture and restore renderer settings; normal pause/focus rules apply."}) do
        automation_bridge.describe("command",name,{description=description,input_schema={type="object"},output_schema={type="object"}})
    end
end
return M
