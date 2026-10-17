-- Engine-independent weapon/ballistics contract: lua tests/weapons_test.lua
package.path="./?.lua;"..package.path
local runtime=require "game.runtime"
local input=require "game.input"
local weapons=require "game.systems.weapons"
local defs=require "game.weapons.defs"
local events=require "game.events"
local combat=require "game.combat"
local ballistics=require "game.weapons.ballistics"
local trace=require "game.weapons.trace"
local geometry=require "game.weapons.geometry"
local clips=require "game.weapons.clips"
local viewmodel=require "game.weapons.viewmodel"
local V=require "game.weapons.math"
local h=1/120
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function near(a,b,e) assert(math.abs(a-b)<(e or 1e-8),a.." != "..b) end
local function ticks(ctx,n) for _=1,n do runtime.fixed_update(ctx,h) end end
local function button(ctx,key,held) input.button(ctx.input,key,held and {pressed=true} or {released=true}) end
local function tap(ctx,key) button(ctx,key,true);ticks(ctx,1);button(ctx,key,false) end
local function new(id)
    local ctx=runtime.new();ctx.world.ready=true;ctx.player.motion.grounded=true
    ticks(ctx,80)
    if id and id~="rifle" then assert(weapons.select(ctx,id));ticks(ctx,150) end
    return ctx
end
local function snapshot(ctx) return weapons.snapshot(ctx) end
local function shape(id,z,d,surface,actor)
    return {id=id,x=0,y=0,z=z,w=4,h=4,d=d,surface=surface,actor=actor}
end
local function launch(shapes,def)
    local ctx=new();ctx.services.bullets=trace.boxes(shapes)
    local hits={}
    events.on(ctx.events,events.BULLET_IMPACT,hits,function(_,hit) hits[#hits+1]=hit end)
    local p=ballistics.spawn(ctx.weapons.sim,def or defs.rifle,{x=0,y=0,z=0},{x=0,y=0,z=-1},"player",false)
    return ctx,p,hits
end

test("origin containment prefilter preserves rotated, animated and near-face slab hits",function()
    local T=require "game.ai.transform"
    local random=require("game.rng").new(1337,"origin-containment")
    local accepted,rejected=0,0
    for i=1,4000 do
        local s={id="probe",x=(random()-.5)*200,y=(random()-.5)*20,z=(random()-.5)*200,
            w=.1+random()*8,h=.1+random()*5,d=.1+random()*8}
        local rotation=T.rotation((random()-.5)*6,(random()-.5)*6,(random()-.5)*6)
        if i%3==0 then rotation[4],rotation[8],rotation[12]=s.x,s.y,s.z;s.transform=rotation
        elseif i%3==1 then s.rotation_x=(random()-.5)*6;rotation=T.rotation(s.rotation_x,0,0)
        else rotation=T.identity() end
        rotation[4],rotation[8],rotation[12]=s.x,s.y,s.z
        local local_origin={x=(random()-.5)*s.w*3,y=(random()-.5)*s.h*3,z=(random()-.5)*s.d*3}
        local local_dir=V.normalize({x=random()-.5,y=random()-.5,z=random()-.5})
        if i%4==0 then
            -- Inside, exactly on the face, and just outside within the native
            -- fallback's accepted entry epsilon; exercise both travel directions.
            local_origin={x=s.w/2+((i%16)/4-1)*.25e-7,y=0,z=0}
            local_dir={x=-1,y=0,z=0}
        end
        local origin,direction=T.point(rotation,local_origin),T.direction(rotation,local_dir)
        local full=trace.box(s,origin,direction,10)
        local candidate=trace.contains_origin(s,origin,direction)
        if full and full.enter<=1e-7 then
            assert(candidate,"Containment discarded a valid starting-inside interval: "..i)
            accepted=accepted+1
        elseif not candidate then rejected=rejected+1 end
    end
    assert(accepted>500 and rejected>2000)
end)

test("auto rate preserves fractional tick intervals and ammunition",function()
    for _,case in ipairs({{"rifle",14,31},{"smg",16,33}}) do
        local ctx=new(case[1]);button(ctx,"fire",true);ticks(ctx,120)
        assert(snapshot(ctx).fired==case[2],snapshot(ctx).fired)
        assert(snapshot(ctx).ammo==case[3]-case[2]);assert(snapshot(ctx).reserve==defs[case[1]].reserve)
        button(ctx,"fire",false);ticks(ctx,120);assert(snapshot(ctx).fired==case[2])
    end
end)
test("semi-auto needs a new press and quick taps survive render frames",function()
    local ctx=new("pistol")
    button(ctx,"fire",true);ticks(ctx,120);assert(snapshot(ctx).fired==1)
    button(ctx,"fire",false);ticks(ctx,1)
    button(ctx,"fire",true);button(ctx,"fire",false)
    runtime.update(ctx,h/2);runtime.update(ctx,h/2);ticks(ctx,1)
    assert(snapshot(ctx).fired==2);ticks(ctx,30);assert(snapshot(ctx).fired==2)
end)
test("three-round burst completes after release and does not restart on hold",function()
    local ctx=new();tap(ctx,"fire_mode");assert(snapshot(ctx).mode=="burst")
    tap(ctx,"fire");ticks(ctx,60);assert(snapshot(ctx).fired==3)
    button(ctx,"fire",true);ticks(ctx,120);assert(snapshot(ctx).fired==6)
    button(ctx,"fire",false);ticks(ctx,30);tap(ctx,"fire_mode");assert(snapshot(ctx).mode=="semi")
    button(ctx,"fire",true);ticks(ctx,120);assert(snapshot(ctx).fired==7)
end)
test("tactical reload transfers only at mag-in and conserves every round",function()
    local ctx=new();button(ctx,"fire",true);ticks(ctx,25);button(ctx,"fire",false)
    local before=snapshot(ctx);local total=before.ammo+before.reserve
    local phases={}
    events.on(ctx.events,events.WEAPON_RELOAD,phases,function(_,e) phases[#phases+1]=e.phase end)
    tap(ctx,"reload");ticks(ctx,180)
    assert(snapshot(ctx).ammo==before.ammo)
    button(ctx,"fire",true);ticks(ctx,35);assert(snapshot(ctx).ammo==31)
    button(ctx,"fire",false);ticks(ctx,60)
    local after=snapshot(ctx);assert(after.clip=="idle" and after.ammo==31)
    assert(after.ammo+after.reserve==total and after.fired==before.fired)
    assert(table.concat(phases,",")=="start,magout,magdrop,magin,slap,end")
end)
test("the last chambered shot fires before a fresh dry trigger requests reload",function()
    local ctx=new("pistol");local s=ctx.weapons.inventory.pistol
    s.mag=0;s.chambered=true
    tap(ctx,"fire");ticks(ctx,30)
    assert(snapshot(ctx).fired==1 and snapshot(ctx).ammo==0 and snapshot(ctx).clip=="idle")
    tap(ctx,"fire");assert(snapshot(ctx).clip=="reloadEmpty")
end)
test("empty reload fills magazine then chambers one at the bolt-release beat",function()
    local ctx=new();local s=ctx.weapons.inventory.rifle
    s.mag=0;s.chambered=false;s.reserve=7
    tap(ctx,"reload");ticks(ctx,260)
    assert(s.mag==7 and not s.chambered and s.reserve==0)
    ticks(ctx,65);assert(s.mag==6 and s.chambered);ticks(ctx,30)
    assert(snapshot(ctx).ammo==7 and snapshot(ctx).clip=="idle")
end)
test("reload cancellation before and after transfer cannot duplicate or strand ammunition",function()
    for _,wait in ipairs({40,220}) do
        local ctx=new();local s=ctx.weapons.inventory.rifle;s.mag=8
        local total=9+s.reserve
        tap(ctx,"reload");ticks(ctx,wait);assert(weapons.select(ctx,"smg"));ticks(ctx,150)
        assert(s.mag+(s.chambered and 1 or 0)+s.reserve==total)
        assert(weapons.select(ctx,"rifle"));ticks(ctx,150)
        assert(snapshot(ctx).ammo==(wait==40 and 9 or 31))
    end
    local ctx=new();local s=ctx.weapons.inventory.rifle;s.mag=0;s.chambered=false;s.reserve=30
    tap(ctx,"reload");ticks(ctx,260);assert(s.mag==30 and not s.chambered and s.reserve==0)
    weapons.select(ctx,"smg");ticks(ctx,150);weapons.select(ctx,"rifle");ticks(ctx,150)
    tap(ctx,"reload");ticks(ctx,355)
    assert(snapshot(ctx).ammo==30 and s.chambered and s.reserve==0)
end)
test("switching retains independent ammo/modes and suppresses firing during both clips",function()
    local ctx=new();tap(ctx,"fire");ticks(ctx,20);tap(ctx,"fire_mode")
    local rounds=snapshot(ctx).ammo
    weapons.select(ctx,"pistol");button(ctx,"fire",true);ticks(ctx,90)
    assert(snapshot(ctx).fired==1 and snapshot(ctx).weapon=="pistol")
    button(ctx,"fire",false);ticks(ctx,30);tap(ctx,"fire");assert(snapshot(ctx).fired==2)
    weapons.select(ctx,"rifle");ticks(ctx,150)
    assert(snapshot(ctx).ammo==rounds and snapshot(ctx).mode=="burst")
end)
test("inspection is interruptible; loading, sprint, mantle, inspection cameras and death gate fire",function()
    local ctx=new();tap(ctx,"inspect");ticks(ctx,30);assert(snapshot(ctx).clip=="inspect")
    tap(ctx,"fire");assert(snapshot(ctx).clip=="idle" and snapshot(ctx).fired==1)
    for _,gate in ipairs({"loading","sprint","mantle","camera","death"}) do
        local c=new()
        if gate=="loading" then c.world.ready=false
        elseif gate=="sprint" then c.player.motion.sprinting=true
        elseif gate=="mantle" then c.player.motion.mantle={time=0,duration=0.62,kind="mantle",side=1}
        elseif gate=="camera" then c.player.enabled=false
        else combat.request(c.combat,{target="player",amount=100}) end
        button(c,"fire",true);ticks(c,60);assert(snapshot(c).fired==0,gate)
    end
end)
test("ADS improves spread and changes both projections; recoil springs recover",function()
    local ctx=new();local hip=snapshot(ctx).spread
    button(ctx,"aim",true);ticks(ctx,120);runtime.update(ctx,h)
    local state=snapshot(ctx);assert(state.ads==1 and state.spread<hip*.2)
    local model=geometry.weapon("rifle");local p=viewmodel.pose(ctx,model)
    near(p.world_fov,math.rad(70)*defs.rifle.adsFov);near(p.view_fov,math.rad(60)*defs.rifle.viewFov)
    tap(ctx,"fire");assert(snapshot(ctx).recoil_pitch>0 and ctx.weapons.recoil.back.v>0)
    ticks(ctx,240);assert(math.abs(snapshot(ctx).recoil_pitch)<1e-6 and math.abs(snapshot(ctx).recoil_back)<1e-6)
    ctx.player.motion.sprinting=true;ticks(ctx,30);assert(snapshot(ctx).ads==0)
end)
test("fast rounds sweep the complete segment and concrete protects the target",function()
    local ctx,p,hits=launch({shape("wall",-2,.1,"concrete"),shape("target",-4,.2,"flesh","enemy")})
    local actor=combat.register(ctx.combat,"enemy",100)
    ticks(ctx,2)
    assert(not p.alive and p.position.z> -2.06 and #hits==1)
    assert(hits[1].surface=="concrete" and hits[1].audio=="concrete" and actor.health==100)
end)
test("thin wood has measured entry/exit and reduced target damage exactly once",function()
    local ctx,p,hits=launch({shape("wood",-2,.1,"wood"),shape("body",-4,.2,"flesh","enemy"),shape("second_hitbox",-4.1,.2,"flesh","enemy")})
    local actor=combat.register(ctx.combat,"enemy",100)
    local requests=0;events.on(ctx.events,events.DAMAGE_DEALT,ctx,function()requests=requests+1 end)
    ticks(ctx,4)
    assert(hits[1].collider=="wood" and not hits[1].exit and hits[2].exit)
    near(hits[2].distance-hits[1].distance,.1,1e-6)
    assert(actor.health>67 and actor.health<76,actor.health)
    assert(requests==1);ticks(ctx,10);assert(requests==1)
end)
test("flight time and gravity are retained after penetration across tick boundaries",function()
    local d={};for k,v in pairs(defs.rifle) do d[k]=v end;d.muzzleVelocity=12;d.dragK=0
    local ctx,p,hits=launch({shape("wood",-.12,.16,"wood"),shape("target",-.6,.1,"flesh","enemy")},d)
    local actor=combat.register(ctx.combat,"enemy",100)
    ticks(ctx,1);assert(p.alive and p.position.z>-.11 and actor.health==100 and #hits==1)
    ticks(ctx,1);assert(#hits==2 and hits[2].exit)
    ticks(ctx,3);assert(actor.health==100)
    ticks(ctx,2);assert(actor.health<100 and p.position.y<0)
end)
test("range limit truncates the segment before collision beyond maximum range",function()
    local d={};for k,v in pairs(defs.rifle) do d[k]=v end;d.maxRange=1
    local ctx,p,hits=launch({shape("wall",-2,.1,"wood")},d);ticks(ctx,1)
    assert(not p.alive and #hits==0);near(p.travelled,1);assert(p.position.z>=-1)
end)
test("origins inside solids, angled thickness and overlapping materials remain solid",function()
    local ctx,p,hits=launch({shape("wall",0,2,"concrete")});ticks(ctx,1)
    assert(not p.alive and #hits==1 and math.abs(p.position.z)<.056)
    local b=shape("angled",-1,.1,"wood");b.rotation_x=math.pi/3
    local interval=trace.box(b,{x=0,y=0,z=0},{x=0,y=0,z=-1},3)
    near(interval.leave-interval.enter,.2)
    local ctx2,p2=launch({shape("one",-.2,.2,"wood"),shape("two",-.2,.2,"wood")});ticks(ctx2,1)
    assert(not p2.alive and p2.position.z>-.3)
end)
test("projectile budget is bounded and expired rounds retire",function()
    local ctx=new();local sim=ctx.weapons.sim
    for _=1,140 do ballistics.spawn(sim,defs.pistol,{x=0,y=10,z=0},{x=0,y=0,z=-1}) end
    assert(#sim.live==128 and sim.retired==12);ticks(ctx,610);assert(#sim.live==0 and sim.retired==140)
end)
test("all generated parts have finite bounds and consistent outward triangles",function()
    local total=0
    for _,id in ipairs({"rifle","smg","pistol"}) do
        local model=geometry.weapon(id)
        for _,b in pairs(model.parts) do
            assert(b.vertex_count>0 and #b.positions==b.vertex_count*3 and #b.colors==b.vertex_count*4)
            total=total+b.vertex_count
            for i,p in ipairs(b.positions) do
                local axis=(i-1)%3+1
                assert(p==p and p>=b.bounds[axis] and p<=b.bounds[axis+3])
            end
            for i=1,#b.positions,9 do
                local p,n=b.positions,b.normals
                local ax,ay,az=p[i+3]-p[i],p[i+4]-p[i+1],p[i+5]-p[i+2]
                local bx,by,bz=p[i+6]-p[i],p[i+7]-p[i+1],p[i+8]-p[i+2]
                assert((ay*bz-az*by)*n[i]+(az*bx-ax*bz)*n[i+1]+(ax*by-ay*bx)*n[i+2]>=-1e-10)
            end
        end
    end
    assert(total<30000);print("GEOMETRY vertices",total)
    for _,name in ipairs({"draw","holster","inspect","reloadTac","reloadEmpty"}) do
        local s=clips.sample(name,1)
        if name~="holster" then for i=1,3 do near(s.pos[i],0);near(s.rot[i],0) end end
    end
end)
test("weapon results and shot directions agree at 30/60/144 presentation FPS",function()
    local results={}
    for _,fps in ipairs({30,60,144}) do
        local ctx=new("smg");local shots={}
        events.on(ctx.events,events.WEAPON_FIRE,shots,function(_,s) shots[#shots+1]=s.dir end)
        button(ctx,"fire",true);button(ctx,"aim",true)
        local accumulated=0
        for _=1,fps do
            accumulated=accumulated+1/fps
            while accumulated+1e-10>=h do ticks(ctx,1);accumulated=accumulated-h end
            runtime.update(ctx,1/fps)
        end
        results[#results+1]={state=snapshot(ctx),shots=shots}
    end
    for i=2,#results do
        assert(results[i].state.fired==results[1].state.fired)
        for _,key in ipairs({"ammo","reserve","ads","spread","recoil_pitch","recoil_back"}) do near(results[i].state[key],results[1].state[key]) end
        for j,dir in ipairs(results[i].shots) do for _,axis in ipairs({"x","y","z"}) do near(dir[axis],results[1].shots[j][axis]) end end
    end
end)
print(count.." weapon tests passed")
