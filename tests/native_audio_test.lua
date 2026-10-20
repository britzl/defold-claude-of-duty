-- Engine-only parity and ownership checks, shared by macOS and Wasm.
local synth=require "game.audio.synth"
local generator=require "game.audio.generator"
local M={}
local function render(recipe,seed,backend,budget)
    local job=generator.new(recipe,seed,backend,false)
    while true do
        local wav,info=generator.step(job,budget)
        if wav then return wav,info end
    end
end
local function native(recipe,seed)
    return audiosynth.new(recipe,seed,synth.parameters(recipe),recipe.kind.."/"..recipe.name.."/"..recipe.variant)
end
function M.run()
    assert(audiosynth,"Native audio tests require the extension")
    assert(audiosynth.fingerprint("\0a")~=audiosynth.fingerprint("\0b"),"Fingerprint ignores embedded zeros")
    local recipes=synth.catalog()
    local bytes=0
    for _,recipe in ipairs(recipes) do
        local expected,expected_info=render(recipe,1337,"lua",1024)
        local wav,info=render(recipe,1337,"native",4096)
        generator.equal(wav,info,expected,expected_info,recipe.key)
        local sliced,sliced_info=render(recipe,1337,"native",97)
        generator.equal(sliced,sliced_info,wav,info,recipe.key.." chunk independence")
        bytes=bytes+#wav
    end
    assert(#recipes==77 and bytes==1698124)
    local single={key="single",kind="cloth",name="fabric",duration=1/synth.rate,variant=1,treatment="dry"}
    local single_wav,single_info=render(single,1337,"native",1)
    local single_reference,single_reference_info=render(single,1337,"lua",1)
    generator.equal(single_wav,single_info,single_reference,single_reference_info,"Single-sample boundary")
    local variants={recipes[1],recipes[2],recipes[3],recipes[28],recipes[29],recipes[64],
        recipes[72],recipes[73],recipes[74],recipes[75],recipes[76],recipes[77],
        {key="unicode",kind="mechanic",name="mécanique",duration=.18,variant=2,treatment="dry"}}
    for _,seed in ipairs({-31.75,2147483647,42.5}) do
        for _,recipe in ipairs(variants) do
            local wav,info=render(recipe,seed,"native",113)
            local expected,expected_info=render(recipe,seed,"lua",701)
            generator.equal(wav,info,expected,expected_info,recipe.key.." seed "..seed)
        end
    end
    local r=recipes[1]
    local job=native(r,1337)
    for _,budget in ipairs({0,-1,1.5,65537,math.huge}) do
        assert(not pcall(audiosynth.step,job,budget),"Invalid chunk budget accepted")
    end
    local wav,info
    repeat wav,info=audiosynth.step(job,1024) until wav
    assert(not pcall(audiosynth.step,job,1),"Finished job accepted more samples")
    audiosynth.close(job);audiosynth.close(job)
    assert(not pcall(audiosynth.step,job,1),"Closed job accepted samples")
    local expected,expected_info=render(r,1337,"lua",1024)
    generator.equal(wav,info,expected,expected_info,"Returned WAV outlives native job")
    local cancelled=generator.new(r,1337,"native",false)
    assert(generator.step(cancelled,1)==nil)
    generator.close(cancelled);generator.close(cancelled)
    assert(not pcall(generator.step,cancelled,1),"Cancelled adapter job accepted samples")
    local function invalid(key,value)
        local copy={};for k,v in pairs(r) do copy[k]=v end;copy[key]=value
        assert(not pcall(audiosynth.new,copy,1337,synth.parameters(r),"test"),"Invalid "..key.." accepted")
    end
    invalid("kind","unknown");invalid("treatment","unknown");invalid("variant",0)
    invalid("duration",0);invalid("duration",31);invalid("duration",0/0)
    assert(not pcall(audiosynth.new,r,math.huge,synth.parameters(r),"test"))
    assert(not pcall(audiosynth.new,r,1337,{},"test"))
    assert(not pcall(audiosynth.new,r,1337,{148,56,0,2450,.055,.3,.028,1880},"test"))
    -- Untaken and partially generated buffers must also be reclaimed by GC.
    for _=1,64 do local abandoned=native(recipes[75],1337);audiosynth.step(abandoned,1) end
    collectgarbage("collect")
    print("NATIVE_AUDIO_TEST PASS 77 exact WAVs, 39 seed/stream cases, chunk independence, ownership and cancellation")
end
return M
