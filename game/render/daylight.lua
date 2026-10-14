-- Fixed reference celestial states. No simulation clocks or random streams.
-- The reference's summer-solstice site is rotated 61 degrees into this map.
local M={environment_size=64,environment_rows=9,reflection_levels=6,max_volumes=8,
    sky_width=768,sky_height=384,fog_steps=40}
M.environment_stride=M.environment_size+2
M.environment_width=M.environment_stride*6
M.environment_height=M.environment_stride*M.environment_rows
local pi,exp,sqrt=math.pi,math.exp,math.sqrt
local function copy(t)
    if type(t)~="table" then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
local function direction(hour,declination,offset)
    local lat=pi/4
    local h=(hour-12)*pi/12+(offset or 0)*pi/180
    local dec=declination*pi/180
    local y=math.sin(lat)*math.sin(dec)+math.cos(lat)*math.cos(dec)*math.cos(h)
    local az=math.acos(math.max(-1,math.min(1,(math.sin(dec)-y*math.sin(lat))/(sqrt(1-y*y)*math.cos(lat)))))
    if math.sin(h)>0 then az=2*pi-az end
    az=az+61*pi/180
    return {sqrt(1-y*y)*math.sin(az),y,-sqrt(1-y*y)*math.cos(az),0}
end
-- Reference medium in megametres, integrated at the same 200 m sky altitude.
-- This is also used by the GPU sky integral; direct light cannot keep a white
-- noon spectrum while the atmosphere around it turns orange.
function M.transmittance(mu,altitude,mie)
    local r=6.36+(altitude or .0002)
    local ground=r*r*mu*mu-r*r+6.36^2
    if mu<0 and ground>0 then return {0,0,0} end
    local dt=(-r*mu+sqrt(r*r*mu*mu-r*r+6.46^2))/48
    local od={0,0,0};local ray={5.802,13.558,33.1};local ozone={.650,1.881,.085}
    for i=1,48 do
        local t=(i-.5)*dt
        local h=math.max(0,(sqrt(r*r+t*t+2*r*t*mu)-6.36)*1000)
        local aerosol=8.396*(mie or 1)*exp(-h/1.2)
        local oz=math.max(0,1-math.abs(h-25)/15)
        for c=1,3 do od[c]=od[c]+dt*(ray[c]*exp(-h/8)+aerosol+ozone[c]*oz) end
    end
    return {exp(-od[1]),exp(-od[2]),exp(-od[3])}
end
local states={}
for _,preset in ipairs({{"daylight",16.5},{"sunset",19.2},{"night",1.5}}) do
    local name,hour=preset[1],preset[2]
    local sun=direction(hour,23.44*math.sin(2*pi/365*(284+172)))
    local moon=direction(hour,28,244)
    local night=name=="night"
    local key=night and moon or sun
    local spectrum=night and {.21,.255,.30} or {5.12,5.12,5.12}
    local transmitted=M.transmittance(key[2])
    local direct,ground={},{ }
    for i=1,3 do
        direct[i]=spectrum[i]*transmitted[i]
        ground[i]=direct[i]*math.max(0,key[2])*.24/pi
    end
    states[name]={name=name,hour=hour,sun_direction=key,sun_radiance=direct,
        solar_direction=sun,moon_direction=moon,sky_horizon={0,0,0,0},sky_zenith={0,0,0,0},
        ground_radiance=ground,sun_shape={0,0,0,0},indirect={1,1,.18,.025},
        atmosphere_data={key,spectrum,{1,night and 1 or 0,1,0},sun,moon},
        fog_data={.0044,.16,180,.006},fog_tint={.88,.96,1.08,0}}
end
function M.rig(name) assert(states[name or "daylight"],"Unknown lighting preset");return copy(states[name or "daylight"]) end
function M.snapshot(name)
    local r=M.rig(name)
    r.environment_width=M.environment_width;r.environment_height=M.environment_height
    r.sky_width=M.sky_width;r.sky_height=M.sky_height
    return r
end
function M.constants(vector,name,clouds)
    local rig=M.rig(name)
    local result={daylight_data={},atmosphere_data={}}
    local function v(t) return vector(t[1],t[2],t[3],t[4] or 0) end
    for i,key in ipairs({"sun_direction","sun_radiance","sky_horizon","sky_zenith","ground_radiance","sun_shape"}) do
        result.daylight_data[i]=v(rig[key])
    end
    rig.atmosphere_data[3][3]=clouds==false and 0 or 1
    for i,t in ipairs(rig.atmosphere_data) do result.atmosphere_data[i]=v(t) end
    result.indirect=v(rig.indirect)
    result.environment_layout=vector(M.environment_size,M.environment_stride,M.reflection_levels,M.environment_rows)
    result.fog_data=v(rig.fog_data);result.fog_tint=v(rig.fog_tint)
    return result
end
-- Preserve the world-generator's default-light contract.
for k,v in pairs(states.daylight) do M[k]=copy(v) end
return M
