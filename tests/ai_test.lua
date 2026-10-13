-- Pure Lua geometry, skinning, navigation and fixed-tick combat regression suite.
package.path="./?.lua;"..package.path
local rig=require "game.ai.rig"
local geo=require "game.ai.geometry"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local trace=require "game.weapons.trace"
local nav=require "game.ai.navigation"
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local combat=require "game.combat"
local events=require "game.events"
local ballistics=require "game.weapons.ballistics"
local h,count=1/120,0
local function near(a,b,t) assert(math.abs(a-b)<(t or 1e-7),a.." != "..b) end
local function test(name,f) f();count=count+1;print("PASS "..name) end
local function flat()
    local q={blocked=false}
    function q:sync() end
    function q:contacts(p) return p.y<0 and {{distance=p.y,nx=0,ny=1,nz=0}} or {} end
    function q:fits(p) return p.y>=-.0001 end
    function q:ray() return nil end
    function q:camera_fraction() return 1 end
    function q:sweep(p,_,dx,dy)
        if dy<0 and p.y+dy<=0 then return {fraction=-p.y/dy,nx=0,ny=1,nz=0,surface="concrete"} end
    end
    function q:visible() return not self.blocked end
    function q:walkable() return not self.blocked end
    return q
end
local function context(position)
    local ctx=runtime.new()
    ctx.world.ready=true
    local e=ai.reset(ctx,position or {x=0,y=.004,z=-8},math.pi)
    e.query=flat()
    ctx.player.position.z=0
    ctx.services.enemy_bullets=trace.boxes({{id="player",actor="player",surface="flesh",x=0,y=.89,z=0,w=.64,h=1.78,d=.64}})
    return ctx,e
end
local function ticks(ctx,n) for _=1,n do runtime.fixed_update(ctx,h) end end

test("25 parent-ordered joints have identity bind palettes and invertible rigid transforms",function()
    assert(rig.count==25)
    local palette=rig.pose({})
    for i,b in ipairs(rig.bones) do
        assert(b.parent<i and rig.index[b.name]==i)
        for j,v in ipairs(T.identity()) do near(palette[i][j],v) end
    end
    local m=T.root({x=3,y=2,z=-7},1.2)
    m=T.mul(m,T.rotation(.5,-.8,.3))
    local p={x=-2,y=4,z=.7}
    local round=T.point(T.inverse(m),T.point(m,p))
    near(round.x,p.x);near(round.y,p.y);near(round.z,p.z)
end)

test("generated triangles face outwards, weights normalize, and all attributes are finite",function()
    local b=geo.build()
    assert(b.vertex_count<15000 and b.vertex_count>3000)
    assert(#b.positions==b.vertex_count*3 and #b.normals==#b.positions)
    assert(#b.joints==b.vertex_count*4 and #b.weights==#b.joints and #b.colors==#b.weights)
    local blended=0
    for i=1,b.vertex_count do
        local sum=0
        for j=1,4 do
            local at=(i-1)*4+j
            assert(b.joints[at]>=0 and b.joints[at]<25 and b.joints[at]%1==0)
            assert(b.weights[at]>=0 and b.weights[at]<=1)
            sum=sum+b.weights[at]
        end
        if b.weights[(i-1)*4+2]>0 then blended=blended+1 end
        near(sum,1)
    end
    assert(blended>500)
    for i=1,#b.positions,9 do
        local p=b.positions
        local ux,uy,uz=p[i+3]-p[i],p[i+4]-p[i+1],p[i+5]-p[i+2]
        local vx,vy,vz=p[i+6]-p[i],p[i+7]-p[i+1],p[i+8]-p[i+2]
        local dot=(uy*vz-uz*vy)*b.normals[i]+(uz*vx-ux*vz)*b.normals[i+1]+(ux*vy-uy*vx)*b.normals[i+2]
        assert(dot>1e-10,"inward/degenerate triangle "..i.." dot "..dot)
    end
    for _,values in ipairs({b.positions,b.normals,b.weights,b.colors}) do
        for _,v in ipairs(values) do assert(v==v and math.abs(v)<math.huge) end
    end
    print("SOLDIER",b.vertex_count,"vertices",b.bytes,"stream bytes")
end)

test("walking, aiming and collapse deform the mesh within conservative animated bounds",function()
    local b=geo.build()
    local changed=0
    for frame=0,16 do
        local palette=rig.pose({time=frame*.2,phase=frame*.4,walk=1,aim=1,pitch=.5,death=frame/16,recoil=.5})
        for i=1,b.vertex_count do
            local at=(i-1)*3
            local p={x=b.positions[at+1],y=b.positions[at+2],z=b.positions[at+3]}
            local result={x=0,y=0,z=0}
            for j=1,4 do
                local slot=(i-1)*4+j
                local point=T.point(palette[b.joints[slot]+1],p)
                for _,axis in ipairs({"x","y","z"}) do result[axis]=result[axis]+point[axis]*b.weights[slot] end
            end
            for index,axis in ipairs({"x","y","z"}) do
                assert(result[axis]>=b.bounds[index] and result[axis]<=b.bounds[index+3], "frame "..frame.." vertex "..i.." "..axis.."="..result[axis])
            end
            if V.length({x=result.x-p.x,y=result.y-p.y,z=result.z-p.z})>.01 then changed=changed+1 end
        end
    end
    assert(changed>b.vertex_count)
end)

test("rotated bone hit volumes preserve exact thickness and headshot identity",function()
    local palette=rig.pose({walk=1,phase=1.4,aim=1,pitch=.3})
    local volumes=rig.volumes(palette,{x=3,y=.1,z=-4},1.1,"enemy")
    for _,box in ipairs(volumes) do
        local origin=T.point(box.transform,{x=0,y=0,z=1})
        local direction=T.direction(box.transform,{x=0,y=0,z=-1})
        local hit=assert(trace.box(box,origin,direction,3))
        near(hit.leave-hit.enter,box.d)
        assert(hit.actor=="enemy" and hit.headshot==box.headshot)
        near(V.length(hit.normal),1)
        local inside=assert(trace.box(box,{x=box.x,y=box.y,z=box.z},direction,3))
        near(inside.enter,0);near(inside.leave,box.d/2)
    end
end)

test("tracer rotations stay finite on both forward axes and almost antiparallel rounds",function()
    for _,d in ipairs({{x=0,y=0,z=-1},{x=0,y=0,z=1},{x=1e-12,y=0,z=-1},{x=.001,y=-.002,z=-1}}) do
        local q=V.forward_rotation(d)
        near(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w,1)
        local target=V.normalize(d)
        near(2*(q.x*q.z+q.w*q.y),target.x,1e-7)
        near(2*(q.y*q.z-q.w*q.x),target.y,1e-7)
        near(1-2*(q.x*q.x+q.y*q.y),target.z,1e-7)
    end
end)

test("overlapping body volumes apply one hit per round, and heads double damage",function()
    for _,head in ipairs({false,true}) do
        local ctx,e=context();ctx.ai.enabled=false
        local shape={id="a",actor=e.id,surface="flesh",headshot=head,x=0,y=1,z=-1,w=.3,h=.4,d=.1}
        local shape2={id="b",actor=e.id,surface="flesh",x=0,y=1,z=-1.04,w=.3,h=.4,d=.1}
        local sim=ballistics.new()
        ballistics.spawn(sim,{id="test",damage=20,muzzleVelocity=500,penetration=2,dropoff=1,maxRange=100,dragK=0},
            {x=0,y=1,z=0},{x=0,y=0,z=-1},"player")
        ballistics.update(ctx,sim,h,trace.boxes({shape,shape2}))
        assert(e.actor.health==100)
        combat.fixed_update(ctx)
        near(e.actor.health,head and 60 or 80)
        runtime.final(ctx)
    end
end)

test("navigation respects blocked links, finds door routes, and rejects unreachable floors",function()
    local graph={nodes={{id="a",x=0,y=0,z=0},{id="b",x=0,y=0,z=-2},
        {id="c",x=-2,y=.145,z=-2},{id="upper",x=-2,y=3,z=-2}},
        edges={{from="a",to="b"},{from="b",to="c"}}}
    local q={walkable=function(_,a,b)
        return math.abs(a.y-b.y)<.5 and (a.x==b.x or (a.z==-2 and b.z==-2))
    end}
    local route=assert(nav.route(graph,{x=0,y=0,z=2},{x=-2,y=.145,z=0},q))
    assert(#route>=3)
    assert(not nav.route(graph,{x=0,y=0,z=2},{x=-2,y=3,z=-2},q))
    assert(not nav.route(graph,{x=0,y=0,z=2},{x=-2,y=0,z=0},{walkable=function() return false end}))
end)

test("patrol needs visible acquisition, pursues, fires physical rounds and damages next tick",function()
    local ctx,e=context({x=0,y=.004,z=-13})
    ticks(ctx,3)
    assert(e.state=="patrol" and e.shots==0)
    ticks(ctx,90)
    assert(e.state=="pursuit" and e.travel>1)
    ticks(ctx,300)
    assert(e.state=="fire" and e.shots>0 and ctx.player.actor.health<100)
    assert(e.position.z< -4)
    runtime.final(ctx)
end)

test("walls, rear-facing patrols and inspection prevent target acquisition and shooting",function()
    local ctx,e=context()
    e.query.blocked=true;ticks(ctx,360)
    assert(e.shots==0 and ctx.player.actor.health==100 and not e.visible)
    e.query.blocked=false;e.yaw=0;e.motion.yaw=0
    e.patrol_points[2]={x=0,y=0,z=-12}
    ticks(ctx,60)
    assert(e.shots==0 and e.notice==0)
    ctx.player.enabled=false
    local before=V.copy(e.position)
    ticks(ctx,240)
    near(e.position.z,before.z);assert(e.shots==0)
    runtime.final(ctx)
end)

test("lost sight uses last-seen position and never fires through new cover",function()
    local ctx,e=context()
    ticks(ctx,180);assert(e.shots>0)
    e.query.blocked=true
    local shots=e.shots
    ticks(ctx,180)
    assert(e.shots==shots and e.state=="pursuit")
    ticks(ctx,480)
    assert(e.state=="patrol" and e.shots==shots)
    runtime.final(ctx)
end)

test("death is single-owner, stops fire immediately, collapses once, and reset rejects old hits",function()
    local ctx,e=context()
    local deaths=0
    events.on(ctx.events,events.ACTOR_DEATH,ctx,function(_,hit) if hit.actor==e.id then deaths=deaths+1 end end)
    ticks(ctx,180)
    combat.request(ctx.combat,{target=e.id,amount=999,source="player"})
    local shots=e.shots
    ticks(ctx,240)
    assert(e.state=="dead" and e.death==1 and e.shots==shots and deaths==1)
    local replacement=ai.reset(ctx,{x=0,y=.004,z=-8},math.pi)
    replacement.query=flat()
    combat.request(ctx.combat,{target=replacement.id,amount=99})
    local newest=ai.reset(ctx,{x=0,y=.004,z=-8},math.pi);newest.query=flat()
    ticks(ctx,1)
    assert(newest.actor.health==100 and ctx.ai.sim.fired==0)
    runtime.final(ctx)
    assert(next(ctx.combat.actors)==nil and next(ctx.events.listeners)==nil)
end)

test("soldier behaviour and animation are identical at 30/60/144 presentation FPS",function()
    local expected
    for _,fps in ipairs({30,60,144}) do
        local ctx,e=context();local accumulated=0
        for _=1,fps*3 do
            accumulated=accumulated+1/fps
            while accumulated+1e-10>=h do runtime.fixed_update(ctx,h);accumulated=accumulated-h end
            runtime.update(ctx,1/fps)
        end
        local result={e.position.x,e.position.z,e.phase,e.shots,ctx.player.actor.health}
        if expected then for i,v in ipairs(expected) do near(result[i],v) end else expected=result end
        runtime.final(ctx)
    end
end)
print(count.." soldier tests passed")
