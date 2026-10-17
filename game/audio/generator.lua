-- Backend selection and verification; recipes and resource ownership stay Lua.
local reference=require "game.audio.synth"
local M={}

function M.equal(wav,info,expected,expected_info,key)
    if wav~=expected then
        local first=1
        while first<=math.min(#wav,#expected) and wav:byte(first)==expected:byte(first) do first=first+1 end
        error("Native audio mismatch: "..key.." at WAV byte "..first.." ("..#wav.." / "..#expected.." bytes)")
    end
    assert(info.frames==expected_info.frames and info.duration==expected_info.duration,key.." duration mismatch")
    for _,name in ipairs({"peak","rms"}) do
        assert(math.abs(info[name]-expected_info[name])<=1e-12,key.." "..name.." mismatch")
    end
end

function M.new(recipe,seed,backend,verify)
    assert(backend=="lua" or backend=="native","Invalid audio synthesis backend")
    assert(not verify or backend=="native","Audio verification requires the native backend")
    local job={recipe=recipe}
    if backend=="native" then
        assert(audiosynth,"AudioSynth native extension is required; rebuild the custom engine")
        job.native=audiosynth.new(recipe,seed,reference.parameters(recipe),
            recipe.kind.."/"..recipe.name.."/"..recipe.variant)
        if verify then job.reference=reference.new(recipe,seed) end
    else
        job.reference=reference.new(recipe,seed)
    end
    return job
end

function M.close(job)
    if job.native then audiosynth.close(job.native);job.native=nil end
    job.reference=nil;job.closed=true
end

function M.step(job,budget)
    assert(not job.closed,"Synthesis job is closed")
    local wav,info
    if job.native then
        if profiler then profiler.scope_begin("loading.audio.native."..job.recipe.kind) end
        wav,info=audiosynth.step(job.native,budget)
        if profiler then profiler.scope_end() end
        if job.reference then
            local expected,expected_info=reference.step(job.reference,budget)
            assert((wav~=nil)==(expected~=nil),"Native audio completion mismatch")
            if wav then M.equal(wav,info,expected,expected_info,job.recipe.key) end
        end
    else
        wav,info=reference.step(job.reference,budget)
    end
    if wav then M.close(job) end
    return wav,info
end
return M
