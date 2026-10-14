local settings=require "game.render.settings"
local photo=require "game.render.photographic"
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
test("photographic controls reject invalid input without changing the current settings",function()
    local current=settings.defaults()
    for k,r in pairs(photo.ranges) do
        for _,v in ipairs({r[1]-.01,r[2]+.01,0/0,math.huge,"1",false}) do
            assert(not pcall(settings.configure,current,{[k]=v}),k)
        end
        assert(settings.configure(current,{[k]=0})[k]==0)
    end
    assert(not pcall(settings.configure,current,{photographic_quality="ultra"}))
    assert(current.grade_strength==1 and current.auto_exposure)
end)
test("quality tiers bound memory and sampling work at normal, odd and tiny resolutions",function()
    for _,size in ipairs({{1,1},{1279,719},{1920,1080}}) do
        local previous=0
        for _,name in ipairs({"low","medium","high"}) do
            local options=settings.configure(settings.defaults(),{photographic_quality=name})
            local bytes=photo.bytes(size[1],size[2],true,options)
            assert(bytes>previous);previous=bytes
            for _,r in pairs(photo.resources(size[1],size[2],options)) do assert(r[1]>=1 and r[2]>=1) end
            assert(photo.quality(name).taps<=13 and photo.quality(name).radius<=16)
            if name=="low" then assert(not photo.resources(size[1],size[2],options).photo_motion) end
        end
    end
end)
test("disabled blur targets release their full resolution allocation",function()
    local current=settings.defaults()
    local off=settings.configure(current,{motion_blur=0,ads_dof=0})
    assert(photo.bytes(1280,720,true,current)-photo.bytes(1280,720,true,off)==1280*720*8*2)
end)
test("night adaptation cannot turn night into day and pause/stalls cannot advance time",function()
    for _,name in ipairs({"daylight","sunset","night"}) do
        local low,high=photo.exposure_limits(name)
        assert(low>0 and low<1 and high>1 and high<=1.8)
    end
    local _,night=photo.exposure_limits("night");assert(night==1.3)
    assert(photo.delta(10,false,false)==.1)
    assert(photo.delta(.1,true,false)==0 and photo.delta(.1,false,true)==0)
    assert(photo.delta(-1,false,false)==0)
end)
print(count.." photographic tests passed")
