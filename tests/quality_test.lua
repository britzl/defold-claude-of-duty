local Q=require 'game.render.quality'
local S=require 'game.render.settings'
local FX=require 'game.render.combat_fx'
local shadows=require 'game.render.shadows'
local n=0
local function test(name,f) f();n=n+1;print('PASS '..name) end
local function drive(s,seconds,fps,active)
    for _=1,math.ceil(seconds*fps) do Q.sample(s,1/fps,active~=false) end
end
test('all presets are valid and independent; quality never owns gameplay fields',function()
    for _,name in ipairs(Q.names) do
        local p=Q.preset(name);S.configure(S.defaults(),p)
        p.shadows=false;assert(Q.preset(name).shadows)
        assert(not Q.owns('fov') and not Q.owns('hour') and not Q.owns('damage_scale'))
        assert(p.local_shadow_cache and Q.owns('local_shadow_cache'))
    end
    for _,v in ipairs({{render_scale=0/0},{render_scale=2},{shadow_resolution=768},{decal_limit=1.5},{material_lod=-1}}) do
        assert(not pcall(S.configure,S.defaults(),v))
    end
end)
test('manual modes never adapt; invalid mode leaves state intact',function()
    local s=Q.new('ultra');drive(s,100,20)
    assert(s.mode=='ultra' and s.active=='ultra' and s.changes==0)
    assert(not pcall(Q.select,s,'bogus'));assert(s.mode=='ultra')
end)
test('sustained slow frames lower tiers; low is a hard floor',function()
    local s=Q.new();drive(s,40,30)
    assert(s.active=='low' and s.changes==2)
    drive(s,120,20);assert(s.active=='low' and s.changes==2)
end)
test('a short hitch and alternating marginal frames do not oscillate',function()
    local s=Q.new();drive(s,6,60);Q.sample(s,.2,true);drive(s,10,60)
    assert(s.active=='high')
    for _=1,10 do drive(s,2,56);drive(s,2,60) end
    assert(s.active=='high' and s.changes==0)
end)
test('healthy capped frames probe up; failed probe has long backoff',function()
    local s=Q.new();drive(s,30,60);assert(s.active=='ultra')
    drive(s,8,30);assert(s.active=='high')
    local count=s.changes;drive(s,100,60);assert(s.active=='high' and s.changes==count)
    drive(s,200,60);assert(s.active=='ultra')
end)
test('loading, pause, focus, capture and invalid clock samples reset pending decisions',function()
    local s=Q.new();drive(s,7.5,30);drive(s,40,10,false)
    assert(s.active=='high' and s.changes==0)
    for _,v in ipairs({0,-1,0/0,math.huge,2}) do Q.sample(s,v,true) end
    drive(s,3,30);assert(s.active=='high')
end)
test('manual custom freezes current tier; Defaults restores Auto and High',function()
    local s=Q.new('low');Q.select(s,'custom');drive(s,60,120)
    assert(s.mode=='custom' and s.active=='low')
    local p=Q.select(s,'auto');assert(s.active=='high' and s.mode=='auto' and p.render_scale==1)
end)
test('internal resolution stays bounded and scales target costs',function()
    local previous=0
    for _,name in ipairs(Q.names) do
        local o=S.configure(S.defaults(),Q.preset(name));local d=S.dimensions(1280,720,o.render_scale)
        local bytes=S.target_bytes(d.width,d.height,true,false,o)
        assert(bytes>previous);previous=bytes
    end
    assert(S.dimensions(1,1,.6).width==1)
    assert(not S.dimensions(0,720,.6))
end)
test('cascade viewports, snapping and atlas texels agree at every resolution',function()
    for _,size in ipairs({256,512,1024,2048}) do
        local fits=shadows.fit({0,2,0},{0,0,-1},1,.7,{.4,.8,.3},nil,nil,size)
        for i,f in ipairs(fits) do
            assert(f.viewport[3]==size and f.viewport[4]==size)
            assert(f.viewport[1]+size<=size*2 and f.viewport[2]+size<=size*2)
            assert(math.abs(f.texel-2*f.radius/size)<1e-10)
        end
    end
end)
test('FX quotas survive pressure, lowering tier and raising tier without new pools',function()
    local s=FX.new();local particles=s.particles
    for _,name in ipairs({'high','low','medium','ultra','low'}) do
        local p=Q.preset(name);FX.configure(s,p)
        for i=1,80 do
            FX.impact(s,{point={x=0,y=0,z=0},surface='concrete'})
            FX.explosion(s,{position={x=0,y=0,z=0}})
        end
        local r=FX.snapshot(s)
        assert(r.particles<=math.ceil(80*p.effect_density)+math.ceil(48*p.effect_density))
        assert(r.decals<=p.decal_limit and (p.heat_distortion or r.haze==0))
        assert(s.particles==particles and #s.particles==128)
    end
end)
print(n..' quality tests passed')
