-- Opt-in browser qualification. Uses production capture and renderer paths.
local capture=require "game.render.capture_controller"
local catalog=require "game.render.capture"
local atlas=require "game.render.surface_atlas"
local M={}
local function report(message)
    -- Release engines suppress print(), so qualification must use the browser
    -- console directly. Keep this bridge inside the opt-in test fixture.
    if html5 then html5.run("console.log("..json.encode(message)..")")
    else print(message) end
end
function M.new()
    local steps={}
    for _,shot in ipairs(catalog.catalog().shots) do
        if not shot.unsupported then steps[#steps+1]={name=shot.id,id=shot.id} end
    end
    for _,pair in ipairs({{"weathering_facade","weathering"},{"micro_detail","micro_detail"},{"parallax_tile","parallax"}}) do
        steps[#steps+1]={name=pair[1],id=pair[1].."_disabled",changes={[pair[2]]=false}}
    end
    for _,step in ipairs({
        {name="interior",id="interior_ungated",changes={interior_lighting=false}},
        {name="laboratory",id="laboratory_unfiltered",changes={environment_filter=false}},
        {name="laboratory",id="laboratory_no_volumes",changes={interior_lighting=false}},
        {name="laboratory",id="environment_atlas",changes={view="environment_atlas"}},
    }) do steps[#steps+1]=step end
    for _,step in ipairs({
        {name="shadow_distance",id="shadow_atlas",changes={view="shadow",bloom=false}},
        {name="shadow_distance",id="shadow_cascades",changes={view="cascades",bloom=false}},
        {name="shadow_distance",id="shadow_distance_disabled",changes={shadows=false}},
        {name="shadow_cutout",id="shadow_cutout_disabled",changes={shadows=false}},
        {name="shadow_cutout",id="shadow_cutout_visibility",changes={view="shadow_visibility",bloom=false}},
        {name="shadow_remote",id="shadow_remote_disabled",changes={shadows=false}},
        {name="shadow_remote",id="shadow_remote_return"},
    }) do steps[#steps+1]=step end
    for _,name in ipairs({"street","contact_furniture","contact_corner","shadow_cutout"}) do
        for _,view in ipairs({"depth","geometry_normals","ao","contact"}) do
            steps[#steps+1]={name=name,id=name.."_"..view,changes={view=view}}
        end
    end
    steps[#steps+1]={name="contact_furniture",id="contact_furniture_no_ao",changes={ambient_occlusion=false}}
    steps[#steps+1]={name="contact_furniture",id="contact_furniture_no_contact",changes={contact_shadows=false}}
    steps[#steps+1]={name="contact_furniture",id="contact_furniture_disabled",changes={ambient_occlusion=false,contact_shadows=false}}
    steps[#steps+1]={name="contact_furniture",id="contact_furniture_return"}
    for _,view in ipairs({"albedo","normals","material"}) do
        for page=1,math.ceil(atlas.width/1024)*math.ceil(atlas.height/1024) do
            steps[#steps+1]={name="laboratory",id=view.."_page_"..page,changes={view=view,atlas_page=page},page=page,view=view}
        end
    end
    for _,step in ipairs({
        {name="street",id="temporal_disabled",changes={temporal_aa=false}},
        {name="shadow_cutout",id="cutout_temporal_disabled",changes={temporal_aa=false}},
        {name="weapon",id="weapon_aa_disabled",changes={weapon_aa=false}},
        {name="ads",id="ads_aa_disabled",changes={weapon_aa=false}},
        {name="street",id="temporal_motion",changes={view="motion"}},
        {name="street",id="temporal_history",changes={view="history"}},
        {name="shadow_cutout",id="temporal_camera_motion",changes={view="motion"},play=true},
        {name="street",id="temporal_live_cost",live=true},
    }) do steps[#steps+1]=step end
    for _,step in ipairs({
        {name="reflections",id="reflections_disabled",changes={reflections=false}},
        {name="reflections",id="reflection_confidence",changes={view="reflections"}},
        {name="glass",id="glass_disabled",changes={glass=false}},
        {name="local_lights",id="local_lights_disabled",changes={local_shadows=false}},
        {name="local_lights",id="local_shadow_atlas",changes={view="local_shadow"}},
        {name="glass",id="glass_return"},
        {name="street",id="step9_disabled_cost",live=true,changes={reflections=false,glass=false,local_shadows=false,muzzle_lights=false}},
    }) do steps[#steps+1]=step end
    for _,step in ipairs({
        {name="sky_daylight",id="clouds_disabled",changes={clouds=false}},
        {name="sky_daylight",id="clouds_return"},
        {name="sunset",id="sunset_fog_disabled",changes={fog=false}},
        {name="sunset",id="sunset_analytic",changes={volumetric_fog=false}},
        {name="window_shafts",id="shafts_shadowed",changes={view="fog_scatter"}},
        {name="window_shafts",id="shafts_unshadowed",changes={view="fog_scatter",fog_shadows=false}},
        {name="window_shafts",id="shafts_return",changes={view="fog_scatter"}},
        {name="sunset",id="sunset_environment",changes={view="environment_atlas"}},
        {name="night",id="night_environment",changes={view="environment_atlas"}},
        {name="street",id="step10_disabled_cost",live=true,changes={fog=false}},
    }) do steps[#steps+1]=step end
    for _,step in ipairs({
        {name="rifle_hip",id="rifle_materials_off",changes={combat_materials=false}},
        {name="weapon_indoor",id="weapon_indoor_ungated",changes={interior_lighting=false}},
        {name="weapon_fire",id="weapon_flash_off",changes={combat_effects=false}},
        {name="combat_effects",id="combat_effects_off",changes={combat_effects=false}},
        {name="combat_effects",id="combat_soft_off",changes={soft_particles=false}},
        {name="combat_effects",id="combat_decals_off",changes={impact_decals=false}},
        {name="combat_effects",id="combat_effects_return"},
        {name="combat_glass",id="combat_glass_off",changes={glass=false}},
        {name="combat_glass",id="combat_glass_return"},
    }) do steps[#steps+1]=step end
    steps[#steps+1]={name="street",id="street_return"}
    if sys.get_config_string("rendering_validation.suite","")=="photographic" then
        steps={}
        for _,name in ipairs({"street","interior","sunset","night","rifle_ads","weapon_fire","detail"}) do
            steps[#steps+1]={name=name,id=name}
        end
        for _,item in ipairs({{"street","grade_strength"},{"street","vignette"},{"street","grain"},{"detail","sharpen"},{"rifle_ads","ads_dof"},{"weapon_fire","bloom_strength"}}) do
            steps[#steps+1]={name=item[1],id=item[1].."_"..item[2].."_off",changes={[item[2]]=0}}
        end
        steps[#steps+1]={name="weapon_fire",id="bloom_diagnostic",changes={view="bloom"}}
        for _,name in ipairs({"street","interior","night"}) do
            steps[#steps+1]={name=name,id=name.."_exposure",changes={view="exposure",auto_exposure=true}}
        end
        -- Alternating tier order limits thermal/order bias; live TAA and both lens
        -- passes are included. GPU samples come from the browser timer harness.
        for repeat_index=1,3 do
            local tiers=repeat_index==2 and {"high","medium","low"} or {"low","medium","high"}
            for _,tier in ipairs(tiers) do
                steps[#steps+1]={name="rifle_ads",id="photo_cost_"..tier.."_"..repeat_index,live=true,
                    changes={photographic_quality=tier,auto_exposure=true}}
            end
        end
        steps[#steps+1]={name="street",id="photo_moving",play=true,changes={motion_blur=1}}
        steps[#steps+1]={name="street",id="street_return"}
    end
    if sys.get_config_string("rendering_validation.suite","")=="catalogue" then
        steps={}
        for _,name in ipairs({"sand","corrugated","burlap","foliage"}) do
            for _,suffix in ipairs({"","_far","_grazing"}) do
                local id="material_"..name..suffix
                steps[#steps+1]={name=id,id=id}
            end
        end
        for _,name in ipairs({"foliage_back","foliage_shadow","foliage_local"}) do steps[#steps+1]={name=name,id=name} end
        for _,name in ipairs({"material_foliage","material_foliage_far","foliage_back"}) do
            for _,view in ipairs({"depth","geometry_normals"}) do
                steps[#steps+1]={name=name,id=name.."_"..view,changes={view=view}}
            end
        end
        for _,entry in ipairs({{"foliage_shadow","shadows"},{"foliage_local","local_shadows"}}) do
            steps[#steps+1]={name=entry[1],id=entry[1].."_disabled",changes={[entry[2]]=false}}
            steps[#steps+1]={name=entry[1],id=entry[1].."_restored"}
        end
        for _,name in ipairs({"sand","corrugated","burlap","foliage"}) do
            steps[#steps+1]={name="material_"..name,id="material_"..name.."_motion",play=true,changes={view="motion"}}
        end
        for _,view in ipairs({"albedo","normals","material","coverage"}) do
            for page=1,math.ceil(atlas.width/1024)*math.ceil(atlas.height/1024) do
                steps[#steps+1]={name="laboratory",id=view.."_page_"..page,changes={view=view,atlas_page=page},page=page,view=view}
            end
        end
        steps[#steps+1]={name="material_foliage",id="material_foliage_return"}
    end
    if sys.get_config_string("rendering_validation.suite","")=="html5" then
        steps={}
        for _,name in ipairs({"street","sky_daylight","rifle_ads"}) do
            steps[#steps+1]={name=name,id=name}
        end
    end
    local local_shadow_cache=sys.get_config_string("rendering_validation.suite","")=="local_shadow_cache"
    if local_shadow_cache then
        -- Upload the laboratory before collecting paired temporal histories.
        -- Its first WebGL frame can precede the deferred mesh resources.
        steps={{name="local_lights",id="local_shadow_fixture_warmup",changes={local_shadow_cache=false}}}
        for _,name in ipairs({"street","interior","courtyard","local_lights","foliage_local"}) do
            for _,view in ipairs((name=="local_lights" or name=="foliage_local") and {"scene","local_shadow"} or {"scene"}) do
                for _,cached in ipairs({false,true}) do
                    steps[#steps+1]={name=name,id=name.."_"..view..(cached and "_cached" or "_reference"),
                        changes={view=view,local_shadow_cache=cached}}
                end
            end
        end
        steps[#steps+1]={name="street",id="street_return"}
    end
    local weapon_aa=sys.get_config_string("rendering_validation.suite","")=="weapon_aa"
    if weapon_aa then
        steps={}
        for _,name in ipairs({"rifle_hip","rifle_ads","smg_hip","smg_ads","pistol_hip","pistol_ads","weapon_indoor","weapon_fire"}) do
            local scales=(name=="rifle_hip" or name=="weapon_fire") and {1,.71} or {1}
            for _,scale in ipairs(scales) do
                local id=name..(scale==1 and "" or "_scaled")
                for i,suffix in ipairs({"","_off","_return"}) do
                    steps[#steps+1]={name=name,id=id..suffix,
                        changes={weapon_aa=i~=2,bloom=false,render_scale=scale}}
                end
            end
        end
    end
    return {steps=steps,index=0,frames=0,intervals={},shot_frame=(weapon_aa or local_shadow_cache) and 65 or 45}
end
function M.update(test,self,dt)
    if test.done then
        if not test.restored and self.renderer_stats.ready and self.renderer_stats.bake_draws==atlas.draw_count*2 then
            test.restored=true
            report("RENDER_BROWSER RESTORED "..json.encode(self.renderer_stats))
        end
        return
    end
    if not self.ctx.world.ready or not self.renderer_stats.ready then return end
    test.target_count=test.target_count or self.renderer_stats.target_count
    test.frames=test.frames+1
    if test.frames==1 then
        test.index=test.index+1
        local step=test.steps[test.index]
        if not step then
            local stats=self.renderer_stats
            assert(stats.bake_jobs==atlas.job_count and stats.bake_draws==atlas.draw_count and stats.target_count==test.target_count)
            assert(stats.surface_count==#atlas.surfaces-1 and self.ctx.time.tick==test.tick,"Capture changed simulation")
            assert(self.ctx.audio.ready and self.map_sent and test.tick>0,"Gameplay startup did not finish")
            table.sort(test.intervals)
            report("RENDER_BROWSER PASS "..json.encode({renderer=stats,shots=#test.steps,
                runtime={profiler=profiler~=nil,world_ready=self.ctx.world.ready,audio_ready=self.ctx.audio.ready,
                    tick=test.tick,boxes=self.ctx.world.stats.boxes,batches=self.ctx.world.stats.batches,
                    colliders=self.ctx.world.stats.colliders},
                frame_interval_median_ms=test.intervals[math.ceil(#test.intervals*.5)],
                frame_interval_p95_ms=test.intervals[math.ceil(#test.intervals*.95)]}))
            test.done=true;return
        end
        capture.select(self,{name=step.name,temporal_live=step.live or step.play})
        if step.play then self.capture.playing=true;self.capture.direction=1 end
        test.tick=test.tick or self.ctx.time.tick
        if step.changes then msg.post("@render:","renderer_configure",step.changes) end
    end
    if test.frames>32 then test.intervals[#test.intervals+1]=dt*1000 end
    if test.frames==test.shot_frame then
        local step=test.steps[test.index]
        report("RENDER_BROWSER SHOT "..json.encode({id=step.id,page=step.page,view=step.view,
            camera=capture.snapshot(self).camera,renderer=self.renderer_stats}))
    end
    if test.frames>=100 then test.frames=0 end
end
return M
