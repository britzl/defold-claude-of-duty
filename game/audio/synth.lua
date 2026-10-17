-- Portable offline synthesis: mono PCM16 WAVs, no imported sound assets.
-- Weapon/impact tuning adapts the reference audio/weapons.js and foley.js.
local rng = require "game.rng"
local M = { rate = 22050 }
local sin, exp, pi = math.sin, math.exp, math.pi
local guns = {
    rifle = {148,56,.085,2450,.055,.30,.028,1880},
    smg = {172,72,.060,3050,.040,.19,.021,2200},
    pistol = {186,84,.050,2750,.035,.16,.038,2450},
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
        out[#out+1]={key=key,kind=kind,name=name,duration=duration,variant=variant or 1,treatment=treatment or "dry"}
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
    add("ambience/wind","ambience","wind",4)
    add("ambience/city","ambience","city",4)
    return out
end

-- The native generator consumes the same tuning tables as the Lua reference.
function M.parameters(recipe)
    if recipe.kind=="shot" then return assert(guns[recipe.name]) end
    if recipe.kind=="impact" or recipe.kind=="step" then return assert(surfaces[recipe.name]) end
    if recipe.kind=="mechanic" or recipe.kind=="shell" then return {mechanics[recipe.name] or 3900} end
    return {}
end

function M.new(recipe,seed)
    return {recipe=recipe,frames=math.floor(recipe.duration*M.rate),cursor=0,chunks={},
        random=rng.new(seed,recipe.kind.."/"..recipe.name.."/"..recipe.variant),
        low=0,mid=0,muffle=0,dc=0,phase=0,history={},peak=0,square=0}
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
        local body=sin(job.phase)*.72*exp(-t/p[3])
        local crack=(noise-job.low)*sin(2*pi*p[4]*t*detune)*.65*exp(-t/p[5])
        local tail=job.mid*.55*exp(-t/p[6])
        local mt=t-p[7]
        local mech=mt>=0 and (.12*sin(2*pi*p[8]*mt)+.07*noise)*exp(-mt/.022) or 0
        x=transient+body+crack+tail+mech
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
    elseif r.kind=="ambience" then
        local wind=r.name=="wind"
        local mod=.7+.3*sin(2*pi*t/r.duration)
        x=wind and (job.low*1.8+job.mid*.05)*mod
            or (job.low*.65+sin(2*pi*75*t)*.035+sin(2*pi*112*t)*.025)*mod
        -- Zero at both ends; quiet fade masks the finite loop seam.
        x=x*math.min(1,t/.15,(r.duration-t)/.15)
    end
    if r.treatment=="room" then
        local i=job.cursor+1
        local a=job.history[i-math.floor(.037*M.rate)] or 0
        local b=job.history[i-math.floor(.071*M.rate)] or 0
        job.history[i]=x
        job.history[i-math.floor(.071*M.rate)-1]=nil
        x=(x+a*.32+b*.18)*.82
    elseif r.treatment=="muffled" then
        job.muffle=job.muffle+.10*(x-job.muffle)
        x=job.muffle
    end
    -- Remove DC and fade endpoints. Never normalize quiet variants upward.
    job.dc=job.dc+.002*(x-job.dc)
    x=(x-job.dc)*math.min(1,t/.0005,(job.frames-1-job.cursor)/(M.rate*.018))
    return math.max(-.92,math.min(.92,x*.9))
end

-- At most `budget` samples per call; packing has the same bound.
function M.step(job,budget)
    if profiler then profiler.scope_begin("loading.audio.synthesize."..job.recipe.kind) end
    local bytes={}
    local count=math.min(budget,job.frames-job.cursor)
    for i=1,count do
        local x=sample(job,job.cursor/M.rate)
        job.peak=math.max(job.peak,math.abs(x));job.square=job.square+x*x
        bytes[i]=u16(math.floor(x*32767+.5)%65536)
        job.cursor=job.cursor+1
    end
    job.chunks[#job.chunks+1]=table.concat(bytes)
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
