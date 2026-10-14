package.path="./?.lua;"..package.path
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local tactics=require "game.ai.tactics"
local combat=require "game.combat"
local events=require "game.events"
local generator=require "game.world.generator"
local nav=require "game.ai.navigation"
local ballistics=require "game.weapons.ballistics"
local trace=require "game.weapons.trace"
local h,count=1/120,0
local function test(name,run) run();count=count+1;print("PASS "..name) end
local function flat()
    local q={blocked=true}
    function q:sync() end
    function q:contacts(p) return p.y<0 and {{distance=p.y,nx=0,ny=1,nz=0}} or {} end
    function q:fits(p) return p.y>=-.0001 end
    function q:ray() end
    function q:camera_fraction() return 1 end
    function q:sweep(p,_,dx,dy)
        if dy<0 and p.y+dy<=0 then return {fraction=-p.y/dy,nx=0,ny=1,nz=0,surface="concrete"} end
    end
    function q:visible() return not self.blocked end
    function q:walkable() return true end
    return q
end
local function context()
    local ctx=runtime.new()
    while ctx.world.phase=="geometry" do generator.step(ctx.world,100) end
    ctx.world.ready=true;ai.reset(ctx)
    for _,id in ipairs(ctx.ai.order) do ctx.ai.actors[id].query=flat() end
    return ctx
end
local function ticks(ctx,n) for _=1,n do runtime.fixed_update(ctx,h) end end

test("layout spawns two deterministic squads with distinct health, motion and random streams",function()
    local ctx=context()
    assert(#ctx.ai.order==6 and #ctx.world.spawn_points==7)
    for _,squad in pairs(ctx.ai.squads) do assert(#squad.members==3) end
    local values={}
    for i,id in ipairs(ctx.ai.order) do
        local e=ctx.ai.actors[id]
        assert(id=="enemy_"..i and e.actor==ctx.combat.actors[id])
        values[i]=e.random()
        if i>1 then assert(values[i]~=values[i-1] and e.motion~=ctx.ai.actors.enemy_1.motion) end
    end
    ai.reset(ctx)
    for i,id in ipairs(ctx.ai.order) do assert(ctx.ai.actors[id].random()==values[i]) end
    runtime.final(ctx)
end)

test("reports stay within the squad, preserve last-seen position, expire without echo and freeze on pause",function()
    local ctx=context()
    ctx.player.position.x=3;ctx.player.position.z=4
    combat.request(ctx.combat,{target="enemy_1",amount=1,source="player"});ticks(ctx,1)
    for i=1,3 do assert(ctx.ai.actors["enemy_"..i].memory>7.9) end
    for i=4,6 do assert(ctx.ai.actors["enemy_"..i].memory==0) end
    ctx.player.position.x=100
    ticks(ctx,120)
    local e=ctx.ai.actors.enemy_2
    assert(e.last_seen.x==3 and e.last_seen.z==4)
    local memory=e.memory
    runtime.set_paused(ctx,true);ticks(ctx,500);assert(e.memory==memory)
    runtime.set_paused(ctx,false);ticks(ctx,1000)
    for i=1,3 do assert(ctx.ai.actors["enemy_"..i].memory==0 and ctx.ai.actors["enemy_"..i].state=="patrol") end
    runtime.final(ctx)
end)

test("only supported, protected and reachable cover is claimed, exclusively across squads",function()
    local ctx=context()
    local a,b=ctx.ai.actors.enemy_1,ctx.ai.actors.enemy_4
    a.last_seen={x=4,y=0,z=-3};b.last_seen=a.last_seen
    a.position={x=0,y=0,z=-4};b.position={x=0,y=0,z=-5}
    ctx.world.cover={
        {id="blocked",x=1,y=0,z=-4,height=1,normal_x=-1,normal_z=0},
        {id="open",x=0,y=0,z=-3,height=1,normal_x=-1,normal_z=0},
        {id="safe",x=0,y=0,z=-5,height=1,normal_x=-1,normal_z=0},
        {id="safe2",x=0,y=0,z=-6,height=1,normal_x=-1,normal_z=0},
    }
    ctx.world.navigation={nodes={},edges={}}
    local q={visible=function(_,from) return from.y>1 or from.z==-3 end,walkable=function(_,from,to) return to.x~=1 end}
    assert(tactics.cover(ctx,a,q).id=="safe")
    assert(tactics.cover(ctx,b,q).id=="safe2")
    assert(ctx.ai.cover_claims.safe==a.id and ctx.ai.cover_claims.safe2==b.id)
    combat.request(ctx.combat,{target=a.id,amount=999,source="player"});combat.fixed_update(ctx)
    assert(ctx.ai.cover_claims.safe==nil and not a.cover)
    tactics.release_cover(ctx.ai,b)
    b.cover_retry=0
    assert(tactics.cover(ctx,b,q).id=="safe")
    runtime.final(ctx)
end)

test("one squad member takes every west-loop waypoint while a living ally engages",function()
    local ctx=context()
    local lead,flanker=ctx.ai.actors.enemy_1,ctx.ai.actors.enemy_3
    lead.state="fire";lead.visible=true
    tactics.alert(ctx,lead,{x=0,y=0,z=8})
    assert(tactics.flank(ctx,ctx.ai.actors.enemy_2)==nil)
    local goal=assert(tactics.flank(ctx,flanker))
    local claim=flanker.flank.id
    assert(ctx.ai.flank_claims[claim]==flanker.id and goal.z==-10)
    local saw_rear=false
    for _=1,20 do
        if not goal then break end
        saw_rear=saw_rear or goal.x< -23
        flanker.position={x=goal.x,y=goal.y,z=goal.z}
        goal=tactics.flank(ctx,flanker)
    end
    assert(saw_rear and flanker.flanks_completed==1 and not flanker.flank and not ctx.ai.flank_claims[claim])
    assert(flanker.position.z==7.5 and flanker.position.x==0)
    assert(not tactics.flank(ctx,flanker),"cooldown prevents repeatedly circling the map")
    runtime.final(ctx)
end)

test("death releases flank ownership and a surviving member can take over",function()
    local ctx=context()
    local lead,flanker=ctx.ai.actors.enemy_1,ctx.ai.actors.enemy_3
    lead.state="fire";lead.visible=true;tactics.alert(ctx,lead,{x=0,y=0,z=8})
    assert(tactics.flank(ctx,flanker))
    combat.request(ctx.combat,{target=flanker.id,amount=999});combat.fixed_update(ctx)
    assert(next(ctx.ai.flank_claims)==nil)
    assert(tactics.flank(ctx,ctx.ai.actors.enemy_2))
    combat.request(ctx.combat,{target="player",amount=999});combat.fixed_update(ctx)
    assert(next(ctx.ai.flank_claims)==nil and next(ctx.ai.cover_claims)==nil)
    runtime.final(ctx)
end)

test("an unreachable flank approach releases its claim and waits before retrying",function()
    local ctx=context()
    local lead,flanker=ctx.ai.actors.enemy_1,ctx.ai.actors.enemy_3
    lead.state="fire";lead.visible=true;tactics.alert(ctx,lead,{x=0,y=0,z=8})
    assert(tactics.flank(ctx,flanker))
    function flanker.query:walkable() return false end
    flanker.think=0
    ticks(ctx,1)
    assert(not flanker.flank and next(ctx.ai.flank_claims)==nil and flanker.flank_retry>flanker.age)
    local replans=flanker.replans
    ticks(ctx,60)
    assert(flanker.replans<=replans+1,"Unreachable goals must not replan every perception tick")
    runtime.final(ctx)
end)

test("friendly firing lanes and movement separation respond to live allies on the same floor",function()
    local ctx=context()
    local a,b=ctx.ai.actors.enemy_1,ctx.ai.actors.enemy_2
    a.position={x=0,y=0,z=0};b.position={x=0,y=0,z=-.65}
    assert(not tactics.clear_shot(ctx.ai,a,{x=0,y=1.5,z=0},{x=0,y=1.3,z=-10}))
    local x,z=tactics.steer(ctx.ai,a,0,-2)
    assert(math.abs(x)>.01 and z> -2)
    b.position.y=3.2
    assert(tactics.clear_shot(ctx.ai,a,{x=0,y=1.5,z=0},{x=0,y=1.3,z=-10}))
    x,z=tactics.steer(ctx.ai,a,0,-2);assert(x==0 and z== -2)
    runtime.final(ctx)
end)

test("a penetrating round damages each of two enemies once despite overlapping hit volumes",function()
    local ctx=context();ctx.ai.enabled=false
    local shapes={}
    for i=1,2 do
        for j=1,2 do shapes[#shapes+1]={id=i.."/"..j,actor="enemy_"..i,surface="flesh",x=0,y=1,z=-i*.25,w=.3,h=.4,d=.03} end
    end
    local hits={}
    events.on(ctx.events,events.DAMAGE_DEALT,hits,function(_,hit) hits[hit.target]=(hits[hit.target] or 0)+1 end)
    local sim=ballistics.new()
    ballistics.spawn(sim,{id="test",damage=20,muzzleVelocity=500,penetration=4,dropoff=1,maxRange=100,dragK=0},
        {x=0,y=1,z=0},{x=0,y=0,z=-1},"player")
    ballistics.update(ctx,sim,h,trace.boxes(shapes));combat.fixed_update(ctx)
    assert(hits.enemy_1==1 and hits.enemy_2==1)
    assert(ctx.ai.actors.enemy_1.actor.health<100 and ctx.ai.actors.enemy_2.actor.health<100)
    assert(ctx.ai.actors.enemy_3.actor.health==100)
    runtime.final(ctx)
end)

test("repeated encounter resets discard pending old hits, rounds, reports and claims",function()
    local ctx=context()
    for _=1,10 do
        tactics.alert(ctx,ctx.ai.actors.enemy_1,{x=0,y=0,z=8})
        ctx.ai.cover_claims.test="enemy_1";ctx.ai.flank_claims.test="enemy_3"
        for _,id in ipairs(ctx.ai.order) do combat.request(ctx.combat,{target=id,amount=999}) end
        ai.reset(ctx);combat.fixed_update(ctx)
        assert(#ctx.ai.order==6 and next(ctx.ai.cover_claims)==nil and next(ctx.ai.flank_claims)==nil)
        assert(ctx.ai.sim.fired==0 and #ctx.ai.sim.live==0 and not ctx.ai.squads.alpha.last_seen)
        for _,id in ipairs(ctx.ai.order) do assert(ctx.ai.actors[id].actor.health==100) end
    end
    runtime.final(ctx)
    assert(next(ctx.combat.actors)==nil and next(ctx.events.listeners)==nil)
end)

test("static edge cache leaves endpoint probes fresh and invalidates with the graph",function()
    local graph={nodes={{id="a",x=0,y=0,z=0},{id="b",x=0,y=0,z=-2}},edges={{from="a",to="b"}}}
    local calls=0
    local q={walkable=function(_,a,b) calls=calls+1;return a.x==b.x or a.z==b.z end}
    local cache={}
    local from,to={x=2,y=0,z=0},{x=2,y=0,z=-2}
    -- Block the direct path only; route via the graph remains supported.
    function q:walkable(a,b) calls=calls+1;return (a.x==0 and b.x==0) or a.z==b.z end
    assert(nav.route(graph,from,to,q,cache));local first=calls
    calls=0;assert(nav.route(graph,from,to,q,cache));assert(calls==first-1)
    graph={nodes=graph.nodes,edges={}};assert(not nav.route(graph,from,to,q,cache))
end)

test("six-actor simulation is deterministic across 30, 60 and 144 presentation FPS",function()
    local expected
    for _,fps in ipairs({30,60,144}) do
        local ctx=context();local accumulator=0
        for _,id in ipairs(ctx.ai.order) do ctx.ai.actors[id].query.blocked=false end
        for _=1,fps*3 do
            accumulator=accumulator+1/fps
            while accumulator+1e-10>=h do runtime.fixed_update(ctx,h);accumulator=accumulator-h end
            runtime.update(ctx,1/fps)
        end
        local result={}
        for _,id in ipairs(ctx.ai.order) do
            local e=ctx.ai.actors[id]
            for _,v in ipairs({e.position.x,e.position.z,e.phase,e.shots}) do result[#result+1]=v end
        end
        if expected then for i,v in ipairs(expected) do assert(math.abs(v-result[i])<1e-7) end else expected=result end
        runtime.final(ctx)
    end
end)
print(count.." squad tests passed")
