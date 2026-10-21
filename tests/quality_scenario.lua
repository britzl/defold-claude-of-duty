-- Shared production-path lifecycle fixture for native and release WebGL.
local ui=require 'game.ui.controller'
local Q=require 'game.render.quality'
local runtime=require 'game.runtime'
local combat=require 'game.combat'
local grenades=require 'game.systems.grenades'
local input=require 'game.input'
local FX=require 'game.render.combat_fx_defold'
local M={}
local function report(kind,data)
    local line='QUALITY '..kind..' '..json.encode(data)
    if html5 then html5.run('console.log('..json.encode(line)..')') else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run('console.error('..json.encode('ERROR: '..tostring(message)..'\n'..tostring(stack))..')') end) end
    local t={checks=0}
    if automation_bridge then automation_bridge.command('quality.validation_continue',function(data) t.ack=data.id;return {ok=true} end) end
    report('START',sys.get_engine_info());return t
end
function M.update(t,self,dt,restart)
    if t.done then
        if html5 then html5.run('window.__QUALITY_STATE__='..json.encode({mode=self.quality.mode,active=self.quality.active,
            paused=self.ctx.paused,render_scale=self.renderer_stats.render_scale,shadow_size=self.renderer_stats.shadow_size})) end
        return
    end
    local ctx=self.ctx
    self.focused=true
    if not ctx.world.ready or not self.renderer_stats.ready then
        t.loading_frames=(t.loading_frames or 0)+1
        if t.loading_frames%120==0 then report('WAIT',{phase=ctx.world.phase,frame=ctx.time.frame,tick=ctx.time.tick,renderer=self.renderer_stats.ready,
            shapes=#ctx.world.shapes,cursor=ctx.world.cursor,audio=ctx.audio.loaded,paused=ctx.paused}) end
        return
    end
    if not t.job then t.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function check(name,data) t.checks=t.checks+1;report('CHECK',{name=name,detail=data}) end
        local function select(mode)
            ui.configure(self,{kind='quality',key='mode',value=mode});frames(8)
        end
        local function shot(id)
            local paused=ctx.paused;runtime.set_paused(ctx,true);frames(5)
            t.ack=nil;report('SHOT',{id=id})
            local at=socket.gettime()
            repeat
                frames(1)
                if html5 and html5.run('window.__QUALITY_SHOT_ACK__ || ""')==id then t.ack=id end
                assert(socket.gettime()-at<45,'screenshot timeout')
            until t.ack==id
            runtime.set_paused(ctx,paused)
        end
        ui.pause(self,false);ctx.ai.damage_scale=0
        local previous_bytes=0
        for _,name in ipairs(Q.names) do
            select(name)
            local r,p=self.renderer_stats,Q.preset(name)
            assert(r.render_scale==p.render_scale and r.shadow_size==p.shadow_resolution,json.encode(r))
            assert(r.width==math.floor(r.output_width*p.render_scale+.5) and r.height==math.floor(r.output_height*p.render_scale+.5))
            assert(r.material_lod==p.material_lod and r.target_bytes>previous_bytes)
            previous_bytes=r.target_bytes
            input.button(ctx.input,'fire',{pressed=true});frames(20);input.button(ctx.input,'fire',{released=true})
            check('preset_'..name,{width=r.width,height=r.height,output_width=r.output_width,output_height=r.output_height,shadow_size=r.shadow_size,material_lod=r.material_lod,targets=r.target_count,target_bytes=r.target_bytes,fx=FX.snapshot(self.combat_visuals),quality=Q.snapshot(self.quality)})
            shot(name)
        end
        local before=ctx.time.tick
        select('low');frames(8);assert(ctx.time.tick>before and ctx.weapons.sim.fired>0)
        assert(grenades.launch(ctx,'enemy_2',{x=1,y=.3,z=3},{x=0,y=0,z=0}))
        combat.request(ctx.combat,{target='enemy_1',source='player',amount=1000})
        frames(6);select('ultra');frames(8)
        assert(not ctx.ai.actors.enemy_1.actor.alive)
        check('quality_changes_with_live_grenade_and_ragdoll')
        select('high');local count,bytes=self.renderer_stats.target_count,self.renderer_stats.target_bytes
        local baked=self.renderer_stats.bake_draws
        for i=1,10 do
            select(i%2==0 and 'ultra' or 'low');restart(self);ctx.ai.damage_scale=0;select('high')
            assert(self.renderer_stats.target_count==count and self.renderer_stats.target_bytes==bytes)
            assert(self.renderer_stats.bake_draws==baked,'quality change rebaked materials')
            assert(self.quality.mode=='high' and self.combat_visuals.state.density==1)
        end
        check('ten_quality_cycles_and_restarts_keep_resource_counts_and_material_bake_stable',{targets=count,bytes=bytes,bake_draws=baked})
        select('low');shot('resize_low');frames(8)
        assert(self.renderer_stats.render_scale==.6)
        check('resizing_with_scaled_scene_preserves_output_and_quality')
        ui.pause(self,true);select('medium');frames(5);shot('menu')
        ui.action(self,{action='quality_defaults'});frames(6)
        assert(self.quality.mode=='auto' and self.quality.active=='high')
        local changes=self.quality.changes;frames(60);assert(self.quality.changes==changes and ctx.paused)
        check('menu_defaults_restore_auto_and_pause_excludes_samples')
        ui.configure(self,{kind='renderer',key='shadows',value=false});frames(4)
        assert(self.quality.mode=='custom' and not self.renderer_settings.shadows)
        ui.action(self,{action='quality_defaults'});frames(4);assert(self.renderer_settings.shadows)
        check('advanced_override_selects_custom_and_defaults_restore_preset')
        ui.pause(self,false);select('medium');ui.focus(self,false);frames(6)
        assert(ctx.paused and self.quality.mode=='medium')
        ui.focus(self,true);ui.pause(self,false);restart(self);ctx.ai.damage_scale=0;frames(8)
        assert(self.quality.mode=='medium' and self.combat_visuals.state.density==.65)
        check('focus_and_restart_preserve_manual_selection_and_effect_limits')
        local capture=require 'game.render.capture_controller'
        capture.select(self,{name='street'});frames(10)
        assert(self.renderer_stats.render_scale==1 and self.quality.mode=='medium')
        capture.finish(self);frames(10)
        assert(self.renderer_stats.render_scale==.8 and self.quality.mode=='medium')
        check('capture_uses_fixed_quality_and_restores_manual_settings')
        select('auto');t.done=true;report('PASS',{checks=t.checks,quality=Q.snapshot(self.quality)})
    end) end
    local ok,err=coroutine.resume(t.job);if not ok then t.done=true;error(err) end
end
return M
