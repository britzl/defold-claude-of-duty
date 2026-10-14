local fx=require 'game.render.combat_fx'
local geometry=require 'game.weapons.geometry'
local count=0
local function test(name,fn) fn();count=count+1;print('PASS '..name) end
local function impact(surface,x)
    return {point={x=x or 0,y=0,z=0},normal={x=0,y=1,z=0},surface=surface or 'concrete'}
end
test('impact pools stay bounded and replace the oldest marks',function()
    local state=fx.new()
    for i=1,100 do fx.impact(state,impact('concrete',i)) end
    local s=fx.snapshot(state)
    assert(s.particles==24 and s.decals==32 and #state.particles==24 and #state.decals==32)
    for _,e in ipairs(state.decals) do assert(e.position.x>=69 and e.normal.y==1 and e.position.y>.0) end
end)
test('smoke grows, fades and expires while static marks retain their plane',function()
    local s=fx.new();fx.impact(s,impact())
    local smoke,mark=s.particles[1],s.decals[1]
    local size=fx.appearance(smoke)
    fx.update(s,.3)
    assert(fx.appearance(smoke)>size and smoke.position.y>.008)
    assert(mark.position.y==.003)
    fx.update(s,1);assert(fx.snapshot(s).particles==0 and fx.snapshot(s).decals==1)
    fx.update(s,18);assert(fx.snapshot(s).decals==0)
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
    fx.update(s,.06);assert(fx.snapshot(s).particles==2)
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
print(count..' combat rendering tests passed')
