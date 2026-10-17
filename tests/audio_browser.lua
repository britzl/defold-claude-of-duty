-- One completion receipt from the real Wasm engine, after all loading work.
local M={}
function M.update(test,self)
    if test.done then return end
    local ctx=self.ctx
    require("game.runtime").set_paused(ctx,false)
    ctx.ai.enabled=false
    if not ctx.world.ready or not self.renderer_stats.ready or not ctx.world.timings.gameplay then return end
    if not test.samples then
        local audio=require("game.systems.audio").snapshot(ctx)
        test.samples=assert(audio.fingerprints);audio.fingerprints=nil;test.index=1
        print("AUDIO_BROWSER READY "..json.encode({timings=ctx.world.timings,
            audio=audio,world=ctx.world.stats,width=self.renderer_stats.width,height=self.renderer_stats.height}))
    end
    -- Defold console lines are bounded. Emit each fingerprint separately,
    -- after the measured readiness point, instead of truncating a large JSON.
    local sample=test.samples[test.index]
    if sample then
        print("AUDIO_BROWSER SAMPLE "..json.encode(sample));test.index=test.index+1
    else
        print("AUDIO_BROWSER PASS "..json.encode({samples=#test.samples}));test.done=true
    end
end
return M
