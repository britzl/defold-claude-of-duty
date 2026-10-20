local daylight=require "game.render.daylight"
local settings=require "game.render.settings"
local capture=require "game.render.capture"
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
test("fixed celestial states match the reference altitudes and carry one spectral key",function()
    local expected={daylight=32,sunset=4.6,night=21.7}
    for name,altitude in pairs(expected) do
        local rig=daylight.rig(name)
        local d=rig.sun_direction
        assert(math.abs(d[1]^2+d[2]^2+d[3]^2-1)<1e-9)
        assert(math.abs(math.asin(d[2])*180/math.pi-altitude)<.15)
        for i=1,3 do
            assert(rig.sun_direction[i]==rig.atmosphere_data[1][i])
            assert(rig.sun_radiance[i]>0 and rig.sun_radiance[i]<5.12)
        end
    end
    local night=daylight.rig("night")
    assert(night.solar_direction[2]<0 and night.moon_direction[2]>0)
end)
test("spectral extinction reddens a low sun and blocks light below the planet",function()
    local high=daylight.transmittance(.8)
    local low=daylight.transmittance(.08)
    for i=1,3 do assert(high[i]>low[i] and high[i]<=1 and low[i]>0) end
    assert(low[1]/low[3]>high[1]/high[3]*3)
    local below=daylight.transmittance(-.1)
    assert(below[1]==0 and below[2]==0 and below[3]==0)
    local high_cloud=daylight.transmittance(.08,.0078)
    assert(high_cloud[3]>low[3])
end)
test("preset snapshots are isolated and settings reject invalid time and rigs",function()
    local a=daylight.rig("sunset");a.sun_radiance[1]=999;a.atmosphere_data[1][1]=999
    assert(daylight.rig("sunset").sun_radiance[1]<6 and daylight.rig("sunset").sun_direction[1]<1)
    for _,bad in ipairs({{lighting="dawn"},{lighting="invalid"},{clouds=1},{volumetric_fog="yes"},{fog_shadows=0},{hour=25}}) do
        assert(not pcall(settings.configure,settings.defaults(),bad))
    end
end)
test("cloud toggles change shared sky inputs without changing the celestial phase",function()
    local vector=function(...) return {...} end
    local a=daylight.constants(vector,"night",true)
    local b=daylight.constants(vector,"night",false)
    assert(a.atmosphere_data[3][3]==1 and b.atmosphere_data[3][3]==0)
    for i=1,3 do assert(a.daylight_data[1][i]==b.daylight_data[1][i]) end
    assert(a.atmosphere_data[3][2]==1)
end)
test("sunset night and opening captures have explicit reproducible lighting",function()
    for _,name in ipairs({"sunset","night","window_shafts","sky_sunset","sky_night"}) do
        local shot=capture.select(name)
        assert(shot.lighting and not shot.unsupported)
        assert(daylight.rig(shot.lighting).hour)
    end
    assert(capture.select("window_shafts").laboratory)
end)
local atmosphere=require "game.render.atmosphere"
test("continuous celestial clock wraps and twilight direct handover has no bright discontinuity",function()
    for i=0,24000 do
        local hour=i/1000;local r=daylight.rig(hour)
        for _,v in ipairs(r.sun_radiance) do assert(v==v and v>=0 and v<=5.12) end
        if i>0 then
            local prev=daylight.rig(hour-.001)
            for c=1,3 do assert(math.abs(r.sun_radiance[c]-prev.sun_radiance[c])<.025) end
        end
    end
    assert(daylight.rig(24).solar_direction[2]==daylight.rig(0).solar_direction[2])
    local r=daylight.blend(daylight.rig(23.9),daylight.rig(.1),.5)
    assert(r.hour<.001 or r.hour>23.999)
end)
test("weather scheduling is bounded, atomic on seek, and freezes without catch-up",function()
    local o=settings.configure(settings.defaults(),{weather_speed=1,time_rate=.2})
    local s=atmosphere.new(o)
    local phases={};local committed=0
    for i=1,180 do
        local phase,_,done=atmosphere.step(s,o,1/60,false,false)
        if phase then phases[phase]=(phases[phase] or 0)+1 end
        if done then committed=committed+1 end
    end
    assert(committed>2 and phases.sky>=24 and phases.environment>=27)
    assert(s.hour>17 and s.time>2.9)
    local hour,time,stage,shown=s.hour,s.time,s.stage,s.shown_time
    for i=1,80 do assert(not atmosphere.step(s,o,1,true,false)) end
    assert(hour==s.hour and time==s.time and stage==s.stage and shown==s.shown_time)
    assert(not atmosphere.step(s,o,1,false,true))
    local seek=settings.configure(o,{hour=1.5,weather_time=120})
    atmosphere.configure(s,o,seek)
    for i=1,18 do local _,_,done=atmosphere.step(s,seek,1/60,true,true);assert(not done) end
    local phase,blend,done=atmosphere.step(s,seek,1/60,true,true)
    assert(phase=="blend" and blend==1 and done and s.rig.hour==1.5 and s.shown_time==120)
    atmosphere.step(s,seek,.1,false,false)
    assert(s.hour~=seek.hour and s.time~=seek.weather_time)
    atmosphere.seek(s,seek.hour,seek.weather_time)
    assert(s.hour==seek.hour and s.time==seek.weather_time and s.stage==0 and s.forced)
end)
test("preset selection sets solar hour and rejects nonfinite weather controls atomically",function()
    local o=settings.configure(settings.defaults(),{hour=8})
    assert(settings.configure(o,{lighting="sunset"}).hour==19.2)
    for _,k in ipairs({"hour","time_rate","weather_speed","weather_time"}) do
        for _,v in ipairs({0/0,math.huge,-math.huge,"1"}) do assert(not pcall(settings.configure,o,{[k]=v})) end
    end
    assert(not pcall(settings.configure,o,{lighting=12}))
end)
print(count.." atmosphere tests passed")
