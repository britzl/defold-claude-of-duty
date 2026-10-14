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
test("preset snapshots are isolated and settings reject arbitrary time or invalid rigs",function()
    local a=daylight.rig("sunset");a.sun_radiance[1]=999;a.atmosphere_data[1][1]=999
    assert(daylight.rig("sunset").sun_radiance[1]<6 and daylight.rig("sunset").sun_direction[1]<1)
    for _,bad in ipairs({{lighting="dawn"},{lighting=12},{clouds=1},{volumetric_fog="yes"},{fog_shadows=0},{hour=19}}) do
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
print(count.." atmosphere tests passed")
