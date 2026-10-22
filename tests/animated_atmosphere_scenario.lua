-- One native/WebGL fixture for staged weather, real GPU output and lifecycle.
local runtime=require "game.runtime"
local settings=require "game.render.settings"
local capture=require "game.render.capture_controller"
local M={}
local function snapshot(stats)
    -- Native print messages have a 4096-byte limit. Keep this fixture's data
    -- instead of unrelated material/combat diagnostics from renderer.snapshot.
    local result={}
    for _,key in ipairs({"width","height","pipeline","target_count","target_bytes","bake_draws",
        "solar_hour","requested_hour","weather_time","requested_weather_time","atmosphere_stage",
        "atmosphere_blend","atmosphere_update_draws","environment_updates","scattering_updates",
        "scattering_update_draws","temporal_resets","temporal_age","settings"}) do result[key]=stats[key] end
    return result
end
local function report(kind,data)
    local line="ATMOSPHERE "..kind.." "..json.encode(data)
    if html5 then html5.run("console.log("..json.encode(line)..")") else print(line) end
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run("console.error("..json.encode("ERROR: "..tostring(message).."\n"..tostring(stack))..")") end) end
    local t={checks=0,shots=0}
    if automation_bridge then automation_bridge.command("atmosphere.capture_ack",function(data)
        assert(data.id==t.waiting);t.ack=data.id;return data
    end) end
    report("START",sys.get_engine_info());return t
end
function M.update(test,self,dt,restart)
    if test.done then return end
    local ctx=self.ctx
    ctx.ai.enabled=false
    if not test.hold then runtime.set_paused(ctx,false);self.focused=true end
    if not ctx.world.ready or not self.renderer_stats.ready then return end
    if not test.job then test.job=coroutine.create(function()
        local function frames(n) for _=1,n do coroutine.yield() end end
        local function check(name,detail) test.checks=test.checks+1;report("CHECK",{name=name,detail=detail}) end
        local function configure(values)
            self.renderer_settings=settings.configure(self.renderer_settings,values)
            msg.post("@render:","renderer_configure",self.renderer_settings)
        end
        local function settle()
            frames(3)
            local limit=0
            repeat frames(1);limit=limit+1;assert(limit<120,"Weather did not settle")
            until self.renderer_stats.atmosphere_stage==0
            frames(40)
        end
        local function shot(name)
            settle();test.waiting=name;test.ack=nil;test.shots=test.shots+1
            report("SHOT",{id=name,renderer=snapshot(self.renderer_stats)})
            local limit=0
            repeat
                if html5 and html5.run("window.__atmosphereCaptureAck || ''")==name then test.ack=name end
                frames(1);limit=limit+1;assert(limit<3600,"Screenshot acknowledgement timeout")
            until test.ack==name
        end
        local function view(name)
            capture.select(self,{name=name})
            configure({temporal_aa=false,auto_exposure=false,motion_blur=0,grain=0,ads_dof=0})
        end
        view("sky_daylight");shot("sky_zero")
        local scattering=self.renderer_stats.scattering_updates
        configure({weather_time=120});shot("sky_drift")
        assert(self.renderer_stats.scattering_updates==scattering,"Wind rebuilt clear scattering")
        -- Compare a cache-hit image with a fresh strip bake at the same pose.
        configure({hour=17});settle()
        configure({hour=16.5})
        configure({weather_time=0});shot("sky_return")
        assert(self.renderer_stats.scattering_updates==scattering+2)
        check("cloud_drift_and_exact_fixed_return")
        configure({view="environment_atlas"});shot("environment_zero")
        scattering=self.renderer_stats.scattering_updates
        configure({weather_time=120});shot("environment_drift")
        configure({weather_time=0});shot("environment_return")
        assert(self.renderer_stats.scattering_updates==scattering)
        check("sky_and_filtered_reflections_share_weather")
        view("street");configure({weather_time=1745,fog=false,reflections=false})
        shot("cloud_shadow")
        configure({cloud_shadows=false});shot("cloud_shadow_off")
        configure({cloud_shadows=true});shot("cloud_shadow_return")
        check("cloud_shadow_toggle_uses_production_surface_lighting")
        view("window_shafts");configure({view="fog_scatter"})
        shot("fog_zero");configure({weather_time=60});shot("fog_drift")
        configure({weather_time=0});shot("fog_return")
        check("advected_fog_has_exact_addressed_return")
        view("street")
        for _,hour in ipairs({5,12,19.2,20,21,1.5}) do
            configure({hour=hour});shot("hour_"..tostring(hour))
            assert(math.abs(self.renderer_stats.solar_hour-hour)<.0001)
        end
        check("full_market_dawn_day_sunset_twilight_night")
        capture.finish(self);self.view="street";test.hold=true;runtime.set_paused(ctx,true)
        configure({hour=18,weather_time=0,weather_speed=10,time_rate=1,temporal_aa=true,
            auto_exposure=true,grain=0,combat_effects=false})
        settle()
        local initial=self.renderer_stats
        local count,bytes,bakes=initial.target_count,initial.target_bytes,initial.bake_draws
        local resets,updates=initial.temporal_resets,initial.environment_updates
        local start_hour=initial.requested_hour
        test.hold=false;runtime.set_paused(ctx,false)
        local peak,advanced,previous_hour,frame=0,0,start_hour,0
        repeat
            frames(1);local s=self.renderer_stats
            advanced=advanced+(s.requested_hour-previous_hour)%24;previous_hour=s.requested_hour
            frame=frame+1;assert(frame<2400,"Solar transition did not advance")
            peak=math.max(peak,s.atmosphere_update_draws)
            assert(s.target_count==count and s.target_bytes==bytes and s.bake_draws==bakes)
            assert(s.temporal_resets==resets,"Weather reset continuous temporal history")
        until advanced>=8 and frame>=180
        assert(self.renderer_stats.environment_updates>updates+2)
        assert(peak==2)
        check("continuous_time_and_clouds_keep_history_and_two_draw_budget",{hours=advanced,frames=frame,renderer=snapshot(self.renderer_stats)})
        test.hold=true;runtime.set_paused(ctx,true);frames(35)
        local frozen=self.renderer_stats
        local hour,time,stage=frozen.requested_hour,frozen.requested_weather_time,frozen.atmosphere_stage
        frames(45)
        assert(self.renderer_stats.requested_hour==hour and self.renderer_stats.requested_weather_time==time and self.renderer_stats.atmosphere_stage==stage)
        require("game.ui.controller").focus(self,false);frames(35)
        assert(self.renderer_stats.requested_hour==hour and self.renderer_stats.requested_weather_time==time)
        require("game.ui.controller").focus(self,true)
        check("pause_and_focus_freeze_inflight_weather_without_catchup")
        for _=1,3 do
            restart(self);ctx.ai.enabled=false;runtime.set_paused(ctx,true);frames(35)
            assert(self.renderer_stats.target_count==count and self.renderer_stats.target_bytes==bytes)
        end
        check("three_restarts_keep_fixed_render_resources")
        self.view=nil;test.done=true
        report("PASS",{checks=test.checks,shots=test.shots,renderer=snapshot(self.renderer_stats)})
    end) end
    local ok,message=coroutine.resume(test.job);assert(ok,message)
end
return M
