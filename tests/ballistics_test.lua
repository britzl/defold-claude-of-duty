-- Engine-independent terminal ballistics and skeleton damage contracts.
package.path="./?.lua;"..package.path
local ballistics=require "game.weapons.ballistics"
local trace=require "game.weapons.trace"
local surfaces=require "game.weapons.surfaces"
local defs=require "game.weapons.defs"
local combat=require "game.combat"
local events=require "game.events"
local rig=require "game.ai.rig"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local runtime=require "game.runtime"
local input=require "game.input"
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function near(a,b,t) assert(math.abs(a-b)<(t or 1e-8),a.." != "..b) end
local function definition(fields)
    local d={id="test",damage=20,muzzleVelocity=1000,penetration=1,dropoff=1,maxRange=100,dragK=0}
    for k,v in pairs(fields or {}) do d[k]=v end
    return d
end
local function shape(id,z,depth,surface,actor)
    return {id=id,x=0,y=0,z=z,w=20,h=20,d=depth,surface=surface,actor=actor}
end
local function launch(shapes,options)
    options=options or {}
    local ctx={events=events.new(),combat=combat.new(),world={ready=false}}
    local hits,segments,damage={},{},{}
    events.on(ctx.events,events.BULLET_IMPACT,hits,function(_,e) hits[#hits+1]=e end)
    events.on(ctx.events,events.BULLET_SEGMENT,segments,function(_,e) segments[#segments+1]=e end)
    events.on(ctx.events,events.DAMAGE_DEALT,damage,function(_,e) damage[#damage+1]=e end)
    local sim=ballistics.new(options.seed)
    local p=ballistics.spawn(sim,options.def or definition(),options.origin or {x=0,y=0,z=0},
        options.direction or {x=0,y=0,z=-1},"player",true)
    local query=trace.boxes(shapes)
    return ctx,sim,p,hits,segments,damage,query
end
local function step(ctx,sim,query,dt)
    ballistics.update(ctx,sim,dt or .01,query);combat.fixed_update(ctx,dt or .01)
end

test("all twelve surfaces match reference single-layer retention and deflection",function()
    for name,props in pairs(surfaces) do
        local ctx,sim,p,hits,segments,_,q=launch({shape("layer",-2,props.depth*.4,name)})
        step(ctx,sim,q)
        assert(#hits==2 and not hits[1].exit and hits[2].exit,name)
        local distance=hits[2].distance-hits[1].distance
        near(p.power,1-distance/props.depth)
        near(p.damage,20*(1-props.loss*distance/props.depth))
        near(V.length(p.velocity),math.sqrt(1000^2+.0981^2))
        assert(sim.deflections==1 and #segments==2 and math.abs(p.position.x)>1e-8,name)
        near(segments[1].to.x,segments[2].from.x);near(segments[1].to.z,segments[2].from.z)
    end
end)

test("thin layers pass and over-budget layers stop without an exit for each weapon",function()
    for _,d in pairs(defs) do for name,s in pairs(surfaces) do
        for _,fraction in ipairs({.5,1.5}) do
            local ctx,sim,p,hits,_,_,q=launch({shape("layer",-.5-s.depth*d.penetration*fraction/2,s.depth*d.penetration*fraction,name)}, {def=d})
            for _=1,10 do step(ctx,sim,q,1/120) end
            assert((sim.exits==1)==(fraction<1),name.." "..d.id)
            if fraction>1 then assert(not p.alive and #hits==1) end
        end
    end end
end)

test("successive layers use the remaining entry budget rather than muzzle power",function()
    local ctx,sim,p,hits,_,_,q=launch({shape("wood",-1,.16,"wood"),shape("glass",-2,.09,"glass")})
    step(ctx,sim,q)
    assert(#hits==4)
    local first=(hits[2].distance-hits[1].distance)/.32
    local second=(hits[4].distance-hits[3].distance)/(.45*(1-first))
    near(p.damage,20*(1-.3*first)*(1-.12*second))
    near(p.power,1-first-(hits[4].distance-hits[3].distance)/.45)
    assert(sim.deflections==2)
end)

test("slow traversal accumulates one layer loss and one exit deflection across ticks",function()
    local ctx,sim,p,hits,_,_,q=launch({shape("wood",-.4,.2,"wood")},{def=definition({muzzleVelocity=10})})
    step(ctx,sim,q,.04);assert(#hits==1 and sim.deflections==0)
    local inside=p.travelled-hits[1].distance
    near(p.damage,20*(1-.3*inside/.32))
    for _=1,5 do step(ctx,sim,q,.01) end
    assert(#hits==2 and sim.deflections==1)
    near(p.damage,20*(1-.3*(hits[2].distance-hits[1].distance)/.32))
end)

test("overlapping and coincident exits are deterministic regardless of query order",function()
    local a,b=shape("a",-1,.08,"wood"),shape("b",-1,.08,"wood")
    local expected
    for _,shapes in ipairs({{a,b},{b,a}}) do
        local ctx,sim,p,hits,_,_,q=launch(shapes);step(ctx,sim,q)
        assert(#hits==4 and sim.exits==2 and sim.deflections==2)
        local result={p.power,p.damage,p.position.x,p.position.y,p.position.z}
        if expected then for i,v in ipairs(result) do near(v,expected[i],1e-12) end else expected=result end
    end
end)

test("deflected path is re-queried in the same tick and cannot hit stale straight-path targets",function()
    local wall=shape("wood",-1,.24,"wood")
    local ctx,sim,p,_,segments,_,q=launch({wall});step(ctx,sim,q)
    assert(#segments==2 and math.abs(p.position.x)>.02)
    local end_point=V.point(p.position,V.normalize(p.velocity),-.5)
    for _,bent in ipairs({true,false}) do
        local target={id="target",actor="target",surface="flesh",x=bent and end_point.x or 0,
            y=bent and end_point.y or -.0009,z=end_point.z,w=.004,h=.004,d=.04}
        local c,s,_,hits,_,damage,query=launch({wall,target})
        local actor=combat.register(c.combat,"target",100)
        step(c,s,query)
        assert((actor.health<100)==bent and #damage==(bent and 1 or 0))
        if bent then assert(hits[3].collider=="target") end
    end
end)

test("exit re-query does not skip a very thin adjacent layer",function()
    local a=shape("wood",-1,.1,"wood")
    local b=shape("foil",-1.05001,.00002,"metal")
    local ctx,sim,_,hits,_,_,q=launch({a,b});step(ctx,sim,q)
    assert(#hits==4 and hits[3].collider=="foil" and sim.deflections==2)
end)

test("near vertical and grazing flight stays finite and preserves speed at deflection",function()
    for _,dir in ipairs({{x=0,y=1,z=0},{x=0,y=-1,z=0},{x=.999,y=0,z=-.0447}}) do
        dir=V.normalize(dir)
        local box=shape("glass",dir.z,.01,"glass");box.x,box.y=dir.x,dir.y
        box.w,box.h=math.abs(dir.y)>.9 and 2 or .1,math.abs(dir.y)>.9 and .01 or 2
        local ctx,sim,p,_,_,_,q=launch({box},{direction=dir});step(ctx,sim,q)
        assert(sim.deflections==1)
        for _,v in pairs(p.velocity) do assert(v==v and math.abs(v)<math.huge) end
    end
end)

test("round-local random streams repeat and are independent of other live rounds",function()
    local expected
    for _,extra in ipairs({false,true}) do
        local ctx,sim,p,_,_,_,q=launch({shape("wood",-1,.16,"wood")})
        if extra then
            for _=1,8 do ballistics.spawn(sim,definition(),{x=1,y=0,z=0},{x=0,y=0,z=-1},"enemy") end
        end
        step(ctx,sim,q)
        local result={p.position.x,p.position.y,p.position.z,p.damage}
        if expected then for i,v in ipairs(result) do near(v,expected[i],1e-12) end else expected=result end
    end
    local ctx,sim,p,_,_,_,q=launch({shape("wood",-1,.16,"wood")},{seed=734})
    step(ctx,sim,q);assert(math.abs(p.position.x-expected[1])>.001)
end)

test("range falloff is applied once for every weapon and range clips before distant geometry",function()
    for _,d in pairs(defs) do for _,fraction in ipairs({.01,.5,.95}) do
        local box=shape("target",-d.maxRange*fraction,.01,"flesh","target")
        local ctx,sim,_,_,_,damage,q=launch({box},{def=d})
        combat.register(ctx.combat,"target",1000)
        for _=1,600 do if #sim.live==0 then break end;step(ctx,sim,q,1/120) end
        assert(#damage==1,d.id)
        local point=damage[1].point
        -- Impact distance comes from actual travelled arc, not straight range.
        local ctx2,sim2,_,hits,_,_,q2=launch({box},{def=d})
        for _=1,600 do if #sim2.live==0 then break end;step(ctx2,sim2,q2,1/120) end
        near(damage[1].amount,d.damage*(1-(1-d.dropoff)*(hits[1].distance/d.maxRange)^2))
        assert(point.z> -d.maxRange)
    end end
    local ctx,sim,p,hits,_,_,q=launch({shape("beyond",-1.01,.001,"glass")},{def=definition({maxRange=1})})
    step(ctx,sim,q);assert(not p.alive and #hits==0);near(p.travelled,1)
end)

test("eleven animated volumes carry reference region scales and arm frames follow both joints",function()
    local expected={head=4,chest=1,hips=.9,leg_r=.7,leg_l=.7,shin_r=.7,shin_l=.7,
        upper_arm_r=.65,forearm_r=.65,upper_arm_l=.65,forearm_l=.65}
    for i=0,8 do
        local palette=rig.pose({walk=1,phase=i*.7,crouch=i/8,aim=1,pitch=i*.07})
        local root=T.root({x=3,y=2,z=-4},i*.3)
        local volumes=rig.volumes(palette,{x=3,y=2,z=-4},i*.3,"target")
        assert(#volumes==11)
        for index,box in ipairs(volumes) do
            assert(box.damage_scale==expected[box.part])
            local ctx,sim,_,_,_,damage,q=launch({box},{origin=T.point(box.transform,{x=0,y=0,z=.4}),
                direction=T.direction(box.transform,{x=0,y=0,z=-1})})
            local actor=combat.register(ctx.combat,"target",1000);step(ctx,sim,q,.001)
            near(1000-actor.health,20*expected[box.part]);assert(#damage==1)
            assert(damage[1].part==box.part and damage[1].region==box.region)
            assert(damage[1].headshot==(box.part=="head"))
            if box.region=="arm" then
                local spec=rig.hitboxes[index]
                local bind=rig.bones[rig.index[spec.bone]].bind
                local joint=T.point(T.mul(root,palette[rig.index[spec.bone]]),bind)
                local local_joint=T.point(T.inverse(box.transform),joint)
                near(local_joint.x,0);near(local_joint.z,0);near(math.abs(local_joint.y),box.h*.5-.02)
            end
        end
    end
end)

test("arm then torso overlap damages once at the first region and preserves death metadata",function()
    local arm=shape("arm",-1,.1,"flesh","target");arm.region="arm";arm.part="forearm_l";arm.damage_scale=.65
    local torso=shape("torso",-1.05,.1,"flesh","target");torso.damage_scale=1
    local ctx,sim,_,_,_,damage,q=launch({torso,arm})
    combat.register(ctx.combat,"target",10)
    local deaths={};events.on(ctx.events,events.ACTOR_DEATH,deaths,function(_,e) deaths[#deaths+1]=e end)
    step(ctx,sim,q)
    assert(#damage==1 and damage[1].amount==10 and damage[1].part=="forearm_l")
    assert(#deaths==1 and deaths[1].region=="arm")
    step(ctx,sim,q);assert(#damage==1 and #deaths==1)
end)

test("six-layer guard and live-round cap remain bounded",function()
    local shapes={}
    for i=1,10 do shapes[i]=shape("sheet"..i,-i*.1,.001,"fabric") end
    local ctx,sim,p,hits,_,_,q=launch(shapes);step(ctx,sim,q)
    assert(not p.alive and #hits==12 and sim.exits==6)
    for _=1,140 do ballistics.spawn(sim,definition(),{x=0,y=1,z=0},{x=0,y=0,z=-1}) end
    assert(#sim.live==128 and sim.retired==13)
end)

test("eye-origin production fire hits cover before a protruding muzzle and ignores muzzle-only overlap",function()
    for _,blocked in ipairs({true,false}) do
        local ctx=runtime.new();ctx.world.ready=true;ctx.ai.enabled=false
        for _=1,80 do runtime.fixed_update(ctx,1/120) end
        local eye=require("game.player.camera").compose(ctx,1,{}).camera
        local wall={id="cover",x=eye.x,y=eye.y-(blocked and 0 or .4),z=eye.z-.22,w=4,h=.3,d=.15,surface="concrete"}
        local target={id="target",actor="target",x=eye.x,y=eye.y,z=eye.z-2,w=2,h=.5,d=.2,surface="flesh"}
        local actor=combat.register(ctx.combat,"target",100)
        ctx.services.bullets=trace.boxes({wall,target})
        input.button(ctx.input,"fire",{pressed=true});runtime.fixed_update(ctx,1/120)
        input.button(ctx.input,"fire",{released=true});runtime.fixed_update(ctx,1/120)
        assert((actor.health==100)==blocked)
        runtime.final(ctx)
    end
end)

test("moving-body metadata survives ray intervals and impact notifications",function()
    local body=shape("body/test",-2,.01,"metal");body.dynamic=true
    local ctx,sim,p,hits,_,_,q=launch({body})
    step(ctx,sim,q)
    assert(#hits>0)
    for _,hit in ipairs(hits) do assert(hit.dynamic==true) end
end)
print(count.." ballistics tests passed")
