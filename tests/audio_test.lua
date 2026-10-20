package.path="./?.lua;"..package.path
local synth=require "game.audio.synth"
local audio=require "game.systems.audio"
local spatial=require "game.audio.spatial"
local runtime=require "game.runtime"
local events=require "game.events"
local input=require "game.input"
local count=0
local function test(name,run) run();count=count+1;print("PASS "..name) end
local function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..tostring(b)) end
local function render(recipe,budget,seed)
    local job=synth.new(recipe,seed or 1337)
    while true do local wav,info=synth.step(job,budget);if wav then return wav,info end end
end
local bank={}
test("every generated WAV is PCM16 mono, finite, audible and bounded; one-shots fade at both ends",function()
    local bytes=0
    for _,recipe in ipairs(synth.catalog()) do
        local wav,info=render(recipe,1024)
        local function uint(i,n)
            local value=0;for k=n-1,0,-1 do value=value*256+wav:byte(i+k) end;return value
        end
        assert(wav:sub(1,4)=="RIFF" and wav:sub(9,16)=="WAVEfmt ")
        assert(uint(5,4)==#wav-8 and uint(21,2)==1 and uint(23,2)==1)
        assert(uint(25,4)==22050 and uint(35,2)==16 and uint(41,4)==#wav-44)
        if recipe.kind~="ambience" then assert(uint(45,2)==0 and uint(#wav-1,2)==0) end
        assert(info.peak<.93 and info.rms>.002,recipe.key.." rms="..info.rms)
        for i=45,#wav,2 do local n=uint(i,2);if n>32767 then n=n-65536 end;assert(math.abs(n)<30500) end
        bank[recipe.key]={wav=wav,info=info,recipe=recipe};bytes=bytes+#wav
    end
    assert(bytes==10611456);print("AUDIO BANK",#synth.catalog(),"samples",bytes,"bytes")
end)
test("ambience wraps at sustained volume without a click, independent of loading budget",function()
    local function pcm(wav,frame)
        local a,b=wav:byte(45+frame*2,46+frame*2)
        local n=a+b*256
        return (n>32767 and n-65536 or n)/32767
    end
    for _,name in ipairs({"wind","city","wind/muffled","city/muffled","wind/room","city/room"}) do
        local item=bank["ambience/"..name]
        assert(render(item.recipe,97)==item.wav,name.." changes with loading budget")
        for _,seed in ipairs({1337,42,-31.75,2147483647}) do
            local wav,info=render(item.recipe,1024,seed)
            -- Inspect the audible signal on both sides of repeated joins.
            -- Endpoint zeroes alone miss the old 150 ms fade-to-silence gap.
            local window=math.floor(.02*synth.rate)
            for _,first in ipairs({0,info.frames-window}) do
                local square=0
                for i=first,first+window-1 do square=square+pcm(wav,i)^2 end
                local rms=math.sqrt(square/window)
                assert(rms>info.rms*.5 and rms<info.rms*1.5,name.." volume dip/spike at wrap")
            end
            local variation=0
            for i=1,info.frames-1 do variation=variation+(pcm(wav,i)-pcm(wav,i-1))^2 end
            local typical=math.sqrt(variation/(info.frames-1))
            local jump=math.abs(pcm(wav,0)-pcm(wav,info.frames-1))
            assert(jump<typical*4,name.." discontinuity at wrap")
        end
    end
end)
test("loading budgets do not change samples; guns/variants differ and muffling removes high frequencies",function()
    local dry=bank["shot/rifle/1/dry"]
    assert(render(dry.recipe,97)==dry.wav)
    assert(dry.wav~=bank["shot/rifle/2/dry"].wav)
    assert(dry.wav~=bank["shot/smg/1/dry"].wav and dry.wav~=bank["shot/pistol/1/dry"].wav)
    local function variation(wav)
        local sum,previous=0,0
        for i=45,#wav,2 do
            local n=wav:byte(i)+wav:byte(i+1)*256;if n>32767 then n=n-65536 end
            sum=sum+(n-previous)^2;previous=n
        end
        return sum
    end
    assert(variation(bank["shot/rifle/1/muffled"].wav)<variation(dry.wav)*.1)
    assert(dry.wav~=bank["shot/rifle/1/room"].wav)
end)
local function backend()
    local b={loaded=0,playing={},blocked=false}
    function b:load(key,wav) self.loaded=self.loaded+1;assert(wav==bank[key].wav);return key end
    function b:play(slot,keys,gain,pan,speed,done)
        assert(not self.playing[slot],"slot reused before completion")
        self.playing[slot]={key=keys[1],keys=keys,gain=gain,pan=pan,speed=speed,done=done}
    end
    function b:mix(slot,gain,pan,weights) local v=assert(self.playing[slot]);v.gain=gain;v.pan=pan;v.weights=weights end
    function b:stop(slot) local v=self.playing[slot];if v then v.stopped=true end end
    function b:finish(slot) local v=self.playing[slot];self.playing[slot]=nil;if v then v.done() end end
    function b:finish_all() for i=1,24 do self:finish(i) end end
    function b:occluded() return self.blocked end
    function b:meter() return {left=0,right=0} end
    function b:final(resources)
        for _,v in pairs(self.playing) do assert(v.stopped) end
        self:finish_all();self.released=0
        for _ in pairs(resources) do self.released=self.released+1 end
    end
    return b
end
local function context(load)
    local b=backend()
    local ctx=runtime.new({audio=b})
    if load then
        for i=1,20000 do
            audio.update(ctx,1/60)
            if ctx.audio.ready then break end
        end
        assert(ctx.audio.ready and b.loaded==234)
    else
        for key,item in pairs(bank) do
            ctx.audio.resources[key]={handle=key,duration=item.info.duration,peak=item.info.peak}
        end
        ctx.audio.ready=true
    end
    ctx.world.ready=true
    return ctx,b
end
local function present(ctx,p,yaw) audio.present(ctx,1/60,p or {x=0,y=1.66,z=0},yaw or 0) end
local function emit(ctx,name,data) events.emit(ctx.events,name,data or {}) end
test("incremental bank loading keeps gameplay gated until audio resources exist",function()
    local b=backend();local ctx=runtime.new({audio=b})
    ctx.world.phase="settle"
    input.button(ctx.input,"fire",{pressed=true})
    runtime.fixed_update(ctx,1/120);runtime.update(ctx,1/60)
    assert(not ctx.world.ready and ctx.weapons.sim.fired==0 and b.loaded<234)
    runtime.final(ctx)
    local loaded,adapter=context(true)
    assert(loaded.audio.bytes==10611456)
    runtime.final(loaded);assert(adapter.released==234)
end)
test("listener yaw, distance and room height determine attenuation and stereo direction",function()
    local listener={position={x=0,y=1.66,z=0},yaw=0}
    local gain,pan=spatial.mix(listener,{x=5,y=1.66,z=0},8,100)
    assert(gain>0 and pan>0)
    listener.yaw=math.pi
    local _,opposite=spatial.mix(listener,{x=5,y=1.66,z=0},8,100);near(pan,-opposite)
    local far=spatial.mix(listener,{x=50,y=1.66,z=0},8,100);assert(far<gain)
    near(spatial.mix(listener,{x=101,y=1.66,z=0},8,100),0)
    local ctx=context()
    assert(spatial.room(ctx.world,{x=-12,y=1.8,z=0}))
    assert(spatial.room(ctx.world,{x=-12,y=5,z=0}))
    assert(not spatial.room(ctx.world,{x=-12,y=3.25,z=0})) -- inside the floor slab
    assert(not spatial.room(ctx.world,{x=-12,y=8,z=0})) -- above the roof
    for _,y in ipairs({1.8,5,8.2}) do assert(spatial.room(ctx.world,{x=10,y=y,z=-7})) end
    for _,y in ipairs({3.25,6.45,10}) do assert(not spatial.room(ctx.world,{x=10,y=y,z=-7})) end
    assert(not spatial.room(ctx.world,{x=5.5,y=1.8,z=-6.5})) -- pavement outside E2
    runtime.final(ctx)
end)
test("player and enemy fire use the same bank with copied positions, occlusion and room variants",function()
    local ctx,b=context()
    local point={x=5,y=1.66,z=0}
    emit(ctx,events.WEAPON_FIRE,{weapon="rifle",source="enemy_1",position=point})
    point.x=-5;present(ctx)
    assert(ctx.audio.last.pan>0 and ctx.audio.last.key=="shot/rifle/1/dry")
    b:finish_all();b.blocked=true
    emit(ctx,events.WEAPON_FIRE,{weapon="smg",source="enemy_1",position=point});present(ctx)
    assert(ctx.audio.last.occluded and ctx.audio.last.key=="shot/smg/1/dry")
    b:finish_all()
    emit(ctx,events.WEAPON_FIRE,{weapon="pistol",origin=point});present(ctx,{x=-12,y=1.8,z=0})
    assert(not ctx.audio.last.occluded and ctx.audio.last.key=="shot/pistol/1/dry" and ctx.audio.last.room)
    near(ctx.audio.last.pan,0)
    runtime.final(ctx)
end)
test("reload cancellation discards pending beats and stops the current mechanical sound",function()
    local ctx,b=context()
    emit(ctx,events.WEAPON_RELOAD,{phase="magout"});present(ctx)
    assert(ctx.audio.by_kind.reload==1)
    emit(ctx,events.WEAPON_RELOAD,{phase="magin"})
    emit(ctx,events.WEAPON_RELOAD,{phase="cancel"});present(ctx)
    assert(ctx.audio.by_kind.reload==1)
    assert(b.playing[5].stopped)
    b:finish_all()
    emit(ctx,events.WEAPON_RELOAD,{phase="magout"});present(ctx)
    emit(ctx,events.ACTOR_DEATH,{actor="player"})
    assert(b.playing[5].stopped)
    runtime.final(ctx)
end)
test("enemy reloads remain spatial and cancellation is scoped to their actor",function()
    local ctx,b=context()
    emit(ctx,events.WEAPON_RELOAD,{source="enemy_1",phase="magout",position={x=4,y=1,z=-6}});present(ctx)
    assert(ctx.audio.last.pan>0)
    emit(ctx,events.WEAPON_RELOAD,{phase="magout"});present(ctx)
    local enemy,player
    for _,v in ipairs(ctx.audio.voices) do
        if v.tag=="reload/enemy_1" then enemy=v.slot elseif v.tag=="reload" then player=v.slot end
    end
    assert(enemy and player)
    emit(ctx,events.WEAPON_RELOAD,{source="enemy_2",phase="magin",position={x=-4,y=1,z=-6}})
    emit(ctx,events.WEAPON_RELOAD,{source="enemy_1",phase="cancel"})
    assert(b.playing[enemy].stopped and not b.playing[player].stopped)
    assert(#ctx.audio.pending==1 and ctx.audio.pending[1].tag=="reload/enemy_2")
    runtime.final(ctx)
end)
test("surface routes, alternating feet, dry fire, hurt and landing consume notifications without applying damage",function()
    local ctx,b=context()
    local health=ctx.player.actor.health
    for _,name in ipairs(synth.surfaces) do
        emit(ctx,events.PLAYER_FOOTSTEP,{surface=name});present(ctx)
        assert(ctx.audio.last.key=="step/"..name.."/1")
        b:finish_all()
        emit(ctx,events.PLAYER_FOOTSTEP,{surface=name});present(ctx)
        assert(ctx.audio.last.key=="step/"..name.."/2")
        b:finish_all()
        emit(ctx,events.BULLET_IMPACT,{surface=name,point={x=1,y=1,z=0}});present(ctx)
        assert(ctx.audio.last.key=="impact/"..name);b:finish_all()
    end
    local impacts=ctx.audio.by_kind.impact
    emit(ctx,events.BULLET_IMPACT,{surface="wood",exit=true});present(ctx)
    assert(ctx.audio.by_kind.impact==impacts)
    emit(ctx,events.WEAPON_DRY);emit(ctx,events.DAMAGE_TAKEN,{amount=12})
    emit(ctx,events.PLAYER_LAND,{velocity=5,surface="wood"});present(ctx)
    assert(ctx.audio.by_kind.dry==1 and ctx.audio.by_kind.hurt==1 and ctx.audio.by_kind.land==1)
    assert(ctx.player.actor.health==health)
    runtime.final(ctx)
end)
test("event floods are bounded, reserve player voices, and keep the peak mix below clipping",function()
    local ctx,b=context()
    for _=1,200 do emit(ctx,events.BULLET_IMPACT,{surface="metal",point={x=1,y=1,z=0}}) end
    assert(#ctx.audio.pending==64);present(ctx)
    for _=1,20 do emit(ctx,events.WEAPON_FIRE,{weapon="rifle"}) end
    present(ctx)
    assert(audio.snapshot(ctx).active==24 and ctx.audio.by_kind.shot==4 and ctx.audio.dropped>0)
    local sum=0
    for slot,v in pairs(b.playing) do if not v.stopped then
        for i,sample in ipairs(ctx.audio.voices[slot].samples) do sum=sum+v.gain*v.weights[i]*sample.peak end
    end end
    assert(sum<=.850001)
    audio.reset(ctx)
    emit(ctx,events.WEAPON_FIRE,{weapon="rifle"});present(ctx)
    assert(ctx.audio.by_kind.shot==4) -- stopping slots cannot be reused yet
    b:finish_all();present(ctx)
    assert(audio.snapshot(ctx).active==3 and ctx.audio.by_kind.shot==5) -- the fresh post-reset cue retries
    runtime.final(ctx)
end)
test("priority sounds replace effect tails only after all layer callbacks release the slot",function()
    local ctx,b=context()
    for _=1,18 do emit(ctx,events.BULLET_IMPACT,{surface="metal",point={x=1,y=1,z=0}}) end
    present(ctx)
    for _=1,20 do emit(ctx,events.WEAPON_FIRE,{weapon="rifle"}) end
    present(ctx)
    assert(ctx.audio.by_kind.shot==4 and #ctx.audio.pending==16 and ctx.audio.preempted==16)
    local key=ctx.audio.pending[1].key;local played=ctx.audio.played
    present(ctx)
    assert(ctx.audio.played==played and ctx.audio.pending[1].key==key)
    for slot,v in pairs(b.playing) do if v.stopped then b:finish(slot) end end
    present(ctx)
    assert(ctx.audio.by_kind.shot==20 and #ctx.audio.pending==0 and audio.snapshot(ctx).active<=24)
    runtime.final(ctx)
end)
test("mute/focus/reset clear transient sounds, preserve the bank and never replay old events",function()
    local ctx,b=context()
    emit(ctx,events.WEAPON_FIRE,{weapon="rifle"});present(ctx)
    audio.configure(ctx,{muted=true})
    for _,v in pairs(b.playing) do assert(v.stopped) end
    b:finish_all();emit(ctx,events.WEAPON_FIRE,{weapon="rifle"});present(ctx)
    assert(audio.snapshot(ctx).active==0)
    audio.configure(ctx,{muted=false});present(ctx)
    assert(audio.snapshot(ctx).active==2 and ctx.audio.by_kind.shot==1)
    audio.suspend(ctx,true);b:finish_all();present(ctx)
    assert(audio.snapshot(ctx).active==0)
    audio.suspend(ctx,false);present(ctx);assert(audio.snapshot(ctx).active==2)
    local saved=ctx.audio.settings.master
    assert(not pcall(audio.configure,ctx,{master=.4,weapons=0/0}))
    near(ctx.audio.settings.master,saved)
    assert(not pcall(audio.configure,ctx,{bad=1}))
    assert(not pcall(audio.preview,ctx,{kind="shot",weapon="rifle",position={x=0,y=0,z=math.huge}}))
    runtime.final(ctx);assert(b.released==234)
    for _,listeners in pairs(ctx.events.listeners) do assert(#listeners==0) end
end)
test("audio variation cannot advance weapon or world random streams",function()
    local a,backend_a=context();local b=context()
    for _=1,6 do emit(a,events.WEAPON_FIRE,{weapon="rifle"});present(a);backend_a:finish_all() end
    for _=1,20 do
        near(a.weapons.random(),b.weapons.random())
        near(a.world.decoration_rng(),b.world.decoration_rng())
        near(a.world.spawn_rng(),b.world.spawn_rng())
    end
    runtime.final(a);runtime.final(b)
end)
test("continuous filtering changes an active sound without restarting its waveform",function()
    local ctx,b=context()
    emit(ctx,events.WEAPON_FIRE,{weapon="rifle",source="enemy_1",position={x=5,y=1.66,z=0}});present(ctx)
    local v=ctx.audio.voices[5];local serial=v.serial;local initial=v.dark
    b.blocked=true
    for _=1,20 do audio.update(ctx,.02);present(ctx) end
    assert(v.occlusion>.95 and v.dark>initial+.5 and v.serial==serial)
    b.blocked=false
    for _=1,20 do audio.update(ctx,.02);present(ctx) end
    assert(v.occlusion<.05 and v.serial==serial and ctx.audio.last_probes<=4)
    runtime.final(ctx)
end)
test("only travelled hostile near passes sound once per projectile, with wall rejection",function()
    local ctx,b=context();present(ctx)
    local round={};local cue={source="enemy_1",round=round,from={x=1,y=1.66,z=-4},to={x=1,y=1.66,z=4},speed=500}
    emit(ctx,events.BULLET_SEGMENT,cue);emit(ctx,events.BULLET_SEGMENT,cue);present(ctx)
    assert(ctx.audio.by_kind.near_miss==1 and ctx.audio.last.key=="crack")
    cue.round={};b.blocked=true;emit(ctx,events.BULLET_SEGMENT,cue);present(ctx)
    assert(ctx.audio.by_kind.near_miss==1)
    b.blocked=false;cue.source="player";emit(ctx,events.BULLET_SEGMENT,cue);present(ctx)
    assert(ctx.audio.by_kind.near_miss==1)
    cue.source="enemy_1";cue.round={};cue.from.z=-8;cue.to.z=-4
    emit(ctx,events.BULLET_SEGMENT,cue);present(ctx);assert(ctx.audio.by_kind.near_miss==1)
    runtime.final(ctx)
end)
test("casings sound on contacts, with resting-contact and multi-point rejection",function()
    local contact=require "game.audio.contacts"
    local item={spec={mass=.008},kind="casing"}
    local n={x=0,y=1,z=0}
    assert(not contact.accept(item,1,{x=0,y=-.17,z=0},n,.0014))
    assert(contact.accept(item,1,{x=0,y=-3,z=0},n,.024))
    assert(not contact.accept(item,1,{x=0,y=-3,z=0},n,.024))
    local ctx,b=context()
    emit(ctx,events.WEAPON_SHELL,{position={x=0,y=1,z=0}});present(ctx)
    assert(not ctx.audio.by_kind.shell)
    emit(ctx,events.PHYSICS_CONTACT,{kind="casing",position={x=1,y=0,z=0},speed=2});present(ctx)
    assert(ctx.audio.by_kind.shell==1)
    runtime.final(ctx)
end)
test("heartbeat, confirmations, grenade and death voices consume actual event contracts",function()
    local ctx,b=context()
    emit(ctx,events.PLAYER_HEARTBEAT,{strength=.8});present(ctx)
    assert(ctx.audio.by_kind.heartbeat==1);b:finish_all()
    emit(ctx,events.DAMAGE_DEALT,{source="player",target="fixture",amount=10,headshot=true});present(ctx)
    assert(ctx.audio.last.key=="ui/headshot");b:finish_all()
    emit(ctx,events.GRENADE_THROW,{source="enemy_1",position={x=2,y=1,z=0}});present(ctx)
    assert(ctx.audio.by_kind.grenade==1 and ctx.audio.by_kind.bark==1)
    ctx.time.frame_elapsed=1;audio.suspend(ctx,true);b:finish_all();audio.ui(ctx);present(ctx)
    assert(ctx.audio.by_kind.ui==1 and audio.snapshot(ctx).active==1)
    runtime.final(ctx)
end)
test("blast ducking/deafening recover, freeze on pause, and clear on encounter reset",function()
    local ctx,b=context();present(ctx)
    emit(ctx,events.EXPLOSION,{position={x=1,y=1,z=0},radius=8});present(ctx)
    assert(ctx.audio.deafness>.8 and ctx.audio.duck>.8 and ctx.audio.by_kind.tinnitus==1)
    local before=ctx.audio.deafness;runtime.set_paused(ctx,true)
    runtime.fixed_update(ctx,1);audio.update(ctx,1);assert(ctx.audio.deafness==before)
    runtime.set_paused(ctx,false);audio.fixed_update(ctx,1);assert(ctx.audio.deafness<before)
    audio.reset(ctx);assert(ctx.audio.deafness==0 and ctx.audio.duck==0 and not ctx.audio.volley)
    runtime.final(ctx)
end)
test("soldier stride/transition audio and distant battles use independent bounded schedules",function()
    local ctx,b=context();present(ctx)
    local e={id="enemy_1",actor={alive=true},position={x=2,y=0,z=-2},travel=0,visible=false,
        motion={grounded=true,stance="stand",surface="wood"},state="patrol"}
    ctx.ai.actors[e.id]=e;ctx.ai.order={e.id}
    audio.fixed_update(ctx,.01);e.travel=2;e.visible=true;audio.fixed_update(ctx,.01);present(ctx)
    assert(ctx.audio.by_kind.soldier_step==1 and ctx.audio.by_kind.bark==1)
    b:finish_all();audio.fixed_update(ctx,.01);present(ctx)
    assert(ctx.audio.by_kind.soldier_step==1 and ctx.audio.by_kind.bark==1)
    local shots=ctx.weapons.sim.fired
    ctx.audio.battle_due=0;audio.fixed_update(ctx,.01);present(ctx)
    assert(ctx.audio.by_kind.battle==1 and ctx.weapons.sim.fired==shots)
    audio.reset(ctx);assert(ctx.audio.scene_clock==0)
    runtime.final(ctx)
end)
print(count.." audio tests passed")
