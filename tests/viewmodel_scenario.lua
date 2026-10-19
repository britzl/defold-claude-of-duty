-- Same production viewmodel, input and ammunition fixture on Metal and WebGL.
local runtime=require 'game.runtime'
local player=require 'game.systems.player'
local weapons=require 'game.systems.weapons'
local input=require 'game.input'
local defs=require 'game.weapons.defs'
local view=require 'game.weapons.viewmodel'
local T=require 'game.ai.transform'
local M={}
local function report(kind,data)
    local line='VIEWMODEL '..kind..' '..json.encode(data)
    if html5 then html5.run('console.log('..json.encode(line)..')') else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,trace)
        html5.run('console.error('..json.encode('ERROR: '..tostring(message)..'\n'..tostring(trace))..')')
    end) end
    report('START',sys.get_engine_info());return {checks=0,shots=0}
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    if not test.hold then
        local changed=ctx.paused or not self.focused
        runtime.set_paused(ctx,false);self.focused=true
        if changed then require("game.ui.controller").publish(self) end
        -- Native focus callbacks can clear held input while automation captures
        -- or a second backend launches. Restore only fixture-owned holds.
        for key,on in pairs(test.buttons or {}) do
            if on and not ctx.input.buttons[key].held then input.button(ctx.input,key,{pressed=true}) end
        end
    end
    ctx.ai.enabled=false
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function wait(fn)
            local deadline=ctx.time.frame_elapsed+20
            while not fn() do assert(ctx.time.frame_elapsed<deadline,'Viewmodel fixture timed out');coroutine.yield() end
        end
        local function ticks(n) local tick=ctx.time.tick+n;wait(function() return ctx.time.tick>=tick end) end
        test.buttons={}
        local function button(key,on)
            test.buttons[key]=on;input.button(ctx.input,key,on and {pressed=true} or {released=true})
        end
        local function tap(key) button(key,true);ticks(1);button(key,false) end
        local function idle() wait(function() return ctx.weapons.clip==nil end) end
        local function check(name)
            test.checks=test.checks+1;report('CHECK',{name=name,state=weapons.snapshot(ctx)})
        end
        local function capture(name)
            test.hold=true;runtime.set_paused(ctx,true);msg.post('/hud#gui','disable');frames(6)
            test.shots=test.shots+1;report('SHOT',{id=name});frames(45)
            runtime.set_paused(ctx,false);test.hold=false;msg.post('/hud#gui','enable')
        end
        local function fresh(id)
            test.buttons={}
            restart(self);ctx.ai.enabled=false;self.focused=true
            player.reset(ctx,{x=0,y=.01,z=24},0);ticks(100)
            if id~='rifle' then weapons.select(ctx,id);idle() end
            input.reset(ctx.input);ticks(4)
        end
        for _,id in ipairs({'rifle','smg','pistol'}) do
            fresh(id)
            local d=defs[id];local w=ctx.weapons;local inventory=w.inventory[id]
            assert(#self.weapon_visuals.objects==50) -- 24 parts, two arms, 24 effects
            for side,part in pairs(self.weapon_visuals.arms) do
                assert(part.visible and #part.palette==17)
                assert(self.weapon_visuals.sample.joints[side].stretch<1.2)
            end
            check(id..'_resources_and_grips');capture(id..'_hip')
            button('aim',true);ticks(90)
            local p=view.pose(ctx,self.weapon_visuals.models[id])
            local matrix=T.rotation(p.rotation[1],p.rotation[2],p.rotation[3])
            matrix[4],matrix[8],matrix[12]=p.position[1],p.position[2],p.position[3]
            local sight=self.weapon_visuals.models[id].sight
            local optical=T.point(matrix,{x=sight[1],y=sight[2],z=sight[3]})
            assert(math.abs(optical.x)<1e-7 and math.abs(optical.y)<1e-7,json.encode({optical=optical,ads=w.ads}))
            assert(p.parts.reticle.visible);check(id..'_ads_alignment');capture(id..'_ads')
            button('aim',false);ticks(60)
            local fired=w.sim.fired;tap('fire')
            assert(w.sim.fired==fired+1);capture(id..'_fire');ticks(30)
            assert(inventory.mag==d.magSize-1)
            local total=inventory.mag+1+inventory.reserve
            tap('reload');wait(function() return w.clip_time/w.clip_duration>=.27 end)
            assert(inventory.mag==d.magSize-1)
            local sample=self.weapon_visuals.sample
            assert(sample.parts.magazine.position[2]<-.02)
            capture(id..'_reload')
            local frozen_time=w.clip_time;test.hold=true;runtime.set_paused(ctx,true)
            local palette=json.encode(view.pose(ctx,self.weapon_visuals.models[id]).arms)
            frames(20);assert(w.clip_time==frozen_time and json.encode(view.pose(ctx,self.weapon_visuals.models[id]).arms)==palette)
            test.hold=false;runtime.set_paused(ctx,false)
            idle();assert(inventory.mag==d.magSize and inventory.chambered)
            assert(inventory.mag+1+inventory.reserve==total);check(id..'_tactical_transfer_and_pause')
            inventory.mag=0;inventory.chambered=false;inventory.reserve=d.magSize
            tap('reload');wait(function() return w.clip_time/w.clip_duration>=.78 end)
            assert(inventory.mag==d.magSize and not inventory.chambered and inventory.reserve==0)
            wait(function() return w.clip_time/w.clip_duration>=.88 end);capture(id..'_charge')
            idle();assert(inventory.mag==d.magSize-1 and inventory.chambered)
            check(id..'_empty_transfer_and_chamber')
            tap('inspect');wait(function() return w.clip_time/w.clip_duration>=.52 end)
            capture(id..'_inspect');fired=w.sim.fired;tap('fire')
            assert(w.sim.fired==fired+1 and w.clip==nil);check(id..'_inspect_interruption')
            ticks(40)
            -- Interrupt an empty reload after transfer, with no reserve left.
            inventory.mag=0;inventory.chambered=false;inventory.reserve=d.magSize
            tap('reload');wait(function() return w.clip_time/w.clip_duration>=.78 end)
            assert(inventory.mag==d.magSize and not inventory.chambered)
            weapons.select(ctx,id=='rifle' and 'smg' or 'rifle');idle()
            weapons.select(ctx,id);idle();tap('reload');idle()
            assert(inventory.mag==d.magSize-1 and inventory.chambered and inventory.reserve==0)
            check(id..'_interrupted_empty_reload')
        end
        fresh('rifle');player.reset(ctx,{x=-13,y=.01,z=19},0);ticks(100)
        capture('rifle_indoor')
        local vertices=self.weapon_visuals.vertices
        restart(self);ticks(100);assert(self.weapon_visuals.vertices==vertices)
        assert(ctx.weapons.equipped=='rifle' and ctx.weapons.inventory.rifle.mag==30)
        check('restart_reuses_resources')
        test.done=true;report('PASS',{checks=test.checks,shots=test.shots,vertices=vertices,
            objects=#self.weapon_visuals.objects,buffers=#self.weapon_visuals.buffers,arm_matrices=34,
            platform=sys.get_sys_info().system_name})
    end) end
    local ok,err=coroutine.resume(test.job)
    if not ok then test.done=true;error(err) end
end
return M
