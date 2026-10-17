-- Opt-in console protocol for the real HTML5 engine. Fingerprinting starts
-- after the measured ready point, never inside a timed loading phase.
local M={}
function M.new() return {index=1} end
function M.update(test,self)
    if test.done then return end
    local ctx=self.ctx
    require("game.runtime").set_paused(ctx,false)
    ctx.ai.enabled=false
    local world=ctx.world
    if not world.ready or not self.renderer_stats.ready or not world.timings.gameplay then return end
    require("game.world.generator").mark(world,"playable")
    if not test.started then
        test.started=true
        print("MESH_BROWSER READY "..json.encode({backend=world.mesh_backend,verified=world.verify_mesh or false,
            timings=world.timings,work_ms=world.work_seconds*1000,peak_job_ms=world.peak_job_seconds*1000,stats=world.stats}))
    end
    local batch=world.batches[test.index]
    if batch then
        local data=resource.get_buffer(batch.resource)
        local entry={key=batch.key,vertices=batch.vertex_count,bounds=batch.bounds,streams={}}
        for _,name in ipairs({"position","normal","color","surface_edges","surface_masks","surface_data"}) do
            if name~="surface_data" or not batch.glass then
                local bytes=buffer.get_bytes(data,hash(name))
                entry.streams[name]={bytes=#bytes,hash=hash_to_hex(hash(bytes))}
            end
        end
        print("MESH_BROWSER BATCH "..json.encode(entry));test.index=test.index+1
    else
        print("MESH_BROWSER PASS "..json.encode({batches=#world.batches,actors=#ctx.ai.order}))
        test.done=true
    end
end
return M
