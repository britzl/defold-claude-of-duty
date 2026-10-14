-- Opt-in browser qualification. Uses production capture and renderer paths.
local capture=require "game.render.capture_controller"
local catalog=require "game.render.capture"
local atlas=require "game.render.surface_atlas"
local M={}
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
    steps[#steps+1]={name="street",id="street_return"}
    return {steps=steps,index=0,frames=0,intervals={}}
end
function M.update(test,self,dt)
    if test.done then
        if not test.restored and self.renderer_stats.ready and self.renderer_stats.bake_draws==atlas.draw_count*2 then
            test.restored=true
            print("RENDER_BROWSER RESTORED "..json.encode(self.renderer_stats))
        end
        return
    end
    if not self.ctx.world.ready or not self.renderer_stats.ready then return end
    test.frames=test.frames+1
    if test.frames==1 then
        test.index=test.index+1
        local step=test.steps[test.index]
        if not step then
            local stats=self.renderer_stats
            assert(stats.bake_jobs==atlas.job_count and stats.bake_draws==atlas.draw_count and stats.target_count==12)
            assert(stats.surface_count==15 and self.ctx.time.tick==test.tick,"Capture changed simulation")
            table.sort(test.intervals)
            print("RENDER_BROWSER PASS "..json.encode({renderer=stats,shots=#test.steps,
                frame_interval_median_ms=test.intervals[math.ceil(#test.intervals*.5)],
                frame_interval_p95_ms=test.intervals[math.ceil(#test.intervals*.95)]}))
            test.done=true;return
        end
        capture.select(self,{name=step.name})
        test.tick=test.tick or self.ctx.time.tick
        if step.changes then msg.post("@render:","renderer_configure",step.changes) end
    end
    if test.frames>32 then test.intervals[#test.intervals+1]=dt*1000 end
    if test.frames==45 then
        local step=test.steps[test.index]
        print("RENDER_BROWSER SHOT "..json.encode({id=step.id,page=step.page,view=step.view,
            camera=capture.snapshot(self).camera,renderer=self.renderer_stats}))
    end
    if test.frames>=100 then test.frames=0 end
end
return M
