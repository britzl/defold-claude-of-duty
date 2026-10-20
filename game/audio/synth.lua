-- Portable offline synthesis: mono PCM16 WAVs, no imported sound assets.
-- Weapon/impact tuning adapts the reference audio/weapons.js and foley.js.
local rng = require "game.rng"
local M = { rate = 22050 }
local sin, exp, pi = math.sin, math.exp, math.pi
local guns = {
    rifle = {148,56,.085,2450,.055,.30,.028,1880},
    smg = {172,72,.060,3050,.040,.19,.021,2200},
    pistol = {186,84,.050,2750,.035,.16,.038,2450},
    explosion = {82,32,.32,1200,.075,.65,.09,350},
}
local surfaces = {
    concrete={180,2600,.075,0}, plaster={220,1900,.050,0},
    metal={150,5200,.030,1750}, wood={320,1500,.045,420},
    dirt={120,700,.090,0}, sand={105,1500,.130,0},
    glass={500,6000,.100,3400}, water={260,1800,.140,620},
    foliage={380,2600,.160,0}, fabric={150,900,.060,0},
    flesh={128,620,.055,0}, rubber={190,1100,.030,260},
}
M.surfaces = {"concrete","plaster","metal","wood","dirt","sand","glass","water","foliage","fabric","flesh","rubber"}
-- Sparse room impulse response, shared exactly by Lua and native synthesis.
-- These are wet-only layers; the mixer continuously blends them with dry audio.
M.room_taps={{.013,.32},{.029,.27},{.043,.23},{.061,.19},{.089,.16},{.127,.13},
    {.173,.10},{.227,.08},{.293,.06},{.367,.045},{.443,.032},{.541,.022}}
local cues={
    ["whizz"]={2,4600,1100,0,.075,.65,0,.20},
    ["crack"]={2,6200,1800,0,.025,.95,0,.10},
    ["heartbeat"]={3,62,48,0,.045,0,0,.34},
    ["tinnitus"]={4,3100,3720,0,1.6,0,0,3.6},
    ["ui/hit"]={5,1250,1900,0,.025,.1,0,.12},
    ["ui/headshot"]={5,1800,2700,0,.045,.12,0,.18},
    ["ui/kill"]={5,660,990,0,.12,.08,0,.36},
    ["ui/confirm"]={5,740,1110,0,.035,0,0,.13},
    ["grenade/pin"]={6,2300,3400,0,.035,.35,0,.18},
    ["grenade/bounce"]={6,280,1900,0,.055,.4,0,.3},
    ["body"]={6,72,180,0,.14,.65,0,.55},
}
local barks={contact={126,570,840,2410,.5,.15,2,.36},
    reload={112,450,900,2300,.5,.16,3,.48},grenade={150,730,1090,2440,.5,.18,2,.40},
    flank={120,730,1090,2440,.5,.18,2,.34},suppress={116,530,1840,2480,.5,.18,4,.57},
    advance={118,325,700,2530,.5,.16,2,.35},hurt={140,640,1200,2500,.5,.4,1,.28},
    death={110,490,1350,1690,.5,.55,2,.8}}
for name,p in pairs(barks) do cues["bark/"..name]={1,p[1],p[2],p[3],p[4],p[6],p[7],p[8]} end
M.cues=cues
local mechanics = {start=480,magout=1400,magdrop=310,magin=980,slap=220,charge=2400,boltrelease=3200,dry=1900}

local function u16(n) return string.char(n%256, math.floor(n/256)%256) end
local function u32(n) return u16(n%65536)..u16(math.floor(n/65536)) end
function M.header(frames)
    local bytes=frames*2
    return "RIFF"..u32(36+bytes).."WAVEfmt "..u32(16)..u16(1)..u16(1)
        ..u32(M.rate)..u32(M.rate*2)..u16(2)..u16(16).."data"..u32(bytes)
end

function M.catalog()
    local out={}
    local function add(key,kind,name,duration,variant,treatment)
        out[#out+1]={key=key,kind=kind,name=name,duration=duration+((kind=="ambience" or kind=="cue") and 0 or .56),variant=variant or 1,treatment=treatment or "dry"}
    end
    for _,name in ipairs({"rifle","smg","pistol"}) do
        for variant=1,3 do
            for _,treatment in ipairs({"dry","room","muffled"}) do
                add("shot/"..name.."/"..variant.."/"..treatment,"shot",name,
                    guns[name][6]*2+.15,variant,treatment)
            end
        end
    end
    for _,name in ipairs(M.surfaces) do
        add("impact/"..name,"impact",name,.42)
        for variant=1,2 do add("step/"..name.."/"..variant,"step",name,.24,variant) end
    end
    for _,name in ipairs({"start","magout","magdrop","magin","slap","charge","boltrelease","dry"}) do
        add("mechanic/"..name,"mechanic",name,.18)
    end
    add("shell","shell","metal",.22)
    add("hurt","hurt","flesh",.3)
    add("cloth","cloth","fabric",.32)
    -- Reuse the portable pressure/body/noise synthesizer with a low, long blast
    -- recipe; both Lua and native backends consume these same parameters.
    add("explosion","shot","explosion",1.6)
    add("ambience/wind","ambience","wind",4)
    add("ambience/city","ambience","city",4)
    for _,name in ipairs({"whizz","crack","heartbeat","tinnitus","ui/hit","ui/headshot","ui/kill","ui/confirm",
        "grenade/pin","grenade/bounce","body","bark/contact","bark/reload","bark/grenade","bark/flank",
        "bark/suppress","bark/advance","bark/hurt","bark/death"}) do
        add(name,"cue",name,cues[name][8]+.56)
    end
    -- Identical lengths, seeds and playback speeds keep all three layers aligned.
    local extra={}
    for _,r in ipairs(out) do
        if r.kind~="shot" or r.name=="explosion" then
            for _,t in ipairs({"muffled","room"}) do
                extra[#extra+1]={key=r.key.."/"..t,kind=r.kind,name=r.name,duration=r.duration,variant=r.variant,treatment=t}
            end
        end
    end
    for _,r in ipairs(extra) do out[#out+1]=r end
    return out
end
function M.layers(key)
    local base=key:match("^(shot/.+/)dry$")
    return {key,base and base.."muffled" or key.."/muffled",base and base.."room" or key.."/room"}
end

-- The native generator consumes the same tuning tables as the Lua reference.
function M.parameters(recipe)
    if recipe.kind=="shot" then return assert(guns[recipe.name]) end
    if recipe.kind=="cue" then return assert(cues[recipe.name]) end
    if recipe.kind=="impact" or recipe.kind=="step" then return assert(surfaces[recipe.name]) end
    if recipe.kind=="mechanic" or recipe.kind=="shell" then return {mechanics[recipe.name] or 3900} end
    return {}
end

function M.new(recipe,seed)
    local frames=math.floor(recipe.duration*M.rate)
    local stream=recipe.kind.."/"..recipe.name.."/"..recipe.variant
    return {recipe=recipe,frames=frames,cursor=0,chunks={},seed=seed,stream=stream,
        random=rng.new(seed,stream),
        -- Prime the filters with whole periods of the same noise. Rewinding
        -- only the random stream leaves the filters continuous at the wrap.
        warmup=recipe.kind=="ambience" and math.max(1,math.ceil(.5*M.rate/frames)) or 0,
        hum_a=math.floor(75*frames/M.rate+.5),hum_b=math.floor(112*frames/M.rate+.5),
        low=0,mid=0,muffle=0,dc=0,phase=0,history_cursor=0,history={},peak=0,square=0}
end

local function sample(job,t)
    local r=job.recipe
    local noise=job.random()*2-1
    job.low=job.low+.055*(noise-job.low)
    job.mid=job.mid+.42*(noise-job.mid)
    local x=0
    local detune=1+(r.variant-2)*.025
    if r.kind=="shot" then
        local p=guns[r.name]
        local f=p[2]+(p[1]-p[2])*exp(-t/.035)
        job.phase=job.phase+2*pi*f*detune/M.rate
        local transient=(noise-job.mid)*.5*exp(-t/.002)
        local body=(sin(job.phase)*.62+sin(job.phase*.5)*.20)*exp(-t/p[3])
        local sub=sin(2*pi*p[2]*1.1*t)*.25*exp(-t/(p[3]*1.4))
        local mid=job.mid*sin(2*pi*(p[4]*.32)*t)*.28*exp(-t/(p[5]*1.1))
        local crack=(noise-job.low)*sin(2*pi*p[4]*t*detune)*.65*exp(-t/p[5])
        local tail=job.mid*.55*exp(-t/p[6])
        local mt=t-p[7]
        local mech=mt>=0 and (.12*sin(2*pi*p[8]*mt)+.07*sin(2*pi*p[8]*1.734*mt)+.04*sin(2*pi*p[8]*2.872*mt)+.07*noise)*exp(-mt/.022) or 0
        x=transient+body+sub+mid+crack+tail+mech
        x=x/(1+math.abs(x)*.7)
    elseif r.kind=="impact" or r.kind=="step" then
        local p=surfaces[r.name]
        local step=r.kind=="step"
        local f=p[1]*(step and .48 or 1)*detune
        local attack=math.min(1,t/(step and .007 or .001))
        local texture=p[2]>2000 and noise-job.low or job.mid
        x=(sin(2*pi*f*t)*.45*exp(-t/.035)+texture*.4*exp(-t/p[3]))*attack
        if p[4]>0 then x=x+sin(2*pi*p[4]*t*detune)*.23*exp(-t/(step and .055 or .12))*attack end
        if step then x=x*.75 end
    elseif r.kind=="mechanic" or r.kind=="shell" then
        local f=mechanics[r.name] or 3900
        local t2=t-.044
        x=(sin(2*pi*f*t)*.3+noise*.35)*exp(-t/.013)
        if t2>0 then x=x+sin(2*pi*f*1.63*t2)*.18*exp(-t2/.027) end
    elseif r.kind=="hurt" then
        x=(sin(2*pi*(95*t-65*t*t))*.55+job.low*.8)*exp(-t/.075)
    elseif r.kind=="cloth" then
        x=job.mid*.7*sin(pi*math.min(1,t/.32))^2
    elseif r.kind=="cue" then
        local p=cues[r.name]
        if t<p[8] then
            if p[1]==1 then
                local f=p[2]*detune*(1+.025*sin(t*71))*(r.name=="bark/death" and (1-.55*t/p[8]) or 1)
                job.phase=job.phase+f/M.rate
                local pulse=job.phase%1
                local voice=exp(-pulse*5)*(sin(2*pi*p[3]*pulse/f)+.55*sin(2*pi*p[4]*pulse/f)+.24*sin(2*pi*p[5]*pulse/f))
                local syllable=(t/p[8]*p[7])%1
                local envelope=sin(pi*math.min(1,syllable/ .88))^2
                x=(voice*.55+job.mid*p[6])*envelope
            elseif p[1]==2 then
                job.phase=job.phase+2*pi*(p[3]+(p[2]-p[3])*exp(-t/.045))/M.rate
                x=((noise-job.low)*p[6]+sin(job.phase)*.2)*exp(-t/p[5])*math.min(1,t/.002)
            elseif p[1]==3 then
                x=sin(2*pi*p[2]*t)*.65*exp(-t/p[5])*math.min(1,t/.008)
                local b=t-.13
                if b>0 then x=x+sin(2*pi*p[3]*b)*.48*exp(-b/.045)*math.min(1,b/.008) end
            elseif p[1]==4 then
                x=(sin(2*pi*p[2]*t)*.24+sin(2*pi*p[3]*t)*.09)*math.min(1,t/.07)*exp(-t/p[5])
            else
                x=(sin(2*pi*p[2]*t)*.42+sin(2*pi*p[3]*t)*.18+job.mid*p[6])*exp(-t/p[5])
            end
        end
    elseif r.kind=="ambience" then
        local wind=r.name=="wind"
        local phase=2*pi*job.cursor/job.frames
        local mod=.7+.3*sin(phase)
        x=wind and (job.low*1.8+job.mid*.05)*mod
            or (job.low*.65+sin(phase*job.hum_a)*.035+sin(phase*job.hum_b)*.025)*mod
    end
    if r.treatment=="room" then
        job.history_cursor=job.history_cursor+1
        local i=job.history_cursor
        job.history[i]=x
        local wet=0
        for _,tap in ipairs(M.room_taps) do wet=wet+(job.history[i-math.floor(tap[1]*M.rate)] or 0)*tap[2] end
        job.history[i-math.floor(.541*M.rate)-1]=nil
        job.muffle=job.muffle+.22*(wet-job.muffle)
        x=job.muffle
    elseif r.treatment=="muffled" then
        job.muffle=job.muffle+.10*(x-job.muffle)
        x=job.muffle
    end
    -- Only one-shots fade to silence. Loop filters are already primed above.
    job.dc=job.dc+.002*(x-job.dc)
    x=x-job.dc
    if r.kind~="ambience" then
        x=x*math.min(1,t/.0005,(job.frames-1-job.cursor)/(M.rate*.018))
    end
    return math.max(-.92,math.min(.92,x*.9))
end

-- At most `budget` samples per call; packing has the same bound.
function M.step(job,budget)
    if profiler then profiler.scope_begin("loading.audio.synthesize."..job.recipe.kind) end
    local bytes={}
    for _=1,budget do
        local x=sample(job,job.cursor/M.rate)
        if job.warmup==0 then
            job.peak=math.max(job.peak,math.abs(x));job.square=job.square+x*x
            bytes[#bytes+1]=u16(math.floor(x*32767+.5)%65536)
        end
        job.cursor=job.cursor+1
        if job.cursor==job.frames then
            if job.warmup==0 then break end
            job.warmup=job.warmup-1;job.cursor=0
            job.random=rng.new(job.seed,job.stream)
        end
    end
    if #bytes>0 then job.chunks[#job.chunks+1]=table.concat(bytes) end
    if profiler then profiler.scope_end() end
    if job.cursor==job.frames then
        if profiler then profiler.scope_begin("loading.audio.wav_finalize") end
        local wav=M.header(job.frames)..table.concat(job.chunks)
        local info={duration=job.frames/M.rate,frames=job.frames,peak=job.peak,rms=math.sqrt(job.square/job.frames)}
        if profiler then profiler.scope_end() end
        return wav,info
    end
end
return M
