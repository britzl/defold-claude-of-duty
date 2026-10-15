local capture=require "game.render.capture"
local lab=require "game.render.laboratory"
local tests=0
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
test("camera samples are frame addressed, bounded and do not mutate definitions",function()
    local shot=capture.select("street")
    local start=capture.camera(shot,0)
    local last=capture.camera(shot,120)
    assert(start.position.x==0 and last.position.x==1.2 and shot.position[1]==0)
    assert(start.yaw==0 and start.pitch==0)
    for _,frame in ipairs({-1,121,.5,0/0,math.huge}) do assert(not pcall(capture.camera,shot,frame)) end
    capture.catalog().shots[1].position[1]=99
    assert(capture.select("street").position[1]==0)
    assert(capture.select("night").lighting=="night" and capture.select("sunset").lighting=="sunset")
end)
test("laboratory normals, winding, bounds and roughness range are valid",function()
    local batches=lab.batches()
    local spheres=0
    for _,b in ipairs(batches) do
        assert(#b.positions==b.vertex_count*3 and #b.colors==b.vertex_count*4)
        assert(#b.edges==b.vertex_count*4 and #b.masks==b.vertex_count*4)
        for i=1,#b.positions,3 do
            local n=b.normals
            assert(math.abs(n[i]^2+n[i+1]^2+n[i+2]^2-1)<1e-6)
            for a=0,2 do assert(b.positions[i+a]>=b.bounds[a+1]-1e-6 and b.positions[i+a]<=b.bounds[a+4]+1e-6) end
        end
        if b.key:match("^sphere/") then
            spheres=spheres+1
            assert(b.surface[3]>=.08 and b.surface[3]<=1)
            for i=1,#b.positions,9 do
                local p,n=b.positions,b.normals
                local ax,ay,az=p[i+3]-p[i],p[i+4]-p[i+1],p[i+5]-p[i+2]
                local bx,by,bz=p[i+6]-p[i],p[i+7]-p[i+1],p[i+8]-p[i+2]
                assert((ay*bz-az*by)*n[i]+(az*bx-ax*bz)*n[i+1]+(ax*by-ay*bx)*n[i+2]>0,"Inverted sphere face")
            end
        end
    end
    assert(spheres==10 and #batches==lab.batch_count)
    local contacts=0
    for _,b in ipairs(batches) do if b.key=="wood" then
        for i=1,#b.positions,3 do
            local p,n=b.positions,b.normals
            if p[i]>41 and p[i]<43 and p[i+2]>-3 and p[i+2]<-1 and math.abs(n[i+1])<.1 then
                assert(p[i+1]>=.01999,"Reflection fixture sides must be clipped to the plate top")
                contacts=contacts+1
            end
        end
    end end
    assert(contacts>0)
end)
test("capture weapon poses ignore live movement, clock and recoil",function()
    local pose=require "game.weapons.viewmodel"
    local model=require("game.weapons.geometry").weapon("rifle")
    local hip,ads=pose.capture(model,false),pose.capture(model,true)
    assert(hip.ads==0 and ads.ads==1 and not hip.parts.reticle.visible and ads.parts.reticle.visible)
    assert(not hip.parts.flash.visible and not ads.parts.flash.visible)
    local again=pose.capture(model,false)
    for i=1,3 do assert(hip.position[i]==again.position[i] and hip.rotation[i]==again.rotation[i]) end
end)
test("leaf cards carry the shared coverage tag on both windings without edge faces",function()
    local mesh=require "game.world.mesh"
    local b=mesh.new("leaf","foliage",0,0)
    mesh.card(b,{material="foliage",x=0,y=1,z=0,w=2,h=2})
    assert(b.vertex_count==12)
    for i=1,12 do
        assert(b.colors[i*4]==-1 and b.positions[i*3]==0)
        assert(b.normals[i*3]==(i<=6 and 1 or -1))
    end
    for _,name in ipairs(lab.catalogue_materials) do
        for _,suffix in ipairs({"","_far","_grazing"}) do
            local s=capture.select("material_"..name..suffix)
            assert(s.laboratory and capture.camera(s,120).position.x==s.position[1]+1.2)
        end
    end
    assert(capture.select("foliage_local").lighting=="night")
end)
print(tests.." capture tests passed")
