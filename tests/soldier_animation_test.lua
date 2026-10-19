package.path="./?.lua;"..package.path
local rig=require "game.ai.rig"
local geo=require "game.ai.geometry"
local variants=require "game.ai.variants"
local animation=require "game.ai.animation"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local runtime=require "game.runtime"
local ai=require "game.systems.ai"
local combat=require "game.combat"
local count=0
local function test(name,f) f();count=count+1;print("PASS "..name) end
local function near(a,b,t) assert(math.abs(a-b)<(t or 1e-6),a.." != "..b) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function actor(variant)
    local e={variant=variant or "vanguard",actor={alive=true,health=100,max_health=100},position={x=0,y=0,z=0},yaw=0,phase=0,run=0}
    animation.init(e);return e
end
local function floor(height)
    return {ray=function(_,p) local y,n=height(p.x,p.z);if y then return {x=p.x,y=y,z=p.z,nx=n and n.x or 0,ny=n and n.y or 1,nz=n and n.z or 0} end end}
end
local function state(e,extra)
    local s=animation.sample(e);s.phase=e.phase;s.walk=e.walk or 0;s.crouch=e.crouch or 0;s.time=e.time or 0
    for k,v in pairs(extra or {}) do s[k]=v end;return s
end
local function rigid(matrix)
    for _,v in ipairs(matrix) do assert(v==v and math.abs(v)<1e5) end
    local x={x=matrix[1],y=matrix[5],z=matrix[9]};local y={x=matrix[2],y=matrix[6],z=matrix[10]};local z={x=matrix[3],y=matrix[7],z=matrix[11]}
    near(T.dot(x,x),1);near(T.dot(y,y),1);near(T.dot(z,z),1);near(T.dot(x,y),0);near(T.dot(T.cross(x,y),z),1)
end

test("three source variants retain common joints but distinct anatomy, gear, weapons and bounded meshes",function()
    local sizes={};local total=0
    for _,name in ipairs(variants.order) do
        local b=geo.build(name);sizes[name]=b;total=total+b.bytes
        assert(b.vertex_count<15000 and #b.joints==b.vertex_count*4 and #b.normals==b.vertex_count*3)
        for i=1,b.vertex_count do
            local sum=0
            for j=1,4 do local at=(i-1)*4+j;sum=sum+b.weights[at];assert(b.joints[at]>=0 and b.joints[at]<25) end
            near(sum,1)
        end
        for i=1,#b.positions,9 do
            local p=b.positions
            local a={x=p[i+3]-p[i],y=p[i+4]-p[i+1],z=p[i+5]-p[i+2]}
            local c={x=p[i+6]-p[i],y=p[i+7]-p[i+1],z=p[i+8]-p[i+2]}
            assert(T.dot(T.cross(a,c),{x=b.normals[i],y=b.normals[i+1],z=b.normals[i+2]})>1e-10,name.." winding")
        end
        print("RESOURCE",name,b.vertex_count,b.bytes)
    end
    assert(sizes.vanguard.positions[2]~=sizes.irregular.positions[2] and sizes.vanguard.colors[1]~=sizes.breacher.colors[1])
    assert(total<3*1024*1024)
    assert(variants.irregular.scale==.985 and variants.breacher.bulk==1.06)
    assert(variants.muzzle("irregular").z<variants.muzzle("vanguard").z)
end)

test("full clip matrix keeps rigid joints, exact hand attachment and scaled hit volumes",function()
    for _,name in ipairs(variants.order) do for _,clip in ipairs({"idle","walk","run","crouch","reload","vault","wounded","head","arm","leg","torso"}) do
        local scratch={}
        for i=0,40 do
            local t=i/40;local s={variant=name,time=t,phase=t*math.pi*2,aim=1,pitch=math.sin(t*6)*.6,aim_yaw=math.cos(t*6)*.75}
            if clip=="walk" or clip=="run" then s.walk=1;s.run=clip=="run" and 1 or 0 end
            if clip=="crouch" then s.walk=1;s.crouch=1 end
            if clip=="reload" or clip=="vault" then s[clip]=t;s[clip.."_weight"]=1 end
            if clip=="wounded" then s.wounded=1 end
            if clip=="head" or clip=="arm" or clip=="leg" or clip=="torso" then s.hit_region=clip;s.hit=.6;s.hit_side=i%2==0 and 1 or -1 end
            local palette,worlds=rig.pose(s,scratch)
            assert(scratch.support_error<1e-5,name.." "..clip.." detached support hand "..scratch.support_error)
            local scale=variants.get(name).scale
            for j,bone in ipairs(rig.bones) do
                rigid(palette[j]);rigid(worlds[j])
                local origin=T.point(palette[j],{x=bone.bind.x*scale,y=bone.bind.y*scale,z=bone.bind.z*scale})
                near(distance(origin,T.origin(worlds[j])),0)
                if bone.parent>0 then
                    local expected=V.length(bone.local_position)*scale
                    near(distance(T.origin(worlds[j]),T.origin(worlds[bone.parent])),expected)
                end
            end
            local volumes=rig.volumes(palette,{x=0,y=0,z=0},0,"fixture",name)
            assert(#volumes==11);near(volumes[1].h,.26*scale)
            for _,volume in ipairs(volumes) do rigid(volume.transform) end
        end
    end end
end)

test("reload hand visits magazine and chest then returns to the exact support socket",function()
    local scratch={};rig.pose({reload=.42,reload_weight=1},scratch)
    local chest=scratch.worlds[rig.index.Spine2]
    local pouch=T.point(chest,{x=.02,y=-.155,z=-.164})
    near(distance(T.origin(scratch.worlds[rig.index.HandL]),pouch),0)
    for _,t in ipairs({0,1}) do
        rig.pose({reload=t,reload_weight=1},scratch)
        near(distance(T.origin(scratch.worlds[rig.index.HandL]),T.point(scratch.weapon_frame,variants.support())),0)
    end
end)

test("vault support target stays reachable throughout the constrained aim arc",function()
    for _,pitch in ipairs({-.6,-.2,.2,.6}) do for _,yaw in ipairs({-.75,-.15,.15,.75}) do
        for i=0,20 do
            local scratch={};rig.pose({aim=1,pitch=pitch,aim_yaw=yaw,vault=i/20,vault_weight=1},scratch)
            assert(scratch.support_error<1e-5)
        end
    end end
end)

test("terrain IK plants both feet on uneven ground and lowers the pelvis without stretching",function()
    for _,name in ipairs(variants.order) do
        local e=actor(name);local scale=variants.get(name).scale
        local q=floor(function(x) return x<0 and -.18 or .12,{x=.12,y=math.sqrt(1-.12^2),z=0} end)
        for _=1,60 do animation.step(e,1/120,q) end
        local s=state(e);local scratch={};local _,worlds=rig.pose(s,scratch)
        assert(s.pelvis<-.17)
        for _,side in ipairs({"R","L"}) do
            local foot=T.origin(worlds[rig.index["Foot"..side]])
            near(foot.y,(side=="R" and .12 or -.18)+.088*scale)
            near(worlds[rig.index["Foot"..side]][6],math.sqrt(1-.12^2))
        end
    end
end)

test("walking and running stance feet stay fixed in world space across complete strides",function()
    for _,speed in ipairs({1.1,2.2}) do
        local e=actor();e.walk=1;e.run=speed>2 and 1 or 0
        local q=floor(function() return 0 end);local previous={};local planted=0;local lifted=0
        for tick=1,360 do
            e.position.z=e.position.z-speed/120;e.phase=e.phase+(speed/120)*2*math.pi/(1.25+.45*e.run)
            animation.step(e,1/120,q);local s=state(e);local _,worlds=rig.pose(s)
            for _,side in ipairs({"R","L"}) do
                local p=T.point(T.root(e.position,e.yaw),T.origin(worlds[rig.index["Foot"..side]]))
                local f=s.feet[side]
                if f.stance and previous[side] and previous[side].stance then
                    near(distance(p,previous[side].p),0,1e-5);planted=planted+1
                end
                if not f.stance and p.y>.12 then lifted=lifted+1 end
                previous[side]={p=p,stance=f.stance}
            end
        end
        assert(planted>100 and lifted>30)
    end
end)

test("crouch locomotion advances the legs while stationary crouch and wounded feet remain planted",function()
    local e=actor();e.crouch=1;local q=floor(function() return 0 end)
    animation.step(e,1/120,q)
    for _,hurt in ipairs({0,1}) do
        local _,worlds=rig.pose(state(e,{wounded=hurt}))
        near(worlds[rig.index.FootR][8],.088);near(worlds[rig.index.FootL][8],.088)
    end
    e.walk=1;local before
    for i=1,200 do
        e.position.z=e.position.z-.65/120;e.phase=e.phase+.65/120*2*math.pi/1.25
        animation.step(e,1/120,q);local _,worlds=rig.pose(state(e))
        if i==1 then before=T.origin(worlds[rig.index.LegR]) end
        if i==150 then assert(distance(before,T.origin(worlds[rig.index.LegR]))>.04) end
    end
end)

test("turning steps lift a trailing foot and hold the other while the body rotates",function()
    local e=actor();local q=floor(function() return 0 end);animation.step(e,1/120,q)
    animation.turn(e,1)
    local max_y=0
    for i=1,50 do
        e.yaw=e.yaw+.008;animation.step(e,1/120,q)
        local _,worlds=rig.pose(state(e));max_y=math.max(max_y,worlds[rig.index.FootR][8])
    end
    assert(max_y>.15)
end)

test("steep walls, missing support, teleports and repeated clip changes remain finite",function()
    local e=actor();local q=floor(function() return nil end)
    for i=1,40 do
        if i%5==0 then e.position.x=e.position.x+20;e.yaw=e.yaw+2;animation.vault(e,.1) end
        animation.step(e,1/120,q)
        local palette=rig.pose(state(e));for _,m in ipairs(palette) do rigid(m) end
        assert(e.animation.targets.R.weight==0)
    end
    q=floor(function() return 0,{x=1,y=0,z=0} end);animation.step(e,1/120,q)
    assert(e.animation.targets.L.weight==0)
end)

test("regional damage drives bounded sided reactions and health drives wounded pose",function()
    local ctx=runtime.new();ctx.world.ready=true;local e=ai.reset(ctx,{x=0,y=0,z=0},0)
    for _,case in ipairs({{"head","head",1},{"arm","forearm_l",-1},{"leg","shin_r",1},{"torso","chest",1}}) do
        combat.request(ctx.combat,{target=e.id,amount=16,source="fixture",region=case[1],part=case[2],from={x=1,y=0,z=0}})
        combat.fixed_update(ctx,1/120);animation.step(e,.08,floor(function() return 0 end))
        local s=state(e);assert(s.hit_region==case[1] and s.hit_side==case[3] and s.hit>0)
    end
    assert(animation.sample(e).wounded>0)
    animation.step(e,.6,floor(function() return 0 end));assert(animation.sample(e).hit==0)
    runtime.final(ctx)
end)

test("one-shot clocks reject overlap, complete cleanly and stop on death",function()
    local e=actor();assert(animation.reload(e,2));assert(not animation.reload(e,1))
    assert(animation.vault(e,.8));assert(e.animation.reload_time==-1 and not animation.reload(e))
    animation.step(e,1,nil);assert(e.animation.vault_time==-1)
    assert(animation.reload(e));e.actor.alive=false;animation.step(e,.1,nil)
    assert(e.animation.reload_time==-1 and e.animation.vault_time==-1)
    assert(not animation.reload(e) and not animation.vault(e))
    local s=animation.interpolate({reload=.99,reload_weight=1},{reload=0,reload_weight=0},.5)
    near(s.reload,.995)
end)

test("constrained aim cannot overtwist spine or head at extreme input",function()
    local a=rig.pose({aim=1,pitch=100,aim_yaw=-100})
    local b=rig.pose({aim=1,pitch=.6,aim_yaw=-.75})
    for i=1,25 do for j=1,12 do near(a[i][j],b[i][j]) end end
end)

test("physics joint frames reconstruct every animated render frame without a death handoff pop",function()
    local _,worlds=rig.pose({variant="breacher",walk=1,phase=2,crouch=.3,aim=1,pitch=-.4,hit=.4,hit_region="arm"})
    local frames=rig.joint_frames(worlds)
    for i,f in ipairs(frames) do
        rigid(f.world);rigid(f.render_from_joint)
        local actual=T.mul(f.world,f.render_from_joint)
        for k=1,12 do near(actual[k],worlds[i][k]) end
        if f.parent_local then
            local linked=T.mul(frames[rig.bones[i].parent].world,f.parent_local)
            for k=1,12 do near(linked[k],f.world[k]) end
        end
    end
end)

test("terrain, reload and reactive poses agree at 30, 60 and 144 FPS without presentation changing simulation",function()
    local function simulate(fps)
        local e=actor("irregular");e.walk=1
        local q=floor(function(x,z) return math.sin(z)*.07,{x=0,y=1/math.sqrt(1+.07^2*math.cos(z)^2),z=-.07*math.cos(z)/math.sqrt(1+.07^2*math.cos(z)^2)} end)
        local tick=0;local previous=state(e);local scratch={}
        for frame=1,fps*2 do
            while (tick+1)/120<=frame/fps+1e-9 do
                previous=state(e);tick=tick+1
                e.position.z=-tick*1.1/120;e.phase=e.phase+1.1/120*2*math.pi/1.25
                if tick==70 then animation.reload(e,1) end
                if tick==120 then animation.hit(e,{region="leg",part="shin_l",amount=20}) end
                animation.step(e,1/120,q)
            end
            local before=state(e);local actual=rig.pose(before)
            rig.pose(animation.interpolate(previous,before,(frame/fps-tick/120)*120),scratch)
            local after=rig.pose(state(e))
            for i=1,25 do for k=1,12 do near(actual[i][k],after[i][k]) end end
        end
        return rig.pose(state(e))
    end
    local a=simulate(30)
    for _,fps in ipairs({60,144}) do
        local b=simulate(fps);for i=1,25 do for k=1,12 do near(a[i][k],b[i][k]) end end
    end
end)
print(count.." soldier animation tests passed")
