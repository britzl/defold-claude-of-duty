local events = require "game.events"
local rng = require "game.rng"
local synth = require "game.audio.synth"
local generator = require "game.audio.generator"
local spatial = require "game.audio.spatial"
local content = require "game.audio.content"
local M = { voice_limit=24, queue_limit=64, physical_voice_limit=72, occlusion_budget=4, sample_budget=8192, native_sample_budget=131072 }
local surface_names={}
for _,name in ipairs(synth.surfaces) do surface_names[name]=true end
local function surface(name) return surface_names[name] and name or "concrete" end
local function copy(p) return p and {x=p.x,y=p.y,z=p.z} end
local function queue(a,cue)
    if not a.backend or not a.ready or a.settings.muted or (a.suspended and not cue.ui) then return end
    if #a.pending>=M.queue_limit then
        local victim
        for i,v in ipairs(a.pending) do if v.priority<cue.priority then victim=i;break end end
        a.dropped=a.dropped+1
        if not victim then return end
        table.remove(a.pending,victim)
    end
    cue.position=copy(cue.position)
    cue.at=a.clock
    a.pending[#a.pending+1]=cue
    return cue
end
local function stop(a,v)
    if v.active and not v.stopping then
        v.stopping=true
        a.backend:stop(v.slot)
    end
end
local function cancel_reload(a,tag)
    tag=tag or "reload"
    for i=#a.pending,1,-1 do if a.pending[i].tag==tag then table.remove(a.pending,i) end end
    for _,v in ipairs(a.voices) do if v.tag==tag then stop(a,v) end end
end
function M.init(ctx)
    local backend=ctx.services.audio and sys and sys.get_config_string("audio_synthesis.backend","native") or "lua"
    assert(backend=="lua" or backend=="native","Invalid audio synthesis backend")
    assert(backend~="native" or audiosynth,"AudioSynth native extension is required; rebuild the custom engine")
    local a={backend=ctx.services.audio,ready=not ctx.services.audio,resources={},voices={},pending={},
        synthesis_backend=backend,verify=sys and sys.get_config_int("audio_synthesis.verify",0)==1 or false,verified=0,
        fingerprints=sys and sys.get_config_int("audio_synthesis.fingerprints",0)==1 and {} or nil,
        recipes=synth.catalog(),cursor=1,clock=0,random=rng.new(ctx.world.seed,"audio/playback"),round={},
        settings={master=.8,weapons=1,foley=.8,ambience=.6,muted=false},
        played=0,completed=0,dropped=0,preempted=0,peak_voices=0,bytes=0,work=0,peak_job=0,loaded=0,
        by_kind={},last={},suspended=false,listener={position=copy(ctx.player.position),yaw=0}}
    ctx.audio=a
    for i=1,M.voice_limit do a.voices[i]={slot=i,serial=0,active=false} end
    content.init(ctx,queue,cancel_reload,surface)
    a.occlusion_cursor=0;a.occlusion_queries=0;a.mix_scale=1
end

function M.update(ctx,dt)
    local a=ctx.audio
    if not a.suspended then a.clock=a.clock+dt end
    if a.ready then return end
    if profiler then profiler.scope_begin("loading.audio") end
    local started=os.clock()
    -- Native chunks retain a 2 ms deadline, with a larger safety cap so the
    -- old eight-chunk limit does not force 107 loading updates after the port.
    local remaining=a.synthesis_backend=="native" and M.native_sample_budget or M.sample_budget
    repeat
        local recipe=a.recipes[a.cursor]
        if not recipe then
            a.ready=true
            require("game.world.generator").mark(ctx.world,"audio_ready")
            break
        end
        a.job=a.job or generator.new(recipe,ctx.world.seed,a.synthesis_backend,a.verify)
        local budget=math.min(1024,remaining)
        local wav,info=generator.step(a.job,budget)
        remaining=remaining-budget
        if wav then
            if a.verify then a.verified=a.verified+1 end
            if a.fingerprints then a.fingerprints[#a.fingerprints+1]={key=recipe.key,
                hash=audiosynth.fingerprint(wav),bytes=#wav,frames=info.frames,duration=info.duration,peak=info.peak,rms=info.rms} end
            if profiler then profiler.scope_begin("loading.audio.upload") end
            info.handle=a.backend:load(recipe.key,wav)
            if profiler then profiler.scope_end() end
            a.resources[recipe.key]=info;a.bytes=a.bytes+#wav;a.loaded=a.loaded+1
            a.job=nil;a.cursor=a.cursor+1
        end
    until remaining<=0 or os.clock()-started>=.002
    local elapsed=os.clock()-started
    a.work=a.work+elapsed;a.peak_job=math.max(a.peak_job,elapsed)
    if profiler then profiler.scope_end() end
end

local function start(a,v,cue)
    local sample=a.resources[cue.key]
    if not sample then a.dropped=a.dropped+1;return end
    v.serial=v.serial+1
    local serial=v.serial
    v.active=true;v.stopping=false;v.cue=cue;v.tag=cue.tag
    v.started=a.clock;v.sample=sample;v.gain=0;v.pan=cue.pan or 0
    v.occlusion=0;v.occlusion_target=0;v.room=0;v.next_probe=0
    local layers=synth.layers(cue.key);local handles={}
    v.samples={}
    for i,key in ipairs(layers) do
        local item=assert(a.resources[key],"Missing audio layer: "..key)
        handles[i]=item.handle;v.samples[i]=item
    end
    a.backend:play(v.slot,handles,0,v.pan,cue.speed or 1,function()
        if v.serial==serial then v.active=false;v.stopping=false;a.completed=a.completed+1 end
    end)
    a.played=a.played+1
    a.by_kind[cue.kind]=(a.by_kind[cue.kind] or 0)+1
    a.last={kind=cue.kind,key=cue.key,occluded=false,room=a.indoor or false,position=copy(cue.position),pan=cue.pan or 0,gain=cue.gain}
    v.receipt=a.last
end
function M.fixed_update(ctx,dt)
    content.fixed_update(ctx,dt,queue,surface)
end
function M.present(ctx,dt,position,yaw)
    local a=ctx.audio
    if not a.backend or not a.ready then return end
    a.listener={position=copy(position),yaw=yaw}
    a.indoor=spatial.room(ctx.world,position)
    if a.settings.muted or not ctx.world.ready then
        a.pending={};for _,v in ipairs(a.voices) do stop(a,v) end
        return
    end
    if not a.suspended then
        for i,name in ipairs({"wind","city"}) do
            local v=a.voices[22+i]
            if not v.active then start(a,v,{kind="ambience",key="ambience/"..name,bus="ambience",
                gain=i==1 and .28 or .22,pan=i==1 and -.45 or .4,loop=true}) end
        end
    end
    -- Stable priority admission prevents a fragment flood burying feedback.
    local deferred={}
    for priority=3,1,-1 do for _,cue in ipairs(a.pending) do if cue.priority==priority then
        if (not a.suspended or cue.ui) and a.clock-cue.at<.15 then
            local gain,pan=spatial.mix(a.listener,cue.position,cue.near or 4,cue.range or 40)
            if gain*cue.gain>.002 then
                if cue.kind=="shot" and not cue.key then
                    local name=cue.weapon;a.round[name]=(a.round[name] or 0)%3+1
                    cue.key="shot/"..name.."/"..a.round[name].."/dry"
                end
                cue.speed=cue.speed or (cue.internal and 1 or .975+a.random()*.05);cue.pan=pan
                local slot
                for i=priority==3 and 1 or 5,22 do if not a.voices[i].active then slot=a.voices[i];break end end
                if slot then start(a,slot,cue)
                else
                    local victim,waiting
                    for i=priority==3 and 1 or 5,22 do
                        local v=a.voices[i]
                        if v.stopping then waiting=true
                        elseif v.cue.priority<priority and (not victim or v.cue.priority<victim.cue.priority
                            or (v.cue.priority==victim.cue.priority and v.started<victim.started)) then victim=v end
                    end
                    -- A stopped component remains owned until all three completion
                    -- callbacks arrive. Retry the original cue, preserving its age,
                    -- timbre and pitch; never attach a new buffer to a live slot.
                    if cue.waiting and a.voices[cue.waiting].stopping then victim=nil end
                    if victim then
                        stop(a,victim);cue.waiting=victim.slot;waiting=true;a.preempted=a.preempted+1
                    end
                    if priority>1 and waiting then deferred[#deferred+1]=cue
                    else a.dropped=a.dropped+1 end
                end
            else a.dropped=a.dropped+1 end
        else a.dropped=a.dropped+1 end
    end end end
    a.pending=deferred
    -- Long barks follow their speaker; gunshots/impacts keep their firing point.
    for _,v in ipairs(a.voices) do
        local actor=v.active and v.cue.source and ctx.ai.actors[v.cue.source]
        if actor and actor.actor.alive then
            local p=actor.position;v.cue.position={x=p.x,y=p.y+1.35,z=p.z}
        end
    end
    -- Four emitter probes (two Bullet rays each) per presentation, round robin.
    local probes=0
    for _=1,M.voice_limit do
        a.occlusion_cursor=a.occlusion_cursor%M.voice_limit+1
        local v=a.voices[a.occlusion_cursor]
        if v.active and not v.stopping and v.cue.position and a.clock>=v.next_probe then
            local amount=a.backend:occluded(position,v.cue.position)
            if type(amount)=="boolean" then amount=amount and 1 or 0 end
            v.occlusion_target=amount;v.next_probe=a.clock+.06
            v.receipt.occluded=amount>0
            probes=probes+1
            if probes==M.occlusion_budget then break end
        end
    end
    a.occlusion_queries=a.occlusion_queries+probes;a.last_probes=probes
    local active,peak_sum=0,0
    local blend=1-math.exp(-math.min(dt,.1)/.045)
    for _,v in ipairs(a.voices) do if v.active and not v.stopping then
        local cue=v.cue
        local gain,pan,distance=spatial.mix(a.listener,cue.position,cue.near or 4,cue.range or 40)
        v.occlusion=v.occlusion+(v.occlusion_target-v.occlusion)*blend
        local indoor=a.indoor or (cue.position and spatial.room(ctx.world,cue.position))
        local wet=cue.internal and 0 or indoor and .48 or .06
        v.room=v.room+(wet-v.room)*blend
        local dark=cue.internal and 0 or math.min(1,math.max(v.occlusion,a.deafness,distance/160,cue.distant and .65 or 0))
        gain=gain*(1-v.occlusion*.65)
        if cue.loop then gain=gain*(a.indoor and .23 or 1);pan=cue.pan end
        if not cue.internal then gain=gain*(1-a.deafness*.55) end
        if cue.bus=="ambience" then gain=gain*(1-a.duck*.8) end
        v.target_gain=cue.gain*gain*a.settings[cue.bus]*a.settings.master
        v.pan=v.pan+(pan-v.pan)*blend
        v.weights={1-dark,dark,v.room*(1-dark*.7)}
        v.dark=dark;active=active+1
        for i,sample in ipairs(v.samples) do peak_sum=peak_sum+v.target_gain*v.weights[i]*sample.peak end
        if not cue.loop and a.clock-v.started>v.sample.duration/(cue.speed or 1)+2 then stop(a,v) end
    end end
    local target=math.min(1,.85/math.max(.001,peak_sum))
    a.mix_scale=math.min(target,a.mix_scale+dt*2)
    for _,v in ipairs(a.voices) do if v.active and not v.stopping then
        v.gain=v.target_gain*a.mix_scale
        a.backend:mix(v.slot,v.gain,v.pan,v.weights)
    end end
    a.peak_voices=math.max(a.peak_voices,active)
end
local function silence(a)
    a.pending={}
    for _,v in ipairs(a.voices) do stop(a,v) end
end
function M.reset(ctx)
    local a=ctx.audio
    silence(a);a.round={};a.stance=nil;a.random=rng.new(ctx.world.seed,"audio/playback")
    content.reset(a,ctx.world.seed);a.mix_scale=1
end
function M.suspend(ctx,value)
    ctx.audio.suspended=value
    if value then silence(ctx.audio) end
end
function M.ui(ctx)
    local a=ctx.audio
    -- Slider drags may publish every frame; rate-limit their acknowledgement.
    local clock=ctx.time.frame_elapsed
    if clock<(a.ui_until or 0) then return end
    a.ui_until=clock+.09
    queue(a,{kind="ui",key="ui/confirm",gain=.25,bus="foley",priority=3,internal=true,ui=true})
end

function M.preview(ctx,data)
    assert(data.kind=="shot" or data.kind=="impact" or data.kind=="step","Expected shot, impact or step")
    if data.position then
        assert(type(data.position)=="table","Expected position")
        for _,key in ipairs({"x","y","z"}) do
            local n=data.position[key]
            assert(type(n)=="number" and n==n and math.abs(n)<10000,"Invalid position")
        end
    end
    local cue={kind=data.kind,position=data.position,priority=2,gain=.6,near=8,range=100,bus="foley"}
    if data.kind=="shot" then
        assert(data.weapon=="rifle" or data.weapon=="smg" or data.weapon=="pistol","Invalid weapon")
        cue.weapon=data.weapon;cue.bus="weapons"
    else
        assert(surface_names[data.surface],"Invalid surface")
        cue.key=data.kind=="step" and "step/"..data.surface.."/1" or "impact/"..data.surface
    end
    queue(ctx.audio,cue)
    return {queued=#ctx.audio.pending}
end
function M.configure(ctx,settings)
    local a=ctx.audio
    -- Validate the entire patch before applying it.
    for key,value in pairs(settings) do
        assert(a.settings[key]~=nil,"Unknown audio setting: "..tostring(key))
        if key=="muted" then assert(type(value)=="boolean","muted must be boolean")
        else assert(type(value)=="number" and value==value and value>=0 and value<=1,"Audio gain must be 0..1") end
    end
    for key,value in pairs(settings) do a.settings[key]=value end
    if a.settings.muted then silence(a) end
    return M.snapshot(ctx)
end
function M.snapshot(ctx)
    local a=ctx.audio
    local active,voices=0,{}
    for _,v in ipairs(a.voices) do
        if v.active then
            active=active+1
            voices[#voices+1]={slot=v.slot,key=v.cue.key,gain=v.gain,pan=v.pan,stopping=v.stopping,occlusion=v.occlusion,dark=v.dark,wet=v.room,weights=v.weights}
        end
    end
    return {ready=a.ready,loaded=a.loaded,total=#a.recipes,bytes=a.bytes,sample_rate=synth.rate,
        synthesis_backend=a.synthesis_backend,verified=a.verified,fingerprints=a.fingerprints,
        active=active,voice_limit=M.voice_limit,physical_voice_limit=M.physical_voice_limit,
        processing="layered_pcm",hrtf=false,deafness=a.deafness,duck=a.duck,scene_clock=a.scene_clock,
        occlusion_queries=a.occlusion_queries,last_probes=a.last_probes or 0,peak_voices=a.peak_voices,pending=#a.pending,
        played=a.played,completed=a.completed,dropped=a.dropped,preempted=a.preempted,by_kind=a.by_kind,last=a.last,
        settings=a.settings,suspended=a.suspended,indoor=a.indoor or false,voices=voices,
        work_ms=a.work*1000,peak_job_ms=a.peak_job*1000,
        meter=a.backend and a.backend:meter() or {left=0,right=0}}
end
function M.final(ctx)
    local a=ctx.audio
    if a.job then generator.close(a.job) end
    events.off_owner(ctx.events,a)
    if a.backend then
        M.reset(ctx)
        a.backend:final(a.resources)
    end
    a.job=nil;a.pending={};a.resources={}
    ctx.audio=nil
end
return M
