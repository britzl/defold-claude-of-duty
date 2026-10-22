-- Presentation-only weather clock and bounded bake scheduler.
local daylight=require "game.render.daylight"
local M={sky_slices=8,environment_slices=9,blend_seconds=.2}
-- Only these inputs affect at_scatter(): medium density and both celestial
-- directions/irradiances. Cloud toggles, wind and the displayed key are separate.
function M.same_scattering(a,b)
    if not a or not b then return false end
    local x,y=a.atmosphere_data,b.atmosphere_data
    if x[3][1]~=y[3][1] then return false end
    for i=4,7 do
        for c=1,3 do if x[i][c]~=y[i][c] then return false end end
    end
    return true
end
function M.new(options)
    return {hour=options.hour,time=options.weather_time,rig=daylight.rig(options.hour),
        shown_time=options.weather_time,clouds=options.clouds,stage=0,updates=0,forced=false}
end
function M.seek(s,hour,time)
    if hour~=nil then s.hour=hour%24 end
    if time~=nil then s.time=time end
    s.stage=0;s.pending=nil;s.forced=true
end
function M.configure(s,old,new)
    local seek=old.hour~=new.hour or old.weather_time~=new.weather_time
    if seek or old.clouds~=new.clouds then
        M.seek(s,old.hour~=new.hour and new.hour or nil,
            old.weather_time~=new.weather_time and new.weather_time or nil)
    end
end
function M.step(s,options,dt,paused,capture)
    dt=math.max(0,math.min(.1,dt or 1/60))
    local frozen=paused or capture
    if not frozen then
        s.hour=(s.hour+dt*options.time_rate)%24
        s.time=s.time+dt*options.weather_speed
    end
    if frozen and not s.forced then return end
    if s.stage==0 then
        local hours=math.abs((s.hour-s.rig.hour+12)%24-12)
        if not s.forced and hours<.001 and math.abs(s.time-s.shown_time)<.1 then return end
        s.pending=daylight.rig(s.hour);s.pending_time=s.time
        s.from=s.rig;s.from_time=s.shown_time;s.blend=0;s.stage=1
        return "begin"
    end
    if s.stage<=M.sky_slices then
        local slice=s.stage;s.stage=s.stage+1
        return "sky",slice
    end
    if s.stage<=M.sky_slices+M.environment_slices then
        local slice=s.stage-M.sky_slices;s.stage=s.stage+1
        return "environment",slice
    end
    -- Explicit seeks/captures publish atomically. Continuous motion blends both
    -- completed maps and the direct-light/shadow rig without resetting TAA.
    s.blend=s.forced and 1 or math.min(1,s.blend+dt/M.blend_seconds)
    s.rig=daylight.blend(s.from,s.pending,s.blend)
    s.shown_time=s.from_time+(s.pending_time-s.from_time)*s.blend
    local committed=s.blend==1
    if committed then s.rig=s.pending;s.clouds=options.clouds;s.stage=0;s.forced=false;s.updates=s.updates+1 end
    return "blend",s.blend,committed
end
function M.weather(vector,time,options)
    return vector(math.cos(.7)*.0042*time,math.sin(.7)*.0042*time,time,
        options.clouds and options.cloud_shadows and 1 or 0)
end
return M
