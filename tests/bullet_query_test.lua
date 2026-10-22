-- Static-index parity through the production query adapter; no engine needed.
-- Add --benchmark for standalone Lua timings (not game frame timings).
package.path="./?.lua;"..package.path
hash=function(v) return v end
hash_to_hex=tostring
vmath={vector3=function(x,y,z) return {x=x,y=y,z=z} end,quat_rotation_x=function(x) return x end}
msg={url=function(_,id) return id end}
local native_hits,groups={},{}
bullet3d={get_world=function() return 1 end,get_gameobject_id=function(id) return id end,
    world={cast_ray=function() return native_hits end}}
physics={SHAPE_TYPE_BOX=1,set_shape=function() end,get_group=function(id) return groups[id] or "world" end}
local next_id=0
factory={create=function() next_id=next_id+1;return "object_"..next_id end}
go={delete=function() end}
resource={release=function() end}
local weapons=require "game.weapons.defold"
local world=require "game.world.defold"
local index=require "game.weapons.origin_index"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local count=0
local function test(name,fn) native_hits={};fn();count=count+1;print("PASS "..name) end
local function box(id,x,y,z,w,h,d,angle)
    return {id=id,x=x,y=y,z=z,w=w,h=h,d=d,surface="wood",rotation_x=angle}
end
local function equal(a,b)
    assert(type(a)==type(b))
    if type(a)~="table" then assert(a==b,tostring(a).." != "..tostring(b));return end
    for k,v in pairs(a) do equal(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil) end
end
local function hits(query,p,d,length)
    local result=query:segment(p,d,length or 10)
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
local function queries(registry,grid,others)
    local registries={registry}
    for _,r in ipairs(others or {}) do registries[#registries+1]=r end
    local indices={[registry]=grid}
    return weapons.query(registries,{origin_indices=indices}),weapons.query(registries),registries,indices
end

test("cell edges, negative coordinates, rotated ramps and overlapping solids preserve exact intervals",function()
    local registry,grid={},index.new()
    for i,s in ipairs({box("edge",2,0,-2,4,2,4),box("negative",-6,0,-6,4,2,4),
        box("ramp",4,0,4,2,8,.3,math.pi/4),box("overlap",2,0,-2,4,2,4)}) do
        registry[i]=s;index.add(grid,i,s)
    end
    local indexed,full=queries(registry,grid)
    local accepted=0
    for _,s in pairs(registry) do
        local transform=T.rotation(s.rotation_x or 0,0,0)
        transform[4],transform[8],transform[12]=s.x,s.y,s.z
        for _,axis in ipairs({"x","y","z"}) do for _,sign in ipairs({-1,1}) do
            for _,epsilon in ipairs({-.01,0,.5e-7,1.5e-7}) do
                local p={x=0,y=0,z=0};p[axis]=sign*((axis=="x" and s.w or axis=="y" and s.h or s.d)/2+epsilon)
                local d={x=0,y=0,z=0};d[axis]=-sign
                p,d=T.point(transform,p),T.direction(transform,d)
                local expected=hits(full,p,d);accepted=accepted+#expected
                equal(hits(indexed,p,d),expected)
            end
        end end
    end
    assert(accepted>50)
    equal(hits(indexed,{x=1000,y=0,z=1000},{x=0,y=0,z=-1}),{})
end)

test("native ray hits outside the origin cell remain present and inside hits are not duplicated",function()
    local registry,grid={},index.new()
    registry.inside=box("inside",0,0,0,1,1,1)
    registry.far=box("far",0,0,-12,1,1,1)
    for id,s in pairs(registry) do index.add(grid,id,s) end
    native_hits={{object="inside",fraction=0},{object="far",fraction=.5},
        {object="unregistered",fraction=.8,normal={x=0,y=0,z=1}},
        {object="filtered",fraction=.9,normal={x=0,y=0,z=1}}}
    groups.filtered="player"
    local indexed,full=queries(registry,grid)
    local actual=hits(indexed,{x=0,y=0,z=0},{x=0,y=0,z=-1},20)
    equal(actual,hits(full,{x=0,y=0,z=0},{x=0,y=0,z=-1},20))
    assert(#actual==3)
    native_hits={};registry.inside.disabled=true
    assert(#hits(indexed,{x=0,y=0,z=0},{x=0,y=0,z=-1})==0)
end)

test("moving registry replacements and later registries are observed without rebuilding the grid",function()
    local static,grid,dynamic={},index.new(),{}
    local indexed,full,registries,indices=queries(static,grid,{dynamic})
    local d={x=0,y=0,z=-1}
    for step=1,3 do
        local p={x=step*10,y=2,z=step*8}
        local s=box("limb",p.x,p.y,p.z,1,2,1)
        s.transform=T.root(p,step*.4);s.actor="enemy_1";s.region="head";s.damage_scale=4
        dynamic.limb=s
        local actual=hits(indexed,p,d);equal(actual,hits(full,p,d));assert(#actual==1 and actual[1].actor=="enemy_1")
        equal(hits(indexed,{x=0,y=2,z=0},d),{})
    end
    dynamic.limb.disabled=true
    equal(hits(indexed,{x=30,y=2,z=24},d),{})
    dynamic.limb=nil
    local later={cover=box("cover",0,0,0,1,1,1)}
    registries[#registries+1]=later
    assert(#hits(indexed,{x=0,y=0,z=0},d)==1)
    indices[later]=index.new();index.add(indices[later],"cover",later.cover)
    equal(hits(indexed,{x=0,y=0,z=0},d),hits(full,{x=0,y=0,z=0},d))
end)

test("world loading updates an existing query and teardown clears its static candidates",function()
    local revision=require 'game.world.collision_revision'
    revision.advance_frame();revision.advance_frame()
    local before=revision.current()
    local adapter=world.new("mesh","collision")
    local query=queries(adapter.by_id,adapter.origin_index)
    local p,d={x=0,y=0,z=0},{x=0,y=0,z=-1}
    assert(#hits(query,p,d)==0)
    world.add_collision(adapter,box("loaded",0,0,0,2,2,2))
    assert(revision.current()==nil)
    revision.advance_frame();assert(revision.current()==nil)
    revision.advance_frame();assert(revision.current()~=before)
    assert(#hits(query,p,d)==1)
    local grid=adapter.origin_index
    world.final(adapter)
    assert(revision.current()==nil)
    assert(next(grid.cells)==nil and #hits(query,p,d)==0)
end)

test("non-unit directions retain the full-scan entry tolerance",function()
    local registry={edge=box("edge",2,0,0,4,2,2)}
    local grid=index.new();index.add(grid,"edge",registry.edge)
    local indexed,full=queries(registry,grid)
    local p,d={x=4.00001,y=0,z=0},{x=-1000,y=0,z=0}
    local actual=hits(indexed,p,d);equal(actual,hits(full,p,d));assert(#actual==1)
end)

test("generated market matches a full scan while rejecting distant static candidates",function()
    local layout=require "game.world.layout"
    local registry,grid,points={},index.new(),{}
    local job=coroutine.create(function() require("game.world.recipes").generate(layout,true,layout.seed) end)
    local total=0
    while coroutine.status(job)~="dead" do
        local ok,s=coroutine.resume(job);assert(ok,s)
        if s and s.surface then
            registry[s.id]=s;index.add(grid,s.id,s);total=total+1
            points[#points+1]={p={x=s.x,y=s.y,z=s.z},d={x=0,y=0,z=-1}}
            points[#points+1]={p={x=s.x+s.w/2+.5e-7,y=s.y,z=s.z},d={x=-1,y=0,z=0}}
        end
    end
    for _,n in ipairs(require("game.world.generator").new(layout).navigation.nodes) do
        points[#points+1]={p={x=n.x,y=n.y+1.5,z=n.z},d={x=0,y=0,z=-1}}
    end
    local random=require("game.rng").new(layout.seed,"performance-probe")
    for _=1,1000 do
        local p={x=(random()-.5)*100,y=random()*16,z=-70+random()*130}
        local d=V.normalize({x=random()-.5,y=random()-.5,z=random()-.5})
        points[#points+1]={p=p,d=d}
    end
    local indexed,full=queries(registry,grid)
    local candidates=0
    for _,q in ipairs(points) do
        equal(hits(indexed,q.p,q.d),hits(full,q.p,q.d))
        for _ in pairs(index.candidates(grid,q.p,q.d)) do candidates=candidates+1 end
    end
    assert(total>1000 and candidates/#points<total*.05)
    print(string.format("  %d colliders, %d origins, %.2f average candidates (%.2f%% fewer checks)",
        total,#points,candidates/#points,100*(1-candidates/(#points*total))))
    if arg[1]=="--benchmark" then
        local function bench(query)
            collectgarbage("collect")
            local start=os.clock();local found=0
            for _=1,3 do for _,q in ipairs(points) do found=found+#query:segment(q.p,q.d,10) end end
            return (os.clock()-start)*1000,found
        end
        for trial=1,3 do
            local a,ac=bench(full);local b,bc=bench(indexed);assert(ac==bc)
            print(string.format("  Trial %d: full %.3f ms, indexed %.3f ms, %.2fx; %d queries (Lua only, native rays stubbed)",
                trial,a,b,a/b,#points*3))
        end
    end
end)
print(count.." bullet query tests passed")
