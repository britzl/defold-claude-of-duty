package.path="./?.lua;"..package.path
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local suppression=require "game.ai.suppression"
local tactics=require "game.ai.tactics"
local ballistics=require "game.weapons.ballistics"
local trace=require "game.weapons.trace"
local events=require "game.events"
local combat=require "game.combat"
local rig=require "game.ai.rig"
local geo=require "game.ai.geometry"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local h,count=1/120,0
local function test(name,run) run();count=count+1;print("PASS "..name) end
local function near(a,b,t) assert(math.abs(a-b)<(t or 1e-7),a.." != "..b) end
local function ticks(ctx,n) for _=1,n do runtime.fixed_update(ctx,h) end end
local function context(cover)
    local ctx=runtime.new();ctx.world.ready=true
    local e=ai.reset(ctx,{x=0,y=.004,z=0},math.pi)
    ctx.player.position.x=0;ctx.player.position.z=6
    local solids=cover and {{id="wall",surface="concrete",x=0,y=.525,z=.6,w=4,h=1.05,d=.2}} or {}
    local query={solids=solids}
    function query:sync() end
    function query:contacts(p) return p.y<0 and {{distance=p.y,nx=0,ny=1,nz=0}} or {} end
    function query:fits(p,height) return p.y>=-.0001 and not (self.ceiling and height>1.12) end
    function query:ray() end
    function query:camera_fraction() return 1 end
    function query:sweep(p,_,dx,dy)
        if dy<0 and p.y+dy<=0 then return {fraction=-p.y/dy,nx=0,ny=1,nz=0,surface="concrete"} end
    end
    function query:visible(a,b)
        local delta={x=b.x-a.x,y=b.y-a.y,z=b.z-a.z}
        return #trace.boxes(self.solids):segment(a,V.normalize(delta),V.length(delta))==0
    end
    function query:walkable() return true end
    e.query=query
    ctx.world.cover=cover and {{id="wall",x=0,y=0,z=0,height=1.05,normal_x=0,normal_z=-1}} or {}
    e.squad="alpha";ctx.ai.squads.alpha={members={e.id}}
    tactics.alert(ctx,e,ctx.player.position)
    return ctx,e
end
local definition={id="pressure_test",damage=1,muzzleVelocity=600,penetration=.1,dropoff=1,maxRange=6,dragK=0}
local function pass(ctx,e,source,solids)
    local eye=suppression.eye(e)
    local sim=ballistics.new()
    ballistics.spawn(sim,definition,{x=eye.x-2,y=eye.y+.25,z=eye.z},{x=1,y=0,z=0},source or "player",false)
    ballistics.update(ctx,sim,h,trace.boxes(solids or {}))
    return sim
end

test("non-tracer near misses follow the travelled segment and stop at concrete",function()
    local ctx,e=context()
    local wall={id="stop",surface="concrete",x=-3,y=1.5,z=0,w=.3,h=4,d=4}
    e.query.solids={wall}
    local sim=ballistics.new()
    ballistics.spawn(sim,definition,{x=-5,y=1.7,z=0},{x=1,y=0,z=0},"player",false)
    ballistics.update(ctx,sim,h,trace.boxes({wall}))
    assert(#sim.live==0 and e.suppression==0,"Pressure must not extend past the stopping wall")
    e.query.solids={};pass(ctx,e)
    assert(e.suppression>.5 and e.suppression_events==1 and e.actor.health==100)
    assert(e.last_seen.z==6,"A near miss must not disclose a new player position")
    runtime.final(ctx)
end)

test("one round contributes at most its strongest pass or impact, regardless of segment count",function()
    local ctx,e=context();local token={}
    local eye=suppression.eye(e)
    local event={from={x=-2,y=eye.y,z=eye.z},to={x=2,y=eye.y,z=eye.z},source="player",round=token}
    for _=1,30 do events.emit(ctx.events,events.BULLET_SEGMENT,event) end
    near(e.suppression,.7);assert(e.suppression_events==1)
    events.emit(ctx.events,events.BULLET_IMPACT,{point=eye,source="player",round=token})
    events.emit(ctx.events,events.BULLET_IMPACT,{point=eye,source="player",round=token,exit=true})
    near(e.suppression,.7)
    ticks(ctx,60)
    local before=e.suppression;events.emit(ctx.events,events.BULLET_SEGMENT,event)
    near(e.suppression,before)
    runtime.final(ctx)
end)

test("near impacts behind cover add bounded pressure; distant, friendly and dead actors do not",function()
    local ctx,e=context(true)
    for _=1,5 do
        events.emit(ctx.events,events.BULLET_IMPACT,{point={x=0,y=.8,z=.71},normal={x=0,y=0,z=1},source="player",round={}})
    end
    assert(e.suppression>.9 and e.suppression<=1.6 and e.suppressed)
    local before=e.suppression
    pass(ctx,e,"enemy_2")
    events.emit(ctx.events,events.BULLET_IMPACT,{point={x=0,y=8,z=0},source="player",round={}})
    near(e.suppression,before)
    combat.request(ctx.combat,{target=e.id,amount=999});combat.fixed_update(ctx)
    pass(ctx,e);near(e.suppression,before)
    runtime.final(ctx)
end)

test("suppression interrupts firing, freezes on pause, then recovers without permanent hiding",function()
    local ctx,e=context();ticks(ctx,180);assert(e.shots>0)
    for _=1,3 do pass(ctx,e) end
    assert(e.suppressed)
    local shots=e.shots;ticks(ctx,30)
    assert(e.crouch==1 and e.motion.stance=="crouch" and e.shots==shots)
    local score=e.suppression
    runtime.set_paused(ctx,true);ticks(ctx,500);pass(ctx,e);near(e.suppression,score)
    runtime.set_paused(ctx,false);ticks(ctx,500)
    assert(not e.suppressed and e.suppression==0 and e.crouch==0 and e.shots>shots)
    runtime.final(ctx)
end)

test("cover alternates protected crouches and visible shots, preserves claims while hidden",function()
    local ctx,e=context(true)
    local hidden,exposed=false,false
    for _=1,900 do
        local shots=e.shots;ticks(ctx,1)
        if e.cover_phase=="hide" then
            assert(e.shots==shots and ctx.ai.cover_claims.wall==e.id)
            if e.crouch==1 then hidden=true;assert(not e.query:visible(suppression.eye(e),{x=0,y=1.28,z=6})) end
        end
        if e.shots>shots then
            exposed=true;assert(e.cover_phase=="peek" and e.crouch<=.08 and e.motion.stance=="stand")
        end
    end
    assert(hidden and exposed and e.peeks>=2)
    for _=1,3 do pass(ctx,e) end
    local shots=e.shots;ticks(ctx,45)
    assert(e.suppressed and e.cover_phase=="hide" and e.shots==shots and e.cover.id=="wall")
    ticks(ctx,600);assert(e.shots>shots and not e.suppressed)
    -- Outdated cover cannot keep a claim after contact memory expires.
    ctx.player.position.z=40;ticks(ctx,1100)
    assert(not e.cover and next(ctx.ai.cover_claims)==nil and e.cover_phase==nil)
    runtime.final(ctx)
end)

test("blocked standing clearance keeps the pose low and prevents muzzle fire",function()
    local ctx,e=context(true);ticks(ctx,60);assert(e.crouch==1)
    e.query.ceiling=true
    local shots=e.shots;ticks(ctx,500)
    assert(e.motion.stance=="crouch" and e.crouch==1 and e.shots==shots)
    e.query.ceiling=false;ticks(ctx,500);assert(e.shots>shots)
    runtime.final(ctx)
end)

test("crouch keeps ankles planted, lifts the rifle, aligns hit volumes and stays in mesh bounds",function()
    local b=geo.build()
    for i=0,8 do
        local crouch=i/8
        local palette,world=rig.pose({crouch=crouch})
        local boxes=rig.volumes(palette,{x=0,y=0,z=0},0,"enemy")
        near(world[rig.index.FootR][8],.088,.0001)
        near(world[rig.index.FootL][8],.088,.0001)
        near(boxes[1].y,T.point(palette[rig.index.Head],rig.hitboxes[1].center).y)
        assert(T.point(palette[rig.index.HandR],rig.muzzle).y>.15,"Rifle must stay above the floor")
        for v=1,b.vertex_count do
            local at=(v-1)*3;local p={x=b.positions[at+1],y=b.positions[at+2],z=b.positions[at+3]}
            local result={x=0,y=0,z=0}
            for j=1,4 do
                local slot=(v-1)*4+j;local point=T.point(palette[b.joints[slot]+1],p)
                for _,axis in ipairs({"x","y","z"}) do result[axis]=result[axis]+point[axis]*b.weights[slot] end
            end
            for k,axis in ipairs({"x","y","z"}) do assert(result[axis]>=b.bounds[k] and result[axis]<=b.bounds[k+3]) end
            assert(result.y>-.06,"Crouch mesh sinks into the floor")
        end
    end
end)

test("death and replacement release cover and discard pressure and peek state",function()
    local ctx,e=context(true);ticks(ctx,60);pass(ctx,e);pass(ctx,e)
    assert(e.cover and e.suppressed)
    combat.request(ctx.combat,{target=e.id,amount=999});ticks(ctx,1)
    assert(not e.cover and not e.cover_phase and next(ctx.ai.cover_claims)==nil)
    local replacement=ai.reset(ctx,{x=0,y=.004,z=0},math.pi)
    assert(replacement.suppression==0 and not replacement.suppressed and replacement.peeks==0 and replacement.crouch==0)
    runtime.final(ctx)
end)

test("suppression, pose and cover timing agree at 30, 60 and 144 presentation FPS",function()
    local expected
    for _,fps in ipairs({30,60,144}) do
        local ctx,e=context(true);local accumulator=0
        for _=1,fps*6 do
            accumulator=accumulator+1/fps
            while accumulator+1e-10>=h do
                if ctx.time.tick==180 then for _=1,3 do pass(ctx,e) end end
                runtime.fixed_update(ctx,h);accumulator=accumulator-h
            end
            runtime.update(ctx,1/fps)
        end
        local actual={e.suppression,e.crouch,e.shots,e.peeks,e.suppressed_ticks,e.peek_timer}
        if expected then for i,v in ipairs(expected) do near(v,actual[i]) end else expected=actual end
        runtime.final(ctx)
    end
end)
print(count.." suppression tests passed")
