-- Opt-in full-map browser fixture; real Bullet queries, actors and renderer.
local world_adapter=require "game.world.defold"
local nav=require "game.ai.navigation"
local runtime=require "game.runtime"
local M={}
local views={"north_plaza","east_alley","ruin_yard","cross_street","gate","e1_shop","e1_top","e3_room"}
local targets={"street_north","street_south","street_gate","west_near/rear_north","west_far/rear_south",
    "east_loop/ruin_yard","east_far/rear_south","W2/bedroom","E2/bedroom","E2/floor2/bedroom",
    "E1/bedroom","E1/floor2/bedroom","E3/room","W2/storage","W2/living","E1/storage","E3/storage","E3/ruin"}
local function report(kind,data) print("MARKET_BROWSER "..kind.." "..json.encode(data)) end
function M.new() return {elapsed=0,view=0,routes=0} end
function M.update(test,self,dt)
    if test.done then return end
    local ctx=self.ctx
    runtime.set_paused(ctx,false)
    ctx.ai.enabled=false
    if not ctx.world.ready or not ctx.ai.actors.enemy_1 then return end
    -- Production fixed_update creates queries after Bullet installs the new
    -- objects. Calling query() here just after runtime.update advances the
    -- frame counter too early on a browser frame with no physics step yet.
    local instances=ctx.services.soldiers.instances
    for _,id in ipairs(ctx.ai.order) do if not instances[id].query then return end end
    local query=instances.enemy_1.query
    test.elapsed=test.elapsed+dt
    if not test.job then
        test.job=coroutine.create(function()
            local valid=world_adapter.validate(ctx.world.adapter,ctx.world,query)
            assert(valid.max_error<1e-5)
            for _,n in ipairs(valid.nodes) do assert(n.supported,"Unsupported node: "..n.id) end
            for _,e in ipairs(valid.edges) do
                assert(e.clear and e.forward and e.reverse,"Blocked edge: "..e.from.." -> "..e.to)
            end
            report("PHYSICS",{nodes=#valid.nodes,edges=#valid.edges,colliders=valid.colliders})
            local nodes={}
            for _,n in ipairs(ctx.world.navigation.nodes) do nodes[n.id]=n end
            for _,id in ipairs(ctx.ai.order) do
                local actor=ctx.ai.actors[id]
                local q=instances[id].query
                for _,target in ipairs(targets) do
                    assert(nav.route(ctx.world.navigation,actor.position,nodes[target],q,ctx.ai.nav_cache),id.." cannot reach "..target)
                    test.routes=test.routes+1
                    coroutine.yield()
                end
                report("ROUTES",{actor=id,targets=#targets})
            end
        end)
    end
    if coroutine.status(test.job)~="dead" then
        local ok,err=coroutine.resume(test.job)
        assert(ok,err)
        return
    end
    if not self.renderer_stats.ready then return end
    ctx.player.enabled=false
    if test.next and test.elapsed<test.next then return end
    if test.capture_due then
        report("SHOT",{id=views[test.view]})
        test.capture_due=false
        test.next=test.elapsed+.75
        return
    end
    test.view=test.view+1
    if test.view>#views then
        local stats=ctx.world.stats
        report("PASS",{routes=test.routes,views=#views,nodes=#ctx.world.navigation.nodes,
            edges=#ctx.world.navigation.edges,colliders=stats.colliders,batches=stats.batches,mesh_bytes=stats.mesh_bytes})
        test.done=true
        return
    end
    self.view=views[test.view]
    msg.post("@render:","renderer_reset_history",{reason="view"})
    -- Keep the camera still after requesting the asynchronous browser capture.
    test.capture_due=true
    test.next=test.elapsed+2
end
return M
