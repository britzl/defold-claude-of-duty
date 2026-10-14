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
print(count.." visible-face tests passed")
