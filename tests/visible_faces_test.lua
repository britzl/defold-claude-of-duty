local visible=require "game.world.visible_faces"
local mesh=require "game.world.mesh"
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function area(rects)
    local result=0
    for _,r in ipairs(rects) do result=result+(r[3]-r[1])*(r[4]-r[2]) end
    return result
end
test("adjoining solids remove both internal faces without opening exterior seams",function()
    local bounds={{-1,-1,-1,1,1,1},{1,-1,-1,3,1,1}}
    local a,b=visible.for_box(1,bounds),visible.for_box(2,bounds)
    assert(#a[1]==0 and #b[2]==0)
    for _,i in ipairs({3,4,5,6}) do assert(area(a[i])+area(b[i])==8) end
end)
test("partly buried trim is clipped to the facade, including its underside",function()
    local bounds={{-1,-1,-1,1,1,1},{.9,0,-1.1,1.1,.2,1.1}}
    local wall,trim=visible.for_box(1,bounds),visible.for_box(2,bounds)
    assert(math.abs(area(wall[1])-3.6)<1e-7)
    assert(math.abs(area(trim[4])-.24)<1e-7)
    for _,r in ipairs(trim[4]) do assert(r[1]>=1 or r[4]<=-1 or r[2]>=1) end
end)
test("small attached fittings preserve facade faces and use bounded box geometry",function()
    local wall={x=0,y=2,z=0,w=.3,h=4,d=6,material="concrete"}
    local fixing={x=.175,y=1,z=0,w=.12,h=.06,d=.12,material="metal",unclipped=true}
    local bounds={visible.bounds(wall),visible.bounds(fixing)}
    assert(visible.for_box(2,bounds)==nil)
    local faces=visible.for_box(1,bounds)
    assert(#faces[1]==1 and area(faces[1])==24,"Fixing fragmented its supporting wall")
    local batch=mesh.new("fixing","metal",0,0)
    mesh.shape(batch,fixing,1,visible.for_box(2,bounds),{})
    assert(batch.vertex_count==36)
end)
test("coincident surfaces have one geometric owner independent of batch submission",function()
    local bounds={{-1,-1,-1,1,1,1},{0,-1,-1,2,1,1}}
    local a,b=visible.for_box(1,bounds),visible.for_box(2,bounds)
    assert(area(a[3])==4 and area(b[3])==2)
    local identical={bounds[1],bounds[1]}
    for _,rects in ipairs(visible.for_box(2,identical)) do assert(#rects==0) end
end)
test("clipped faces retain winding and remove geometry below a raised kerb",function()
    local shapes={
        {x=0,y=-.15,z=0,w=9,h=.3,d=7,material="asphalt"},
        {x=5.5,y=-.0275,z=0,w=2,h=.345,d=7,material="concrete"}}
    local bounds={visible.bounds(shapes[1]),visible.bounds(shapes[2])}
    local faces=visible.for_box(2,bounds)
    assert(math.abs(area(faces[2])-.145*7)<1e-7)
    assert(faces[2][1][1]==0)
    local batch=mesh.new("test","concrete",0,0)
    mesh.box(batch,shapes[2],1,faces)
    local p,n=batch.positions,batch.normals
    for i=1,#p,9 do
        local ax,ay,az=p[i+3]-p[i],p[i+4]-p[i+1],p[i+5]-p[i+2]
        local bx,by,bz=p[i+6]-p[i],p[i+7]-p[i+1],p[i+8]-p[i+2]
        assert((ay*bz-az*by)*n[i]+(az*bx-ax*bz)*n[i+1]+(ax*by-ay*bx)*n[i+2]>0)
    end
end)
test("shared edge endpoints include both box boundaries and clipped window cuts",function()
    local bounds={{6.5,3.145,-12,20.2,3.255,2},{6.4,3.255,-12.1,6.8,3.345,2.1}}
    local registry={}
    for i,b in ipairs(bounds) do visible.register_edges(registry,b,visible.for_box(i,bounds)) end
    local points=visible.edge_vertices(registry,{6.5,3.255,-12.1},{6.5,3.255,2.1})
    assert(#points==2 and points[1][3]==-12 and points[2][3]==2)
    -- These endpoints were introduced by clipping: they are absent from the
    -- original wall bounds, but must split the adjacent roof's longer edge.
    local wall={6.5,0,-12,6.8,9.545,2}
    visible.register_edges(registry,wall,{{},{{9.325,-5.975,9.545,-4.025}},{},{},{},{}})
    points=visible.edge_vertices(registry,{6.5,9.545,-12},{6.5,9.545,2})
    assert(#points==2 and points[1][3]==-5.975 and points[2][3]==-4.025)
end)
test("spatial lookup preserves clipping order at cell boundaries and epsilon contacts",function()
    local bounds={}
    for i=1,40 do
        local x,z=(i%7-3)*8,(i%5-2)*8
        bounds[i]={x-4,-1,z-4,x+4,3,z+4,unclipped=i%9==0}
    end
    bounds[#bounds+1]={-80,-2,-80,80,-1,80}
    bounds[#bounds+1]={4+5e-8,0,-4,6,1,4}
    bounds[#bounds+1]=bounds[2]
    local grid=visible.index(bounds)
    local function equal(a,b)
        assert(type(a)==type(b))
        if type(a)~="table" then assert(a==b);return end
        assert(#a==#b)
        for i,v in ipairs(a) do equal(v,b[i]) end
    end
    for i=1,#bounds do equal(visible.for_box(i,bounds),visible.for_box(i,bounds,grid)) end
end)
test("edge lookup preserves epsilon deduplication and reverse traversal",function()
    local registry={}
    local bounds={0,0,0,1,1,8}
    visible.register_edges(registry,bounds,{{{0,0,1,8}},{},{},{},{},{}})
    for _,z in ipairs({1,1+5e-8,2,7,7+5e-8}) do
        visible.register_edges(registry,{0,0,z,1,1,z+1},{{{0,z,1,z+1}},{},{},{},{},{}})
    end
    local a,b={1,0,1},{1,0,7}
    local forward,reverse=visible.edge_vertices(registry,a,b),visible.edge_vertices(registry,b,a)
    assert(#forward==#reverse and #forward>0)
    for i,p in ipairs(forward) do
        assert(p[3]>1+1e-7 and p[3]<7-1e-7)
        assert(p[3]==reverse[#reverse-i+1][3])
        if i>1 then assert(p[3]-forward[i-1][3]>1e-7) end
    end
end)
print(count.." visible-face tests passed")
