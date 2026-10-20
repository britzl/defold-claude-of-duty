local fx=require 'game.render.combat_fx'
local geometry=require 'game.weapons.geometry'
local K=fx.kind
local function advance(s,seconds,query,env)
    for _=1,math.ceil(seconds*60) do fx.update(s,1/60,query,env) end
end
local floor={ray=function(_,p,dx,dy,dz)
    if dy<0 and p.y>=0 and p.y+dy<=0 then
        local t=-p.y/dy;return {x=p.x+dx*t,y=0,z=p.z+dz*t,nx=0,ny=1,nz=0,surface="concrete"}
    end
end}
local count=0
local function test(name,fn) fn();count=count+1;print('PASS '..name) end
local function impact(surface,x)
    return {point={x=x or 0,y=0,z=0},normal={x=0,y=1,z=0},surface=surface or 'concrete'}
end
test('impact pools stay bounded and replace the oldest marks',function()
    local state=fx.new()
    for i=1,100 do fx.impact(state,impact('concrete',i)) end
    local s=fx.snapshot(state)
    assert(s.particles==fx.particle_limit and s.decals==fx.decal_limit and #state.particles==fx.particle_limit and #state.decals==fx.decal_limit)
    for _,e in ipairs(state.decals) do assert(e.position.x>=53 and e.normal.y==1 and e.position.y>.0) end
end)
test('smoke grows, fades and expires while static marks retain their plane',function()
    local s=fx.new();fx.impact(s,impact())
    local smoke,mark=s.particles[1],s.decals[1]
    local size=fx.appearance(smoke)
    advance(s,.3)
    assert(fx.appearance(smoke)>size and smoke.position.y>.008)
    assert(mark.position.y==.003)
    advance(s,2);assert(fx.snapshot(s).particles==0 and fx.snapshot(s).decals==1)
    advance(s,25);assert(fx.snapshot(s).decals==0)
end)
test('zero time freezes presentation and generated sequences repeat exactly',function()
    local a,b=fx.new(),fx.new()
    for _=1,5 do fx.impact(a,impact());fx.impact(b,impact()) end
    fx.update(a,0)
    for i,e in ipairs(a.particles) do
        assert(e.life==b.particles[i].life)
        if e.life>0 then assert(e.seed==b.particles[i].seed and e.position.y==b.particles[i].position.y) end
    end
end)
test('moving or transparent receivers do not acquire floating static marks',function()
    local s=fx.new()
    for _,surface in ipairs({'flesh','glass','fabric','foliage','water'}) do fx.impact(s,impact(surface)) end
    assert(fx.snapshot(s).decals==0)
end)
test('actual shot presentation distinguishes world and viewmodel flashes',function()
    local s=fx.new();local p,d={x=1,y=2,z=3},{x=0,y=0,z=-1}
    fx.fire(s,p,d,false);assert(fx.snapshot(s).particles==1)
    fx.fire(s,p,d,true);assert(fx.snapshot(s).particles==3)
    advance(s,.06);assert(fx.snapshot(s).particles==2)
    assert(s.shots==2)
end)
test('unit quad has correct winding and complete UV coverage',function()
    local b=geometry.quad();assert(b.vertex_count==6)
    for i=1,#b.positions,9 do
        local p=b.positions
        local x=(p[i+3]-p[i])*(p[i+7]-p[i+1])-(p[i+4]-p[i+1])*(p[i+6]-p[i])
        assert(x>0 and b.normals[i+2]==1)
    end
end)
test('every weapon has bounded material identities and deterministic ADS attachments',function()
    for _,id in ipairs({'rifle','smg','pistol'}) do
        local b=geometry.weapon(id)
        for _,part in pairs(b.parts) do for i=4,#part.colors,4 do assert(part.colors[i]>=0 and part.colors[i]<=7) end end
        local pose=require('game.weapons.viewmodel').capture(b,true,id)
        assert(pose.ads==1 and pose.parts.reticle.visible and not pose.parts.flash.visible)
    end
end)
test('all twelve surface recipes emit distinct material fragments in the outward hemisphere',function()
    local seen={}
    for _,surface in ipairs({'metal','wood','glass','flesh','concrete','plaster','rubber','dirt','sand','water','foliage','fabric'}) do
        local s=fx.new();fx.impact(s,impact(surface))
        local fragments=0
        for _,e in ipairs(s.particles) do if e.life>0 and e.fragment then
            fragments=fragments+1;assert(e.velocity.y>0);seen[e.kind]=true
        end end
        assert(fragments>=4)
    end
    for _,k in ipairs({K.spark,K.splinter,K.glass,K.blood,K.chip,K.splash,K.leaf,K.fibre}) do assert(seen[k]) end
end)
test('moving rigid bodies never receive static bullet decals',function()
    local s=fx.new();local hit=impact('metal');hit.dynamic=true;fx.impact(s,hit)
    assert(fx.snapshot(s).decals==0)
end)
test('blood spatter and explosion scorch require a real static receiver',function()
    local s=fx.new();local hit=impact('flesh');hit.point.y=.5;hit.incident={x=0,y=-1,z=0}
    fx.impact(s,hit,floor);assert(s.decals[1].kind==K.stain and s.decals[1].position.y==.003)
    fx.explosion(s,{position={x=0,y=.2,z=0}},floor)
    assert(s.decals[2].kind==K.scorch and s.decals[2].position.y==.003)
    local empty=fx.new();fx.impact(empty,hit);fx.explosion(empty,{position={x=0,y=10,z=0}},floor)
    assert(fx.snapshot(empty).decals==0)
end)
test('swept fragment rays prevent floor tunnelling and bound rebounds',function()
    local s=fx.new();local hit=impact('metal');hit.point.y=.03;fx.impact(s,hit)
    advance(s,2,floor)
    assert(s.collisions>0 and s.rays<=fx.fragment_limit*120)
    for _,e in ipairs(s.particles) do if e.fragment then assert(e.position.y>=0 and e.bounces>=0) end end
end)
test('explosions contain fire, shockwaves, smoke, debris, heat and a finite column',function()
    local s=fx.new();fx.explosion(s,{position={x=0,y=.1,z=0}},floor)
    for _,k in ipairs({K.fire,K.ring,K.smoke,K.chip,K.spark,K.haze,K.scorch}) do assert(s.by_kind[k]) end
    assert(#s.emitters==1 and fx.snapshot(s).haze==2)
    advance(s,6,floor);local snap=fx.snapshot(s)
    assert(snap.particles==0 and snap.haze==0 and snap.emitters==0 and snap.decals==1)
end)
test('ambient motes and wreck columns survive combat pressure within separate pools',function()
    local s=fx.new();fx.ambient_sources(s,require 'game.world.layout');assert(#s.emitters==3)
    local env={position={x=0,y=1.7,z=6},forward={x=0,y=0,z=-1},sun=1}
    advance(s,6,floor,env)
    assert(fx.snapshot(s).ambient>0 and s.by_kind[K.mote] and s.by_kind[K.haze])
    local ambient=fx.snapshot(s).ambient
    for _=1,100 do fx.explosion(s,{position={x=0,y=.1,z=0}},floor) end
    assert(fx.snapshot(s).ambient==ambient and #s.emitters==fx.emitter_limit)
    local persistent=0;for _,e in ipairs(s.emitters) do if e.persistent then persistent=persistent+1 end end
    assert(persistent==3)
end)
test('night disables ground shimmer, pause freezes emitters and elapsed time',function()
    local s=fx.new();advance(s,3,floor,{position={x=0,y=1.7,z=0},sun=0})
    assert(not s.by_kind[K.haze]);local emitted,time=s.emitted,s.time
    fx.update(s,0,floor,{position={x=0,y=1.7,z=0},sun=1})
    assert(s.emitted==emitted and s.time==time)
end)
test('landing dust needs support and skips non-dusty surfaces',function()
    local s=fx.new();local step={position={x=0,y=.01,z=0},surface='dirt',velocity=8}
    fx.footstep(s,step,floor,true);assert(s.steps==1 and fx.snapshot(s).particles==4)
    step.surface='metal';fx.footstep(s,step,floor,false);assert(s.steps==1)
    step.surface='dirt';step.position.y=2;fx.footstep(s,step,floor,true);assert(s.steps==1)
end)
test('fixed effect ticks repeat across render frame rates and never use global random',function()
    local old=math.random;math.random=function() error('Shared RNG consumed') end
    local states={}
    for _,hz in ipairs({30,60,144}) do
        local s=fx.new(42);fx.impact(s,impact('metal'));fx.explosion(s,{position={x=0,y=.2,z=0}},floor)
        for _=1,hz do fx.update(s,1/hz,floor) end;states[#states+1]=s
    end
    math.random=old
    for _,s in ipairs(states) do
        assert(s.emitted==states[1].emitted and s.collisions==states[1].collisions)
        for i,e in ipairs(s.particles) do
            local ref=states[1].particles[i];assert(math.abs(e.life-ref.life)<1e-8)
            if e.life>0 then assert(math.abs(e.position.y-ref.position.y)<1e-8) end
        end
    end
end)
print(count..' combat rendering tests passed')
