-- Compare the submitted scene with the original unconditional presentation
-- formulas, and check that unchanged frames issue no redundant engine writes.
local fx=require 'game.render.combat_fx'
local V=require 'game.weapons.math'
local events=require 'game.events'
math.atan2=math.atan2 or math.atan
local function copy(v)
    if type(v)~='table' then return v end
    local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
end
local quat={}
function quat.__mul(a,b)
    return setmetatable({x=a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
        y=a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,z=a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,
        w=a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z},quat)
end
vmath={
    vector3=function(x,y,z) return {x=x,y=y,z=z} end,
    vector4=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end,
    quat=function(x,y,z,w) return setmetatable({x=x,y=y,z=z,w=w},quat) end,
    quat_rotation_z=function(t) return setmetatable({x=0,y=0,z=math.sin(t/2),w=math.cos(t/2)},quat) end,
    conj=function(q) return setmetatable({x=-q.x,y=-q.y,z=-q.z,w=q.w},quat) end,
    length=V.length,
}
vmath.rotate=function(q,v) return q*vmath.quat(v.x,v.y,v.z,0)*vmath.conj(q) end
local scene,writes={},{}
local function node(id) scene[id]=scene[id] or {visible=false};return scene[id] end
local function write(id,key,value) node(id)[key]=copy(value);writes[key]=(writes[key] or 0)+1 end
go={set_position=function(v,id) write(id,'position',v) end,
    set_rotation=function(v,id) write(id,'rotation',v) end,
    set_scale=function(v,id) write(id,'scale',v) end,set=function(id,key,v) write(id,key,v) end}
msg={post=function(id,message,data)
    if id=='@render:' then write(id,'haze',data.haze) else write(id,'visible',message=='enable') end
end}
local depth=0
profiler={scope_begin=function() depth=depth+1 end,scope_end=function() depth=depth-1;assert(depth>=0) end}
local visual=require 'game.render.combat_fx_defold'
local function adapter(seed)
    local a={state=fx.new(seed),parts={},pending={},ctx={world={ready=true,seed=seed,layout={}},events=events.new()}}
    for _,group in ipairs({'particles','ambient','decals','haze'}) do
        for i=1,#a.state[group] do
            local id=group..'/'..i
            a.parts[#a.parts+1]={id=id,url=id,group=group,index=i,visible=false}
        end
    end
    return a
end
local function near(a,b,label)
    if type(b)=='table' then for k,v in pairs(b) do near(a and a[k],v,label..'.'..k) end
    elseif type(b)=='number' then assert(type(a)=='number' and math.abs(a-b)<1e-12,label..': '..tostring(a)..' != '..b)
    else assert(a==b,label..' differs') end
end
local camera=vmath.quat(0,0,0,1)
local muzzle,eye={x=0,y=1,z=0},{x=0,y=1.7,z=3}
local function check(a,dt,capture,enabled)
    writes={};visual.update(a,dt,camera,muzzle,capture,enabled,eye,1);assert(depth==0)
    local state=a.fixture or a.state
    local show=enabled and (not capture or a.fixture~=nil)
    local haze=0
    for _,part in ipairs(a.parts) do
        local e=state[part.group][part.index];local shown=show and e.life>0
        near(node(part.id).visible,shown,part.id..'.visible')
        if shown then
            local size,opacity=fx.appearance(e)
            local q=camera
            if e.decal then local r=V.forward_rotation(e.normal);q=vmath.quat(r.x,r.y,r.z,r.w) end
            local angle=e.seed*6.2831853+e.spin*(e.duration-e.life)
            local stretch=1
            if e.kind==fx.kind.spark then
                local v=vmath.rotate(vmath.conj(camera),vmath.vector3(e.velocity.x,e.velocity.y,e.velocity.z))
                angle=math.atan2(v.y,v.x);stretch=1+math.min(12,vmath.length(v)*.8)
            end
            local actual=node(part.id)
            near(actual.position,e.position,part.id..'.position')
            near(actual.rotation,q*vmath.quat_rotation_z(angle),part.id..'.rotation')
            near(actual.scale,{x=size*stretch,y=size,z=size},part.id..'.scale')
            near(actual.particle,{x=e.kind,y=opacity,z=e.seed,w=1-e.life/e.duration},part.id..'.particle')
            if part.group~='haze' then
                near(actual.tint,{x=e.colour[1],y=e.colour[2],z=e.colour[3],w=e.variant or 0},part.id..'.tint')
            else haze=haze+1 end
        end
    end
    near(node('@render:').haze,haze,'haze')
    return writes
end
local count=0
local function test(name,fn) fn();count=count+1;print('PASS '..name) end
local a=adapter(42)
for _,surface in ipairs({'metal','wood','concrete','glass','flesh'}) do
    fx.impact(a.state,{surface=surface,point={x=.3,y=.2,z=0},normal={x=0,y=1,z=0}})
end
fx.explosion(a.state,{position={x=1,y=.5,z=0}})
fx.column(a.state,{x=2,y=0,z=0},true)
local snapshot=fx.snapshot
fx.snapshot=function() error('Presentation must not build diagnostic snapshots') end
test('all effect kinds match unconditional presentation; frozen frames submit nothing',function()
    local first=check(a,0,false,true);assert(first.position and first.tint and first.particle)
    local repeated=check(a,0,false,true);assert(next(repeated)==nil)
    assert(next(check(a,1/120,false,true))==nil,'No effect tick should mean no repeated submissions')
    local advanced=check(a,1/120,false,true);assert(advanced.position and advanced.particle and not advanced.tint)
end)
test('camera-only changes rotate billboards and spark projections while retaining decal planes',function()
    local before=copy(scene['decals/1'].rotation)
    camera.x,camera.y,camera.z,camera.w=0,math.sin(.3),0,math.cos(.3)
    local changed=check(a,0,false,true)
    assert(changed.rotation and not changed.position and not changed.tint and not changed.particle)
    near(scene['decals/1'].rotation,before,'decal plane')
    assert(next(check(a,0,false,true))==nil)
end)
test('in-place edits to every submitted input invalidate the appropriate values',function()
    local e=a.state.particles[1]
    for key,value in pairs({life=.21,duration=.8,size=.4,growth=4,opacity=.3,seed=.9,spin=2,variant=3}) do
        e[key]=value;check(a,0,false,true)
    end
    e.position.x=e.position.x+.01;e.colour[1]=.13;check(a,0,false,true)
    e.kind=fx.kind.spark;e.velocity={x=1,y=2,z=3};check(a,0,false,true)
    e.velocity.y=-2;check(a,0,false,true)
    e.decal=true;e.normal={x=1,y=0,z=0};check(a,0,false,true)
    e.normal.x=0;e.normal.z=-1;check(a,0,false,true)
    e.decal=nil;e.kind=fx.kind.smoke;check(a,0,false,true)
    local mark=a.state.decals[1];mark.normal={x=.1,y=.9,z=.2};mark.size=.27;check(a,0,false,true)
end)
test('hidden effects reappear with the latest camera, material and geometry',function()
    check(a,0,false,false)
    camera=vmath.quat_rotation_z(.8);check(a,0,false,false)
    a.state.particles[1].position.z=3;a.state.particles[1].colour={.8,.7,.6}
    check(a,0,false,true)
    local expired=a.state.particles[1];expired.life=0;check(a,0,false,true)
    for i=1,150 do fx.fire(a.state,{x=i,y=1,z=-i},{x=0,y=0,z=-1},true) end
    check(a,0,false,true)
end)
test('pending muzzle events, fixtures, quality changes and resets preserve ownership',function()
    local pending=a.pending
    pending[1]={x=0,y=0,z=-1};pending[2]={x=1,y=0,z=0}
    local shots=a.state.shots
    check(a,0,true,true);assert(#a.pending==2)
    check(a,0,false,true);assert(a.state.shots==shots+2 and #a.pending==0 and a.pending==pending)
    visual.fixture(a,true);check(a,0,true,true);assert(next(check(a,0,true,true))==nil)
    visual.fixture(a,false);check(a,0,false,true)
    visual.configure(a,{effect_density=.5,decal_limit=8,heat_distortion=false});check(a,0,false,true)
    visual.reset(a);check(a,0,false,true)
    fx.fire(a.state,muzzle,{x=0,y=0,z=-1},true);check(a,0,false,true)
end)
test('multiple rendered frames per tick remain identical through motion and expiry',function()
    for i=1,360 do
        if i%17==0 then camera=vmath.quat_rotation_z(i*.01) end
        check(a,1/144,false,true)
        assert(next(check(a,0,false,true))==nil)
    end
end)
fx.snapshot=snapshot
print(count..' combat presentation tests passed')
