-- Exercise partial uploads without publishing incomplete geometry.
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
hash=function(v) return v end
hash_to_hex=tostring
vmath={vector3=function(x,y,z) return {x=x,y=y,z=z} end,
    vector4=function(...) return {...} end}
msg={url=function(_,id,component) return id.."/"..component end}
local created,released,resources,properties=0,0,{},{}
factory={create=function() created=created+1;return created end}
resource={create_buffer=function(path,params) resources[path]=params.buffer;return path end,
    release=function(path) assert(resources[path]);released=released+1;resources[path]=nil end}
go={set=function(url,key,value) properties[url..":"..key]=value end,delete=function() end}
buffer={VALUE_TYPE_FLOAT32=1}
function buffer.create(n,declarations)
    local data={n=n,streams={}}
    for _,d in ipairs(declarations) do
        data.streams[d.name]=setmetatable({},{__newindex=function(t,k,v)
            assert(k>=1 and k<=n*d.count and type(v)=="number");rawset(t,k,v)
        end})
    end
    return data
end
buffer.get_stream=function(data,name) return assert(data.streams[name]) end
buffer.set_metadata=function(data,_,value) data.bounds=value end
local adapter=require "game.world.defold"
local function clone(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=clone(v) end;return result
end
local function equal(a,b)
    assert(type(a)==type(b))
    if type(a)~="table" then assert(a==b);return end
    for k,v in pairs(a) do equal(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil) end
end
local function batch(glass,override)
    local b={vertex_count=7,material=glass and "glass" or "concrete",glass=glass,
        centre={x=10,y=-3,z=5},bounds={9,-4,4,11,-2,6},positions={},normals={},colors={},edges={},masks={}}
    if not glass and not override then b.surfaces={} end
    if override then b.surface={3,0,0,0} end
    for i=1,21 do b.positions[i]=i*.125;b.normals[i]=i%3-1 end
    for i=1,28 do b.colors[i]=i*.01;b.edges[i]=i*.02;b.masks[i]=i*.03 end
    if b.surfaces then for i=1,14 do b.surfaces[i]=i*.1 end end
    return b
end
for _,case in ipairs({{name="opaque"},{name="glass",glass=true},{name="surface override",override=true}}) do
    test(case.name.." sliced and immediate uploads have identical streams and bounds",function()
        local a,b=adapter.new("#world_mesh"),adapter.new("#world_mesh")
        local first=batch(case.glass,case.override);local second=clone(first)
        adapter.add_batch(a,first)
        local before=created
        assert(not adapter.step_batch(b,second,2))
        assert(not adapter.step_batch(b,second,2))
        assert(not adapter.step_batch(b,second,2))
        assert(created==before and #b.buffers==0 and second.positions)
        assert(adapter.step_batch(b,second,2))
        assert(created==before+1 and not b.pending_batch and not second.positions)
        equal(resources[first.resource],resources[second.resource])
        if case.glass then
            local data=resources[second.resource]
            assert(data.streams.position[1]==.125-10)
            assert(data.streams.position[2]==.25+3)
            assert(data.bounds[1]==-1 and data.bounds[4]==1)
        elseif not case.override then
            for i=1,14 do assert(resources[second.resource].streams.surface_data[i]==i*.1) end
        end
        adapter.final(a);adapter.final(b)
    end)
end
test("cancelling a partial upload leaves no published resource or object",function()
    local a=adapter.new("#world_mesh")
    local before=created
    assert(not adapter.step_batch(a,batch(false),1))
    adapter.final(a)
    assert(not a.pending_batch and created==before and #a.objects==0 and #a.buffers==0)
end)
assert(created==released)
print(count.." world upload tests passed")
