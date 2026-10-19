local events = require "game.events"
local rng = require "game.rng"
local synth = require "game.audio.synth"
local generator = require "game.audio.generator"
local spatial = require "game.audio.spatial"
local M = { voice_limit=24, queue_limit=64, sample_budget=8192, native_sample_budget=131072 }
local surface_names={}
for _,name in ipairs(synth.surfaces) do surface_names[name]=true end
local function surface(name) return surface_names[name] and name or "concrete" end
local function copy(p) return p and {x=p.x,y=p.y,z=p.z} end
local function queue(a,cue)
    if not a.backend or not a.ready or a.settings.muted or a.suspended then return end
    if #a.pending>=M.queue_limit then a.dropped=a.dropped+1;return end
    cue.position=copy(cue.position)
    cue.at=a.clock
    a.pending[#a.pending+1]=cue
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
        played=0,completed=0,dropped=0,peak_voices=0,bytes=0,work=0,peak_job=0,loaded=0,
        by_kind={},last={},suspended=false,listener={position=copy(ctx.player.position),yaw=0}}
    ctx.audio=a
    for i=1,M.voice_limit do a.voices[i]={slot=i,serial=0,active=false} end
    events.on(ctx.events,events.WEAPON_FIRE,a,function(_,hit)
        local first=not hit.source or hit.source=="player"
        local name=(hit.weapon=="smg" or hit.weapon=="pistol") and hit.weapon or "rifle"
        queue(a,{kind="shot",weapon=name,position=not first and (hit.origin or hit.position) or nil,
            gain=first and .8 or .9,bus="weapons",priority=first and 3 or 2,near=8,range=100})
    end)
    events.on(ctx.events,events.WEAPON_DRY,a,function()
        queue(a,{kind="dry",key="mechanic/dry",gain=.35,bus="foley",priority=3})
    end)
    events.on(ctx.events,events.WEAPON_RELOAD,a,function(_,hit)
        local tag=hit.source and hit.source~="player" and "reload/"..hit.source or "reload"
        if hit.phase=="cancel" then cancel_reload(a,tag);return end
        if hit.phase=="end" then return end
        queue(a,{kind="reload",tag=tag,position=hit.position,key="mechanic/"..hit.phase,gain=.45,bus="foley",priority=2})
    end)
    events.on(ctx.events,events.PLAYER_FOOTSTEP,a,function(_,hit)
        local name=surface(hit.surface)
        a.round[name]=(a.round[name] or 0)%2+1
        queue(a,{kind="step",key="step/"..name.."/"..a.round[name],gain=hit.running and .55 or .34,bus="foley",priority=1})
    end)
    events.on(ctx.events,events.PLAYER_LAND,a,function(_,hit)
        queue(a,{kind="land",key="step/"..surface(hit.surface).."/1",
            gain=math.min(.8,.2+(hit.velocity or 0)*.055),speed=.8,bus="foley",priority=2})
    end)
    events.on(ctx.events,events.BULLET_IMPACT,a,function(_,hit)
        if hit.exit then return end -- entry and exit on a thin wall are one audible contact
        queue(a,{kind="impact",key="impact/"..surface(hit.audio or hit.surface),position=hit.point,
            gain=.42,bus="foley",priority=1,near=5,range=45})
    end)
    events.on(ctx.events,events.WEAPON_SHELL,a,function(_,hit)
        -- The visual casing has no collision simulation: this is its ejection tick.
        queue(a,{kind="shell",key="shell",position=hit.position,gain=.11,bus="foley",priority=1,near=3,range=12})
    end)
    events.on(ctx.events,events.DAMAGE_TAKEN,a,function()
        queue(a,{kind="hurt",key="hurt",gain=.6,bus="foley",priority=3})
    end)
    events.on(ctx.events,events.ACTOR_DEATH,a,function(_,hit)
        if hit.actor=="player" then cancel_reload(a) end
    end)
    events.on(ctx.events,events.PLAYER_STATE,a,function(_,state)
        if state.stance~=a.stance or state.sliding~=a.sliding or state.mantling~=a.mantling then
            if a.stance then queue(a,{kind="cloth",key="cloth",gain=.2,bus="foley",priority=1}) end
            a.stance,a.sliding,a.mantling=state.stance,state.sliding,state.mantling
        end
    end)
end

function M.update(ctx,dt)
    local a=ctx.audio
    a.clock=a.clock+dt
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
    -- Per-slot generation ignores late completion from a previous playback.
    a.backend:play(v.slot,sample.handle,0,v.pan,cue.speed or 1,function()
        if v.serial==serial then v.active=false;v.stopping=false;a.completed=a.completed+1 end
    end)
    a.played=a.played+1
    a.by_kind[cue.kind]=(a.by_kind[cue.kind] or 0)+1
    a.last={kind=cue.kind,key=cue.key,occluded=cue.occluded or false,room=cue.room or false,
        position=copy(cue.position),pan=cue.pan or 0,gain=cue.gain}
end

function M.present(ctx,dt,position,yaw)
    local a=ctx.audio
    if not a.backend or not a.ready then return end
    a.listener={position=copy(position),yaw=yaw}
    a.indoor=spatial.room(ctx.world,position)
    if a.settings.muted or a.suspended or not ctx.world.ready then
        a.pending={}
        for _,v in ipairs(a.voices) do stop(a,v) end
        return
    end
    -- Two dedicated looping voices cannot consume the effects pool.
    for i,name in ipairs({"wind","city"}) do
        local v=a.voices[22+i]
        if not v.active then start(a,v,{kind="ambience",key="ambience/"..name,bus="ambience",
            gain=i==1 and .28 or .22,pan=i==1 and -.45 or .4,loop=true}) end
    end
    for _,cue in ipairs(a.pending) do
        if a.clock-cue.at<.15 then
            local gain,pan,distance=spatial.mix(a.listener,cue.position,cue.near or 4,cue.range or 40)
            if gain*cue.gain>.002 then
                local blocked=cue.position and distance>1 and a.backend:occluded(position,cue.position) or false
                if blocked then gain=gain*.35 end
                cue.occluded=blocked;cue.room=a.indoor
                if cue.kind=="shot" then
                    local name=cue.weapon
                    a.round[name]=(a.round[name] or 0)%3+1
                    cue.key="shot/"..name.."/"..a.round[name].."/"..(blocked and "muffled" or a.indoor and "room" or "dry")
                end
                cue.speed=cue.speed or (.975+a.random()*.05)
                cue.pan=pan
                local slot
                -- Four slots are reserved for local shots/damage/dry fire.
                for i=cue.priority==3 and 1 or 5,22 do
                    if not a.voices[i].active then slot=a.voices[i];break end
                end
                if slot then start(a,slot,cue) else a.dropped=a.dropped+1 end
            else a.dropped=a.dropped+1 end
        else a.dropped=a.dropped+1 end
    end
    a.pending={}
    local active,peak_sum=0,0
    for _,v in ipairs(a.voices) do
        if v.active and not v.stopping then
            local cue=v.cue
            local gain,pan=spatial.mix(a.listener,cue.position,cue.near or 4,cue.range or 40)
            if cue.occluded then gain=gain*.35 end
            if cue.loop then gain=gain*(a.indoor and .23 or 1);pan=cue.pan end
            v.target_gain=cue.gain*gain*a.settings[cue.bus]*a.settings.master
            v.pan=pan;active=active+1;peak_sum=peak_sum+v.target_gain*v.sample.peak
            if not cue.loop and a.clock-v.started>v.sample.duration/(cue.speed or 1)+2 then stop(a,v) end
        end
    end
    -- Conservative peak budget gives simultaneous fire/impacts headroom without
    -- a platform-specific DSP extension. Fast reduction, smooth recovery.
    local target=math.min(1,.85/math.max(.001,peak_sum))
    a.mix_scale=math.min(target,(a.mix_scale or 1)+dt*2)
    for _,v in ipairs(a.voices) do
        if v.active and not v.stopping then
            v.gain=v.target_gain*a.mix_scale
            a.backend:mix(v.slot,v.gain,v.pan)
        end
    end
    a.peak_voices=math.max(a.peak_voices,active)
end

function M.reset(ctx)
    local a=ctx.audio
    a.pending={};a.round={};a.stance=nil;a.random=rng.new(ctx.world.seed,"audio/playback")
    for _,v in ipairs(a.voices) do stop(a,v) end
end
function M.suspend(ctx,value)
    ctx.audio.suspended=value
    if value then M.reset(ctx) end
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
    if a.settings.muted then M.reset(ctx) end
    return M.snapshot(ctx)
end
function M.snapshot(ctx)
    local a=ctx.audio
    local active,voices=0,{}
    for _,v in ipairs(a.voices) do
        if v.active then
            active=active+1
            voices[#voices+1]={slot=v.slot,key=v.cue.key,gain=v.gain,pan=v.pan,stopping=v.stopping}
        end
    end
    return {ready=a.ready,loaded=a.loaded,total=#a.recipes,bytes=a.bytes,sample_rate=synth.rate,
        synthesis_backend=a.synthesis_backend,verified=a.verified,fingerprints=a.fingerprints,
        active=active,voice_limit=M.voice_limit,peak_voices=a.peak_voices,pending=#a.pending,
        played=a.played,completed=a.completed,dropped=a.dropped,by_kind=a.by_kind,last=a.last,
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
