package.path="./?.lua;"..package.path
local F=require "game.ui.feedback"
local hud=require "game.ui.hud"
local events=require "game.events"
local runtime=require "game.runtime"
local combat=require "game.combat"
local ai=require "game.systems.ai"
local ctx=runtime.new()
while not ctx.world.ready do runtime.update(ctx,1/60) end
ai.reset(ctx,{x=0,y=0,z=-10},0);ctx.ai.enabled=false
ctx.presentation={position={x=0,y=0,z=0},camera={x=0,y=1.6,z=0},yaw=0,pitch=0,roll=0,fov=math.rad(70)}
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." ~= "..tostring(b)) end
test("perspective tracks yaw pitch roll FOV and aspect; behind-axis clamps to edge",function()
    local c=ctx.presentation
    local p=F.project({x=0,y=1.6,z=-10},c,960,640,70);near(p.x,0);near(p.y,0);assert(not p.offscreen)
    local q=F.project({x=2,y=1.6,z=-10},c,960,640,70);assert(q.x>0)
    c.roll=math.pi/2;p=F.project({x=2,y=1.6,z=-10},c,960,640,70);near(p.x,0);near(p.y,-q.x);c.roll=0
    c.pitch=.2;p=F.project({x=0,y=1.6,z=-10},c,960,640,70);assert(p.y<0);c.pitch=0
    c.yaw=-math.pi/2;p=F.project({x=10,y=1.6,z=0},c,960,640,70);near(p.x,0);assert(not p.behind);c.yaw=0
    for _,wh in ipairs({{960,640},{1280,720},{2560,720},{640,960}}) do
        p=F.project({x=0,y=1.6,z=10},c,wh[1],wh[2],70)
        assert(p.behind and p.offscreen);near(p.y,-wh[2]/2+70)
        p=F.project({x=10,y=4,z=0},c,wh[1],wh[2],70)
        assert(math.abs(p.x)<=wh[1]/2-70+1e-6 and math.abs(p.y)<=wh[2]/2-70+1e-6)
    end
end)
test("north-up contacts clip to map and retain floor hints",function()
    local at=ctx.presentation.position
    local p=F.map_point({x=10,y=3,z=-10},at,148,22,false)
    assert(p.x>0 and p.y>0 and p.floor==1)
    assert(F.map_point({x=0,y=-3,z=0},at,148,22,false).floor==-1)
    assert(not F.map_point({x=100,y=0,z=0},at,148,22,false))
    assert(F.map_point({x=100,y=0,z=0},at,148,22,true).x==67)
end)
test("only player damage creates confirmations; duplicate lethal requests announce once",function()
    combat.register(ctx.combat,"fixture",10)
    for _=1,2 do combat.request(ctx.combat,{target="fixture",amount=20,source="player",headshot=true,point={x=0,y=1.6,z=-8}}) end
    combat.fixed_update(ctx,1/120)
    assert(#ctx.hud.feedback.numbers==1 and F.snapshot(ctx).hit_kind=="kill")
    assert(F.snapshot(ctx).banner=="ENEMY ELIMINATED")
    events.emit(ctx.events,events.DAMAGE_DEALT,{source="enemy_1",target="player",amount=5})
    assert(#ctx.hud.feedback.numbers==1)
end)
test("floods stay bounded and copy hit points without simulation randomness",function()
    local p={x=1,y=1.6,z=-8}
    for _=1,100 do
        events.emit(ctx.events,events.DAMAGE_DEALT,{source="player",target="enemy_2",amount=33,point=p})
        events.emit(ctx.events,events.DAMAGE_TAKEN,{amount=20,from=p})
    end
    p.x=500
    assert(#ctx.hud.feedback.numbers==16 and #ctx.hud.feedback.arcs==6)
    assert(ctx.hud.feedback.numbers[16].position.x==1)
    local a=F.items(ctx,960,640).arcs[1].angle
    ctx.presentation.yaw=-.3;local b=F.items(ctx,960,640).arcs[1].angle;near(a-b,.3);ctx.presentation.yaw=0
end)
test("pause freezes presentation expiry; resume expires it and reset clears capabilities",function()
    F.set_prompt(ctx,{key="F",text="USE",progress=.5})
    local p={x=0,y=0,z=-5};F.set_objectives(ctx,{{position=p,label="A",name="CHECK"}});p.x=50
    assert(ctx.hud.feedback.objectives[1].position.x==0)
    runtime.set_paused(ctx,true);runtime.update(ctx,10)
    assert(#ctx.hud.feedback.numbers==16)
    runtime.set_paused(ctx,false);F.update(ctx,3)
    assert(#ctx.hud.feedback.numbers==0 and #ctx.hud.feedback.arcs==0 and F.snapshot(ctx).banner=="")
    hud.reset(ctx);assert(#ctx.hud.feedback.objectives==0 and not ctx.hud.feedback.prompt)
end)
test("grenades prioritize imminent fuses and exclude expired or distant bodies",function()
    ctx.grenades.live={}
    for i=1,8 do ctx.grenades.live[i]={position={x=1,y=3,z=1},fuse=i*.2} end
    ctx.grenades.live[9]={position={x=0,y=0,z=0},fuse=0}
    ctx.grenades.live[10]={position={x=100,y=0,z=0},fuse=.01}
    local items=F.items(ctx,960,640)
    assert(#items.grenades==4 and items.grenades[1].fuse==.2 and items.grenades[4].fuse==.8)
    assert(items.grenades[1].floor==" ABOVE" and items.grenades[1].offscreen)
    for i=1,4 do for j=i+1,4 do assert(math.abs(items.grenades[i].y-items.grenades[j].y)>=59) end end
    ctx.grenades.live={}
end)
test("reload magazine absence, low ammo and chamber are independent",function()
    local w=ctx.weapons;w.equipped="rifle";w.inventory.rifle.mag=5;w.inventory.rifle.chambered=true
    w.clip="reloadTac";w.clip_duration=2.1;w.clip_time=1
    local s=F.snapshot(ctx);assert(s.mag==0 and s.ammo==6 and s.chambered and s.ammo_low and s.reload)
    w.clip_time=0;s=F.snapshot(ctx);assert(s.mag==5)
    w.clip=nil;w.inventory.rifle.mag=0;w.inventory.rifle.chambered=false
    assert(F.snapshot(ctx).ammo_empty and not F.snapshot(ctx).reload)
end)
test("display contracts reject non-finite input and oversized objective lists atomically",function()
    assert(not pcall(F.set_prompt,ctx,{progress=0/0}))
    assert(not pcall(F.set_objectives,ctx,{{position={x=math.huge,y=0,z=0}}}))
    local list={};for i=1,7 do list[i]={position={x=0,y=0,z=0}} end
    assert(not pcall(F.set_objectives,ctx,list));assert(#ctx.hud.feedback.objectives==0)
    F.set_prompt(ctx,{progress=2});assert(F.snapshot(ctx).prompt.progress==1)
    F.set_prompt(ctx,nil);assert(not ctx.hud.feedback.prompt)
end)
runtime.final(ctx)
print(count.." HUD feedback tests passed")
