-- Opt-in HTML5 fixture. Enable only with tests/squads_browser.project at build.
-- Uses real fixed updates, Bullet, rendering and sound; reports through stdout.
local ai=require "game.systems.ai"
local player=require "game.systems.player"
local combat=require "game.combat"
local M={}
local function report(kind,data) print("SQUAD_BROWSER "..kind.." "..json.encode(data)) end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function reset(self,x,z)
    ai.reset(self.ctx);self.ctx.ai.damage_scale=0;self.ctx.ai.enabled=true
    player.reset(self.ctx,{x=x,y=.01,z=z},0)
end
function M.new() return {phase="loading",frames={},restarts=0,rear=false} end
function M.update(test,self,dt,restart)
    if test.phase=="done" or not self.ctx.world.ready then return end
    local ctx=self.ctx
    if not test.started then
        test.started=ctx.time.elapsed;test.phase="cover";reset(self,4,-2.5)
        report("START",{actors=#ctx.ai.order})
    end
    assert(ctx.time.elapsed-test.started<100,"Browser squad fixture timed out in "..test.phase)
    local snapshot=ai.snapshot(ctx)
    for _,e in ipairs(snapshot.actors) do assert(not e.recovery_failed,"Browser actor recovery failed: "..e.id) end
    if test.phase=="cover" then
        for _,e in ipairs(snapshot.actors) do
            if e.cover and e.state=="fire" and e.shots>0 then
                report("COVER",{id=e.id,cover=e.cover,shots=e.shots})
                test.phase="flank";reset(self,0,5);break
            end
        end
    elseif test.phase=="flank" then
        test.frames[#test.frames+1]=dt*1000
        local completed=false
        for _,e in ipairs(snapshot.actors) do
            test.rear=test.rear or (e.flank~=nil and e.x< -23)
            completed=completed or e.flanks_completed>0
        end
        if completed then
            assert(test.rear and snapshot.fired>12,"Expected a rear flank during live combat")
            for _,e in ipairs(snapshot.actors) do assert(e.travel>.5,"Actor did not move: "..e.id) end
            table.sort(test.frames)
            local frames=test.frames
            report("FLANK",{actors=#snapshot.actors,fired=snapshot.fired,rear=test.rear,
                mean_tick_ms=snapshot.mean_tick_ms,peak_tick_ms=snapshot.peak_tick_ms,
                frames=#frames,frame_p95_ms=frames[math.ceil(#frames*.95)],frame_p99_ms=frames[math.ceil(#frames*.99)],
                objects=snapshot.render.objects,hitboxes=snapshot.render.active_hitboxes,buffers=snapshot.render.buffers})
            ctx.ai.enabled=false
            for _,id in ipairs(ctx.ai.order) do combat.request(ctx.combat,{target=id,amount=999,source="player"}) end
            test.phase="deaths"
        end
    elseif test.phase=="deaths" then
        local dead=true
        for _,e in ipairs(snapshot.actors) do dead=dead and e.death==1 end
        if dead then
            assert(snapshot.render.active_hitboxes==0 and count(ctx.ai.cover_claims)==0 and count(ctx.ai.flank_claims)==0)
            report("DEATHS",{actors=#snapshot.actors,hitboxes=0})
            test.phase="restart";test.next_reset=ctx.time.elapsed
        end
    elseif test.phase=="restart" and ctx.time.elapsed>=test.next_reset then
        if test.restarts>0 then
            assert(snapshot.render.objects==78 and snapshot.render.active_hitboxes==66 and snapshot.render.buffers==1)
            for _,e in ipairs(snapshot.actors) do assert(e.health==100) end
            assert(snapshot.live==0 and count(ctx.ai.cover_claims)==0 and count(ctx.ai.flank_claims)==0)
        end
        if test.restarts==8 then
            restart(self)
            assert(ctx.ai.damage_scale==1 and ctx.player.actor.health==100 and #ctx.ai.order==6)
            -- Freeze the successful result for visual review, without applying
            -- the diagnostic damage setting to the normal restart path.
            ctx.ai.enabled=false
            report("PASS",{restarts=8,actors=6,health=100,damage_scale=1})
            test.phase="done"
        else
            ai.reset(ctx);test.restarts=test.restarts+1;test.next_reset=ctx.time.elapsed+.2
        end
    end
end
return M
