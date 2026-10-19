package.path="./?.lua;"..package.path
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local perception=require "game.ai.perception"
local guns=require "game.ai.weapons"
local tactics=require "game.ai.tactics"
local events=require "game.events"
local combat=require "game.combat"
local V=require "game.weapons.math"
local h,count=1/120,0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function near(a,b) assert(math.abs(a-b)<1e-7,a.." != "..b) end
local function flat()
    local q={blocked=true}
    function q:sync() end
    function q:contacts(p) return p.y<0 and {{distance=p.y,nx=0,ny=1,nz=0}} or {} end
    function q:fits(p) return p.y>=-.0001 end
    function q:ray(p,dx,dy,dz) if dy<0 and p.y+dy<=0 then return {x=p.x,y=0,z=p.z,nx=0,ny=1,nz=0} end end
    function q:camera_fraction() return 1 end
    function q:sweep(p,_,dx,dy) if dy<0 and p.y+dy<=0 then return {fraction=-p.y/dy,nx=0,ny=1,nz=0} end end
    function q:visible() return not self.blocked end
    function q:walkable() return true end
    return q
end
local function context()
    local ctx=runtime.new();ctx.world.ready=true
    local e=ai.reset(ctx,{x=0,y=.004,z=0},0);e.query=flat()
    ctx.player.position.x=100;ctx.player.position.z=100
    ctx.ai.damage_scale=0
    ctx.world.navigation={nodes={},edges={}};ctx.world.cover={}
    e.patrol_points={V.copy(e.position),V.copy(e.position)}
    return ctx,e
end
local function ticks(ctx,n)
    for _=1,n do runtime.fixed_update(ctx,h);if ctx.time.tick%2==0 then runtime.update(ctx,h*2) end end
end

test("shots, steps and explosions record event positions without granting target knowledge",function()
    for _,kind in ipairs({"shot","step","run","explosion"}) do
        local ctx,e=context();local p={x=0,y=1,z=-3}
        perception.hear(ctx,{position=p},kind);p.z=-90
        assert(e.heard and e.heard.position.z==-3 and not e.target_point and e.memory==0)
        ticks(ctx,120);assert(e.shots==0 and e.investigations>0 and e.position.z<-.1)
        runtime.final(ctx)
    end
end)

test("hearing attenuation, friendly events, death, pause and capture cannot disclose targets",function()
    local ctx,e=context()
    perception.hear(ctx,{position={x=0,y=1,z=-8}},"step");assert(not e.heard)
    e.query.blocked=false
    perception.hear(ctx,{position={x=0,y=1,z=-8},source="enemy_2"},"shot");assert(not e.heard)
    for _,flag in ipairs({"paused","capture_active"}) do
        ctx[flag]=true;perception.hear(ctx,{position={x=0,y=1,z=-2}},"shot");assert(not e.heard);ctx[flag]=false
    end
    perception.hear(ctx,{position={x=0,y=1,z=-8}},"step");assert(e.heard)
    combat.request(ctx.combat,{target=e.id,amount=999});combat.fixed_update(ctx)
    local n=e.heard_count;perception.hear(ctx,{position={x=0,y=1,z=-2}},"shot");assert(e.heard_count==n)
    runtime.final(ctx)
end)

test("damage without an origin is not omniscient; recorded origin remains historical",function()
    local ctx,e=context()
    combat.request(ctx.combat,{target=e.id,amount=1,source="player"});ticks(ctx,1)
    assert(not e.heard and e.memory==0)
    combat.request(ctx.combat,{target=e.id,amount=1,source="player",from={x=0,y=1.5,z=-4}});ticks(ctx,1)
    assert(e.heard.position.z==-4 and e.memory==0 and not e.target_point)
    runtime.final(ctx)
end)

test("investigation reaches evidence, searches, and expires without following hidden movement",function()
    local ctx,e=context()
    events.emit(ctx.events,events.WEAPON_FIRE,{origin={x=0,y=1.3,z=-2},weapon="rifle"})
    ticks(ctx,900)
    assert(e.searches==1 and not e.heard and e.memory==0 and e.shots==0)
    assert(e.state=="patrol" and e.position.x<1)
    runtime.final(ctx)
end)

test("suppression targets only recent visual evidence and cannot extend by hearing",function()
    local ctx,e=context();tactics.alert(ctx,e,{x=0,y=0,z=-8})
    local p=assert(perception.target(e));ctx.player.position.z=40
    near(p.z,-8);ticks(ctx,100);assert(perception.target(e))
    ticks(ctx,180);assert(not perception.target(e) and e.last_seen.z==-8)
    perception.hear(ctx,{position={x=0,y=0,z=-3}},"shot");assert(not perception.target(e))
    runtime.final(ctx)
end)

test("each variant empties a finite magazine, reloads on its clip and emits actor-local beats",function()
    for _,variant in ipairs({"vanguard","irregular","breacher"}) do
        local ctx,e=context();e.variant=variant;guns.init(e);local p=guns.profile(e)
        local beats={};events.on(ctx.events,events.WEAPON_RELOAD,beats,function(_,v) beats[#beats+1]=v end)
        for i=1,p.magazine do guns.consume(e,false) end
        assert(e.ammo==0);guns.tick(ctx,e,h,e.position)
        assert(e.reload_left==p.reload and e.ammo==0 and e.animation.reload_time==0)
        for _=1,math.floor(p.reload/h)-1 do guns.tick(ctx,e,h,e.position) end
        assert(e.ammo==0)
        for _=1,3 do guns.tick(ctx,e,h,e.position) end
        assert(e.ammo==30 and e.reloads==1 and e.reload_beats==3)
        assert(#beats==5 and beats[1].phase=="start" and beats[2].phase=="magdrop" and beats[5].phase=="end")
        for _,beat in ipairs(beats) do assert(beat.source==e.id and beat.position.z==e.position.z) end
        runtime.final(ctx)
    end
end)

test("reload freezes on pause, cancels on death, and reset clears ammo and timers",function()
    local ctx,e=context();e.ammo=0;ticks(ctx,4);local left=e.reload_left
    runtime.set_paused(ctx,true);ticks(ctx,400);near(e.reload_left,left)
    runtime.set_paused(ctx,false);combat.request(ctx.combat,{target=e.id,amount=999});ticks(ctx,1)
    assert(e.reload_left==0 and e.ammo==0 and e.animation.reload_time==-1)
    local fresh=ai.reset(ctx,{x=0,y=.004,z=0},0)
    assert(fresh.ammo==30 and fresh.reloads==0 and fresh.burst_left==0)
    runtime.final(ctx)
end)

test("bursts enforce cyclic intervals and pauses; pressure increases angular error",function()
    local ctx,e=context();e.cooldown=0;e.burst_cooldown=0
    assert(guns.ready(e));guns.consume(e,false);assert(not guns.ready(e))
    while e.burst_left>0 do e.cooldown=0;guns.consume(e,false) end
    e.cooldown=0;assert(e.burst_cooldown>=.45 and not guns.ready(e))
    local saved=e.random;e.random=function() return .5 end
    local a=guns.direction(e,{x=0,y=1,z=0},{x=0,y=1,z=-10},false)
    e.suppression=.8
    local b=guns.direction(e,{x=0,y=1,z=0},{x=0,y=1,z=-10},false)
    assert(math.abs(b.x)>math.abs(a.x)*2)
    near(V.length(b),1);e.random=saved;runtime.final(ctx)
end)

test("tall cover requires a walkable side and a clear muzzle-height firing lane",function()
    local cover={id="wall",x=0,y=0,z=0,height=2,normal_x=0,normal_z=1,half_width=1}
    local q={visible=function(_,a) return math.abs(a.x)>1.5 end,walkable=function() return true end,fits=function() return true end}
    local p=assert(tactics.peek(q,cover,{x=0,y=0,z=-10}));assert(math.abs(p.x)==1.65)
    q.walkable=function() return false end;assert(not tactics.peek(q,cover,{x=0,y=0,z=-10}))
    q.walkable=function() return true end;q.visible=function() return false end
    assert(not tactics.peek(q,cover,{x=0,y=0,z=-10}))
end)

test("squad peek permission is exclusive, rotates fairly and releases on suppression/death",function()
    local ctx,e=context();local squad={members={}};ctx.ai.squads.alpha=squad
    for i=1,3 do
        local a=i==1 and e or {}
        if i>1 then for k,v in pairs(e) do a[k]=v end end
        a.id="enemy_"..i;a.index=i;a.squad="alpha";a.age=1;a.memory=8
        a.cover={id="c"..i,x=0,y=.004,z=0,height=1};a.cover_peek=V.copy(a.cover);a.cover_phase="hide";a.peek_timer=0
        ctx.ai.actors[a.id]=a;squad.members[i]=a.id
    end
    for i=1,3 do tactics.posture(ctx.ai.actors[squad.members[i]],h,ctx.ai) end
    assert(squad.peek_owner==e.id)
    e.suppressed=true;tactics.posture(e,h,ctx.ai);assert(not squad.peek_owner)
    local second=ctx.ai.actors.enemy_2;tactics.posture(second,h,ctx.ai);assert(squad.peek_owner==second.id)
    tactics.release(ctx.ai,second);assert(not squad.peek_owner)
    runtime.final(ctx)
end)

test("wounded retreat selects reachable protection farther from known threat and releases claims",function()
    local ctx,e=context();tactics.alert(ctx,e,{x=0,y=0,z=-6})
    ctx.world.navigation.nodes={{id="rear",x=0,y=.004,z=5},{id="front",x=0,y=.004,z=-4}}
    local goal=assert(tactics.reposition(ctx,e,e.query,nil,true))
    assert(goal.z==5 and e.retreats==1 and ctx.ai.position_claims[goal.id]==e.id)
    tactics.release(ctx.ai,e);assert(not next(ctx.ai.position_claims))
    e.reposition_retry=0;e.query.walkable=function() return false end
    assert(not tactics.reposition(ctx,e,e.query,nil,true) and not next(ctx.ai.position_claims))
    runtime.final(ctx)
end)

test("blocked and friendly firing lanes remain safe with recent-last-known-position fire",function()
    local ctx,e=context();e.query.blocked=false;ctx.player.position.x=0;ctx.player.position.z=-8
    ticks(ctx,200);assert(e.shots>0)
    local shots=e.shots;e.query.blocked=true;ticks(ctx,240);assert(e.shots==shots)
    e.query.blocked=false
    ctx.ai.actors.friend={id="friend",actor={alive=true},position={x=0,y=0,z=-4}}
    ctx.ai.order[2]="friend"
    assert(not tactics.clear_shot(ctx.ai,e,{x=0,y=1.4,z=0},{x=0,y=1.3,z=-8}))
    ctx.ai.order[2]=nil;ctx.ai.actors.friend=nil;runtime.final(ctx)
end)
test("live magazine cycles and perception agree at 30/60/144 presentation FPS",function()
    local expected
    for _,fps in ipairs({30,60,144}) do
        local ctx,e=context();ctx.player.position.x=0;ctx.player.position.z=-9;e.query.blocked=false
        local accumulated=0
        for _=1,fps*15 do
            accumulated=accumulated+1/fps
            while accumulated+1e-10>=h do runtime.fixed_update(ctx,h);accumulated=accumulated-h end
            runtime.update(ctx,1/fps)
        end
        assert(e.reloads>=1 and e.shots>30,"Live clip boundary lost its refill")
        local result={e.shots,e.ammo,e.reloads,e.reload_left,e.burst_left,e.burst_cooldown,e.contact_age}
        if expected then for i,v in ipairs(expected) do near(v,result[i]) end else expected=result end
        runtime.final(ctx)
    end
end)

test("flanks work outside the central street and fall back to reachable lateral nodes",function()
    for _,lane in ipairs({true,false}) do
        local ctx,e=context();e.squad="alpha";e.id="enemy_1"
        local lead={id="lead",actor={alive=true,health=100},state="fire",visible=true,position={x=23,y=0,z=0}}
        ctx.ai.actors.lead=lead;ctx.ai.squads.alpha={members={"lead",e.id}}
        e.position.x=23;e.position.z=0;tactics.alert(ctx,e,{x=23,y=0,z=-12})
        ctx.world.navigation={nodes={{id="side",x=28,y=0,z=-3}},edges={},flanks=lane and {
            {id="eastern",points={{x=23,y=0,z=0},{x=29,y=0,z=-6},{x=23,y=0,z=-10}}}
        } or {}}
        local goal=assert(tactics.flank(ctx,e,e.query));assert(e.flank and ctx.ai.flank_claims[e.flank.id]==e.id)
        if lane then assert(e.flank.id=="eastern") else assert(goal.x==28 and e.flank.id=="position/side") end
        tactics.release(ctx.ai,e);assert(not next(ctx.ai.flank_claims) and not next(ctx.ai.position_claims))
        ctx.ai.actors.lead=nil;runtime.final(ctx)
    end
end)

test("a yielded reposition cannot steal a node acquired by another squad flanker",function()
    local ctx,e=context();tactics.alert(ctx,e,{x=0,y=0,z=-8})
    ctx.world.navigation={nodes={{id="side",x=5,y=.004,z=-2}},edges={}}
    local other={};for k,v in pairs(e) do other[k]=v end;other.id="other"
    local function job(actor) return coroutine.create(function()
        tactics.reposition(ctx,actor,e.query,{checkpoint=coroutine.yield},false)
    end) end
    local first,second=job(e),job(other)
    assert(coroutine.resume(first));assert(coroutine.resume(second))
    assert(coroutine.resume(first));assert(e.reposition)
    local id=e.reposition.id;ctx.ai.position_claims[id]=nil;ctx.ai.flank_claims[id]=e.id;e.reposition=nil
    assert(coroutine.resume(second));assert(not other.reposition and ctx.ai.flank_claims[id]==e.id)
    runtime.final(ctx)
end)

test("contact expiry cancels suspended tactical jobs before they can renew claims",function()
    local ctx,e=context();tactics.alert(ctx,e,{x=0,y=0,z=-8});e.memory=h*.5
    e.cover={id="old"};ctx.ai.cover_claims.old=e.id
    e.flank={id="lane"};ctx.ai.flank_claims.lane=e.id
    e.reposition={id="side"};ctx.ai.position_claims.side=e.id
    local job=require("game.ai.planner").add(ctx.ai.planner,e,function() ctx.ai.cover_claims.stale=e.id end)
    e.nav_job=job;ctx.ai.planner.seconds=0;ticks(ctx,1)
    assert(e.nav_job~=job and not e.cover and not e.flank and not e.reposition)
    assert(not next(ctx.ai.cover_claims) and not next(ctx.ai.flank_claims) and not next(ctx.ai.position_claims))
    ctx.ai.planner.seconds=1;ticks(ctx,10);assert(not ctx.ai.cover_claims.stale)
    runtime.final(ctx)
end)

print(count.." AI tactics tests passed")
