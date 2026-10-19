-- Shared native/HTML5 integration fixture. Only opt-in validation invokes it.
-- Stimuli are real, finite projectiles through the normal Bullet adapter.
local ai=require "game.systems.ai"
local player=require "game.systems.player"
local ballistics=require "game.weapons.ballistics"
local suppression=require "game.ai.suppression"
local M={}
local round={id="rifle",damage=10,muzzleVelocity=600,penetration=.1,dropoff=1,maxRange=4,dragK=0}
function M.new() return {phase="loading",report={}} end
local function record(test,kind,data)
    test.report[kind]=data
    print("SUPPRESSION_SCENARIO "..kind.." "..json.encode(data))
end
local function head(ctx,id)
    for _,shape in pairs(ctx.services.soldiers.by_id) do
        if shape.actor==id and shape.headshot and not shape.disabled then return shape end
    end
    error("Missing native head volume")
end
local function burst(ctx,e,impact)
    local eye=suppression.eye(e)
    for _=1,impact and 10 or 4 do
        local origin=impact and {x=3,y=.8,z=e.position.z+.35}
            or {x=eye.x-.45,y=eye.y+.1,z=eye.z-2}
        ballistics.spawn(ctx.weapons.sim,round,origin,impact and {x=-1,y=0,z=0} or {x=0,y=0,z=1},"player",true)
    end
end
function M.update(test,ctx)
    if test.phase=="done" or ctx.paused or not ctx.world.ready then return end
    if not test.started then
        test.started=ctx.time.elapsed;test.phase="cover"
        ai.reset(ctx);ctx.ai.enabled=true;ctx.ai.damage_scale=0
        player.reset(ctx,{x=4,y=.01,z=-2.5},1.32)
        ctx.player.motion.pitch=-.12
    end
    assert(ctx.time.elapsed-test.started<35,"Suppression fixture timed out: "..test.phase)
    local e=test.id and ctx.ai.actors[test.id]
    if test.phase=="cover" then
        for _,id in ipairs(ctx.ai.order) do
            local candidate=ctx.ai.actors[id]
            if candidate.cover and candidate.shots>0 and candidate.crouch==0 and candidate.state=="fire" then
                test.id=id;e=candidate;test.cover=e.cover.id;test.shots=e.shots
                test.standing=head(ctx,id).y;test.at=ctx.time.elapsed
                record(test,"PEEK",{id=id,head_y=test.standing,shots=e.shots,cover=test.cover})
                test.phase="ready_passes";break
            end
        end
    elseif test.phase=="ready_passes" and ctx.time.elapsed-test.at>.4 then
        -- Give the native screenshot client a standing review frame before
        -- the same physics-driven burst used by the browser fixture.
        test.shots=e.shots;test.at=ctx.time.elapsed
        burst(ctx,e,false);test.phase="passes"
    elseif test.phase=="passes" or test.phase=="impacts" then
        assert(e.shots==test.shots,"Suppressed actor fired before recovering")
        if ctx.time.elapsed-test.at>.4 then
            assert(e.suppressed and e.crouch==1 and e.motion.stance=="crouch","Expected a physical duck")
            assert(e.cover and e.cover.id==test.cover and ctx.ai.cover_claims[test.cover]==e.id)
            local volume=head(ctx,e.id)
            assert(volume.y<test.standing-.7,"Native hit volume did not follow the duck")
            local eye=suppression.eye(e)
            assert(math.abs(volume.y-eye.y)<.02,"Skinning and native hit volume disagree")
            local query=ctx.services.soldiers.api.query(ctx.services.soldiers,e)
            assert(not query:visible(eye,{x=4,y=1.28,z=-2.5}),"Crouched head is exposed through cover")
            assert(e.actor.health==100,"Near misses/cover impacts unexpectedly hit the actor")
            record(test,test.phase=="passes" and "PASSES" or "IMPACTS",{head_y=volume.y,standing_head_y=test.standing,
                score=e.suppression,events=e.suppression_events,shots=e.shots,cover=e.cover.id,crouch=e.crouch})
            test.phase=test.phase=="passes" and "recover_passes" or "recover_impacts"
        end
    elseif test.phase=="recover_passes" or test.phase=="recover_impacts" then
        if e.suppressed then assert(e.shots==test.shots,"Actor fired under suppression") end
        if not e.suppressed and e.crouch==0 and e.shots>test.shots then
            if test.phase=="recover_passes" then
                test.shots=e.shots;test.at=ctx.time.elapsed
                burst(ctx,e,true);test.phase="impacts"
            else
                record(test,"RECOVERED",{shots=e.shots,peeks=e.peeks,score=e.suppression})
                local render=ai.snapshot(ctx).render
                assert(render.objects==78 and render.active_hitboxes==66 and render.buffers==1)
                record(test,"PASS",{actors=6,objects=render.objects,hitboxes=render.active_hitboxes,buffers=render.buffers})
                test.phase="done";ctx.ai.enabled=false
            end
        end
    end
end
return M
