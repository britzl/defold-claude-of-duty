-- Shared visual replay. Recording overhead is deliberately excluded from the
-- separate sustained benchmark. Phase times use simulation time, not wall time.
local runtime=require 'game.runtime'
local ui=require 'game.ui.controller'
local player=require 'game.systems.player'
local ai=require 'game.systems.ai'
local combat=require 'game.combat'
local grenades=require 'game.systems.grenades'
local weapons=require 'game.weapons.driver'
local movement=require 'game.player.driver'
local M={}
local function report(kind,data)
    local line='COMBAT_REVIEW '..kind..' '..json.encode(data)
    if html5 then html5.run('console.log('..json.encode(line)..')') else print(line) end
end
function M.new()
    local t={phases={}}
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run('console.error('..json.encode('ERROR: '..message..'\n'..stack)..')') end) end
    if automation_bridge then automation_bridge.command('combat_review.start',function() t.start=true;return {started=true} end) end
    return t
end
function M.update(t,self,dt,restart)
    if t.done then return end
    local ctx=self.ctx
    self.focused=true
    runtime.set_paused(ctx,t.ready and not t.start or false)
    if not ctx.world.ready or not self.renderer_stats.ready or not ctx.services.capsule then return end
    if not t.ready then
        restart(self);ctx.ai.enabled=false;ctx.ai.damage_scale=0
        ui.focus(self,true);ui.pause(self,false);ui.quality_mode(self,'high')
        t.ready=true;runtime.set_paused(ctx,true)
        report('READY',{engine=sys.get_engine_info(),width=self.renderer_stats.output_width,height=self.renderer_stats.output_height})
    end
    if html5 and not t.start then t.start=html5.run('window.__COMBAT_REVIEW_START__ ? "1" : "0"')=='1' end
    if not t.start then return end
    runtime.set_paused(ctx,false);ctx.ai.damage_scale=0;ctx.player.actor.health=100
    if not t.job then t.job=coroutine.create(function()
        ui.pause(self,false)
        -- Hide the UI to keep the visual review unobstructed.
        -- Background native windows can receive focus-loss menu messages.
        msg.post('/hud#gui','disable')
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function seconds(n) local until_time=ctx.time.elapsed+n;repeat frames(1) until ctx.time.elapsed>=until_time end
        local function phase(name)
            local row={name=name,tick=ctx.time.tick,simulation_seconds=ctx.time.elapsed,wall=socket.gettime()}
            t.phases[#t.phases+1]=row;report('PHASE',row)
        end
        local function reset(x,z,yaw)
            self.weapon_drive=nil;ctx.player.drive=nil;restart(self)
            ctx.ai.enabled=false;ctx.ai.damage_scale=0
            player.reset(ctx,{x=x,y=.01,z=z},yaw or 0)
            frames(3)
        end
        reset(0,10)
        phase('walk_sprint_turn')
        ctx.player.drive=movement.new({{ticks=240,move_z=-1},{ticks=240,move_z=-1,sprint=true},
            {ticks=240,move_x=1,look_x=-.7},{ticks=240,move_x=-1,look_x=.7},{ticks=120}})
        repeat frames(1) until ctx.player.drive.complete
        for _,name in ipairs({'rifle','smg','pistol'}) do
            reset(0,10)
            phase(name..'_ads_fire_reload_inspect')
            self.weapon_drive=weapons.new({{ticks=120,['weapon_'..name]=true},{ticks=120,aim=true},
                {ticks=180,aim=true,fire=true},{ticks=1},{ticks=360,reload=true},
                {ticks=120},{ticks=360,inspect=true}})
            repeat frames(1) until self.weapon_drive.complete
            assert(ctx.weapons.sim.fired>0,'Replay weapon did not fire: '..name)
        end
        reset(0,10,math.pi/2)
        phase('wall_impacts')
        self.weapon_drive=weapons.new({{ticks=120,aim=true},{ticks=240,aim=true,fire=true},{ticks=120}})
        repeat frames(1) until self.weapon_drive.complete
        assert(self.combat_visuals.state.impacts>0,'Replay must hit the world')
        reset(0,10)
        local e=ai.reset(ctx,{x=0,y=.01,z=2},math.pi)
        ctx.ai.enabled=true
        phase('soldier_combat')
        seconds(4)
        phase('ragdoll')
        assert(combat.request(ctx.combat,{target=e.id,source='player',amount=1000,
            point={x=e.position.x,y=e.position.y+1.3,z=e.position.z},direction={x=0,y=0,z=-1}}))
        seconds(2)
        phase('explosion_smoke')
        grenades.detonate(ctx,{id=990,source=e.id,position={x=1,y=.15,z=6},damage_scale=0})
        seconds(5)
        phase('complete')
        t.done=true;runtime.set_paused(ctx,true)
        report('PASS',{phases=t.phases,renderer={width=self.renderer_stats.output_width,height=self.renderer_stats.output_height,targets=self.renderer_stats.target_count},
            effects=require('game.render.combat_fx_defold').snapshot(self.combat_visuals),
            physics=require('game.physics.defold').snapshot(ctx.services.dynamics)})
    end) end
    local ok,err=coroutine.resume(t.job);assert(ok,err)
end
return M
