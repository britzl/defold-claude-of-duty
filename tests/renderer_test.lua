-- Render scheduling/resource contracts without a GPU. Pixel/shader checks live
-- in renderer_smoke.py and run against Defold itself.
local settings=require "game.render.settings"
local atlas=require "game.render.surface_atlas"
local daylight=require "game.render.daylight"
local shadows=require "game.render.shadows"
local photo=require "game.render.photographic"
local tests=0
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
test("settings reject unknown, mistyped and nonfinite values atomically",function()
    local original=settings.defaults()
    for _,invalid in ipairs({{exposure=0/0},{exposure=math.huge},{exposure=0},{shadows=1},{view="missing"},{unknown=true},{atlas_half=3},{atlas_half=.5},{atlas_half=0/0}}) do
        assert(not pcall(settings.configure,original,invalid))
    end
    local changed=settings.configure(original,{exposure=2,shadows=false,view="shadow"})
    assert(original.exposure==1 and original.shadows and changed.exposure==2 and not changed.shadows)
end)
test("minimized and tiny windows have bounded valid target dimensions",function()
    assert(not settings.dimensions(0,100) and not settings.dimensions(100,0))
    local d=settings.dimensions(1,3)
    assert(d.bloom_width==1 and d.bloom_height==1)
    assert(settings.target_bytes(1920,1280)==768*1024*8+1920*1280*(8*2+44+4*7)+960*640*12+photo.bytes(1920,1280,false,settings.defaults())+shadows.atlas_size^2*8+shadows.count*shadows.size^2*8+atlas.width*atlas.height*12+(daylight.environment_width*daylight.environment_height+daylight.sky_width*daylight.sky_height)*4*4+daylight.sky_width*daylight.sky_height*16)
end)
test("HDR requires a qualified backend and format; compatibility remains explicit",function()
    assert(settings.pipeline({family="metal"},1,"auto").hdr)
    for _,backend in ipairs({"opengl","vulkan","null"}) do
        assert(not settings.pipeline({family=backend},1,"auto").hdr)
    end
    assert(not settings.pipeline({family="metal"},nil,"auto").hdr)
    assert(not settings.pipeline({family="metal"},1,"rgba8").hdr)
    assert(not pcall(settings.pipeline,{family="metal"},1,"unknown"))
    assert(settings.target_bytes(1280,720,true)-settings.target_bytes(1280,720,false)==36680544-320*180*8+3*(daylight.environment_width*daylight.environment_height+daylight.sky_width*daylight.sky_height)*4+photo.bytes(1280,720,true,settings.defaults())-photo.bytes(1280,720,false,settings.defaults()))
end)

test("camera light selection covers all enterable buildings and floors within four slots",function()
    local world=require("game.world.generator").new(require "game.world.layout")
    assert(#world.lights>settings.max_lights)
    for _,light in ipairs(world.lights) do
        if light.kind=="room" then
            local selected=settings.select_lights(world.lights,light)
            assert(#selected==settings.max_lights)
            assert(selected[1]==light,"Containing room light was omitted: "..light.id)
            local again=settings.select_lights(world.lights,light)
            for i,l in ipairs(selected) do assert(l==again[i]) end
        end
    end
end)

test("indirect volumes cover every storey but exclude exterior walls and roof terraces",function()
    local layout=require "game.world.layout"
    local world=require("game.world.generator").new(layout)
    assert(#world.lighting_volumes==8 and #world.lighting_volumes<=daylight.max_volumes)
    local function contains(v,p,inset)
        for i=1,3 do if p[i]<v.minimum[i]+inset or p[i]>v.maximum[i]-inset then return false end end
        return true
    end
    for _,b in ipairs(layout.buildings) do if b.room then
        local volume
        for _,v in ipairs(world.lighting_volumes) do if v.id==b.id then volume=v end end
        assert(volume)
        for floor=0,b.floors-1 do
            local y=layout.street.walk_height+floor*layout.storey
            assert(contains(volume,{b.x,y,b.z},volume.params[3]))
            assert(contains(volume,{b.x+b.side*(b.w/2-layout.wall),y+1,b.z},volume.params[3]-.00001))
            assert(not contains(volume,{b.x+b.side*b.w/2,y+1,b.z},volume.params[2]))
        end
        assert(not contains(volume,{b.x,layout.street.walk_height+b.floors*layout.storey,b.z},0))
        assert(volume.doorway[1]==b.x+b.side*b.w/2 and volume.aperture[1]==b.door.width)
        assert(volume.params[1]==daylight.indirect[3])
    end end
end)
test("capture lighting metadata and world sun come from the same daylight rig",function()
    local catalog=require("game.render.capture").catalog()
    local sun=require("game.world.generator").new(require "game.world.layout").lights[1].direction
    assert(sun.x==catalog.lighting.sun_direction[1] and sun.y==catalog.lighting.sun_direction[2])
    assert(catalog.lighting.rig.sun_radiance[1]==daylight.sun_radiance[1])
    catalog.lighting.rig.sun_radiance[1]=999
    assert(daylight.sun_radiance[1]~=999)
    for _,bad in ipairs({-1,8,.5,0/0}) do assert(not pcall(settings.configure,settings.defaults(),{environment_level=bad})) end
end)

-- The stub records resource ownership and pass inputs; matrix maths is tested
-- by the native screenshots, rather than reimplementing vmath here.
graphics=setmetatable({},{__index=function(t,k) rawset(t,k,k);return k end})
graphics.get_adapter_info=function() return {family="metal"} end
sys={get_config_string=function(_,default) return default end}
hash=function(s) return s end
local matrix_mt={}
local function value(...) return setmetatable({x=0,y=0,z=0,w=1,m00=1,m10=0,m20=0,m01=0,m21=0,m11=1,m02=0,m12=0,m22=1,m03=0,m13=0,m23=0,args={...}},matrix_mt) end
matrix_mt.__add=function() return value() end
matrix_mt.__mul=function() return value() end
vmath={matrix4=value,matrix4_perspective=value,matrix4_orthographic=value,matrix4_look_at=value,normalize=value,
    vector3=value,vector4=function(...) local v=value(...);v.w=select(4,...) or 0;return v end,inv=value}
camera={get_view=value,get_projection=value}
local w,h=960,640
local targets,draws,bindings,messages={},{},{},{}
local texture_attachments={}
local active,material,listener
local depth_mask,depth_func
local function noop() end
render={RENDER_TARGET_DEFAULT="screen",CONTEXT_EVENT_CONTEXT_RESTORED="restored"}
render.FRUSTUM_PLANES_ALL="all_planes"
for _,name in ipairs({"set_viewport","set_camera","set_view","set_projection","set_depth_mask",
    "set_stencil_mask","disable_state","enable_state","set_depth_func","clear","draw_debug3d","set_blend_func"}) do
    render[name]=noop
end
render.set_depth_mask=function(value) depth_mask=value end
render.set_depth_func=function(value) depth_func=value end
render.get_window_width=function() return w end
render.get_window_height=function() return h end
render.predicate=function(tags) return tags[1] end
render.constant_buffer=function() return {} end
render.render_target=function(params)
    local target={params=params,deleted=false,id=#targets+1};targets[#targets+1]=target;return target
end
render.set_render_target_size=function(target,width,height)
    for _,params in pairs(target.params) do
        if type(params)=="table" then params.width=width;params.height=height end
    end
end
render.delete_render_target=function(target) assert(not target.deleted);target.deleted=true end
render.set_render_target=function(target,options) active=target end
render.enable_material=function(name) material=name end
render.disable_material=function() material=nil end
render.enable_texture=function(name,target,attachment) assert(not target.deleted);bindings[name]=target;texture_attachments[name]=attachment end
render.disable_texture=function(name) bindings[name]=nil;texture_attachments[name]=nil end
render.set_listener=function(fn) listener=fn end
render.draw=function(predicate,options)
    if material=="atmosphere" or material=="atmosphere_copy" then
        for name,attachment in pairs({scattering_texture=graphics.BUFFER_TYPE_COLOR1_BIT,scattering_fine_texture=graphics.BUFFER_TYPE_COLOR2_BIT}) do
            assert(texture_attachments[name]==attachment and bindings[name].params[attachment],"Missing clear-sky cache attachment")
            assert(active.params[attachment].format==graphics.TEXTURE_FORMAT_RGBA)
        end
    end
    if material=="shadow_copy" then
        assert(bindings.source_texture and bindings.source_texture==bindings.source_depth,"Missing matching cached colour/depth")
        assert(depth_mask and depth_func==graphics.COMPARE_FUNC_ALWAYS,"Cached depth must overwrite the destination")
        assert(bindings.source_depth.params[graphics.BUFFER_TYPE_DEPTH_BIT].flags==render.TEXTURE_BIT)
    end
    if options and options.frustum then
        assert(options.frustum_planes==render.FRUSTUM_PLANES_ALL,"3D draw omitted near/far culling")
    end
    for _,target in pairs(bindings) do assert(target~=active,"render-target feedback loop") end
    if material=="shadow" or material=="local_shadow" or material=="prepass" or predicate=="capture_lab" or predicate=="model" then
        assert(bindings.coverage_texture,"Missing foliage mask in "..tostring(material or predicate))
        assert(#options.constants.coverage_rects==11,"Missing cutout mip rectangles")
        assert(options.constants.coverage_info.args[2]==atlas.surfaces[20].size)
    end
    if material=="bloom" then
        for _,name in ipairs({"source_texture","lower_texture","weapon_texture","exposure_texture"}) do
            assert(bindings[name],"Missing bloom sampler "..name)
        end
    elseif material=="exposure" then
        for _,name in ipairs({"source_texture","previous_texture","weapon_texture","depth_normal_texture"}) do
            assert(bindings[name],"Missing exposure sampler "..name)
        end
    end
    if predicate=="viewmodel" then assert(not bindings.occlusion_texture,"Weapon sampled world AO") end
    draws[#draws+1]={predicate=predicate,material=material,target=active,scene_texture=bindings.scene_texture,weapon_texture=bindings.weapon_texture,
        scattering_reuse=material=="atmosphere" and options.constants.bake_region.args[3] or nil}
end
msg={post=function(receiver,name,data) messages[#messages+1]={name=name,data=data} end}
local function renderer_stats()
    for i=#messages,1,-1 do
        if messages[i].name=="renderer_stats" then return messages[i].data end
    end
end
-- Each of these API calls queues one Defold render-script command. Count the
-- real calls made by the renderer so additions cannot silently exceed 1024.
local commands=0
for _,name in ipairs({"set_camera","set_view","set_projection","set_depth_mask",
    "set_stencil_mask","disable_state","enable_state","set_depth_func","clear",
    "draw_debug3d","set_blend_func","set_viewport","set_render_target",
    "enable_material","disable_material","enable_texture","disable_texture","draw"}) do
    local original=render[name]
    render[name]=function(...) commands=commands+1;return original(...) end
end
dofile("render/game.render_script")
local render_update=update
update=function(state,dt)
    commands=0
    render_update(state,dt)
    assert(commands<=1024,"Render command capacity exceeded: "..commands)
end
local self={}
test("recipes, padded mip chains and filtered environment finish before the world draws",function()
    init(self)
    assert(#self.lighting.surface_infos==#atlas.surfaces)
    for i,s in ipairs(atlas.surfaces) do
        assert(self.lighting.surface_infos[i].args[1]==s.metres)
        assert(self.lighting.surface_infos[i].args[2]==s.size)
        assert(self.lighting.surface_parameters[i].args[1]==s.parallax)
    end
    assert(#targets==53)
    assert(self.pipeline.hdr and self.pipeline.tone_mapper=="agx_neutral")
    for _,name in ipairs({"scene","weapon","environment","bloom_down_1","bloom_up_1"}) do
        assert(self.targets[name].params[graphics.BUFFER_TYPE_COLOR0_BIT].format==graphics.TEXTURE_FORMAT_RGBA16F)
    end
    local frames,max_jobs=0,0
    while self.bake_step<atlas.job_count do
        local previous=self.bake_step
        update(self);frames=frames+1
        assert(self.bake_step>previous)
        max_jobs=math.max(max_jobs,self.bake_step-previous)
        assert(self.bake_draws>=self.bake_step)
        assert(self.shadow_frames==0,"Scene draws shared a bake command buffer")
        assert(not renderer_stats().ready,"Reported ready before the first scene frame")
        assert(frames<atlas.job_count)
    end
    assert(max_jobs>16 and frames<60,"Loading still waits on small fixed batches")
    assert(self.bake_frames==frames and self.bake_peak_commands<=896)
    local recipes,filters,cube=0,0,0
    for _,draw in ipairs(draws) do
        if draw.material=="bake" then recipes=recipes+1 end
        if draw.material=="surface_filter" then filters=filters+1 end
        if draw.material=="environment" then cube=cube+1 end
    end
    assert(recipes==#atlas.surfaces*2 and filters==atlas.draw_count-#atlas.surfaces*2-1 and cube==1)
    assert(self.shadow_frames==0)
    update(self)
    assert(self.shadow_frames==1 and renderer_stats().ready)
    assert(self.targets.scratch_a==nil and self.targets.atlas_spare==nil)
    assert(self.bake_draws==atlas.draw_count)
end)
test("shadow, world, weapon, post and HUD execute in order without texture feedback",function()
    draws={};update(self)
    local positions={}
    for i,d in ipairs(draws) do
        if d.material then positions[d.material]=i end
        if d.target=="screen" and d.predicate=="fullscreen" then positions.composite=i end
        if d.predicate=="gui" then positions.gui=i end
    end
    assert(positions.temporal<positions.lens and positions.lens<positions.exposure)
    assert(positions.exposure<positions.bloom and positions.bloom<positions.composite and positions.composite<positions.gui)
    assert(draws[1].material=="shadow" and draws[2].material=="shadow_skinned")
    assert(next(bindings)==nil)
end)
test("flash resolves in linear light without target feedback and retains weapon coverage",function()
    on_message(self,"renderer_weapon_flash",{active=true})
    draws={};update(self)
    local flash,resolve,aa
    for _,d in ipairs(draws) do
        if d.predicate=="viewmodel_flash" then flash=d end
        if d.material=="weapon_composite" then resolve=d end
        if d.material=="weapon_aa" then aa=d end
    end
    assert(flash and flash.target==self.targets.glass)
    assert(resolve and resolve.target==self.targets.weapon_aa)
    assert(aa and aa.target==self.targets.weapon)
    on_message(self,"renderer_configure",{weapon_aa=false})
    draws={};update(self)
    for _,d in ipairs(draws) do if d.target=="screen" and d.predicate=="fullscreen" then
        assert(d.weapon_texture==self.targets.weapon_aa)
    end end
    on_message(self,"renderer_weapon_flash",{active=false})
    on_message(self,"renderer_configure",{weapon_aa=true})
end)
test("heat distortion uses a separate offset target and skips work when disabled",function()
    on_message(self,"renderer_combat_state",{haze=2})
    draws={};update(self)
    assert(self.haze_draw_passes==2)
    local haze,warp
    for i,d in ipairs(draws) do
        if d.predicate=="combat_haze" then haze=i;assert(d.target==self.targets.haze) end
        if d.material=="haze_composite" then warp=i;assert(d.target==self.targets.reflected) end
    end
    assert(haze and warp and haze<warp)
    on_message(self,"renderer_configure",{heat_distortion=false});update(self);assert(self.haze_draw_passes==0)
    on_message(self,"renderer_configure",{heat_distortion=true});on_message(self,"renderer_combat_state",{haze=0})
    update(self);assert(self.haze_draw_passes==0)
end)
test("resize reuses screen targets and leaves generated textures intact",function()
    w,h=1279,719;update(self)
    assert(#targets==53 and self.resizes==2 and self.bake_draws==atlas.draw_count)
    assert(self.targets.scene.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==1279)
    assert(self.bloom_width==319 and self.bloom_height==179)
    assert(self.occlusion_width==640 and self.occlusion_height==360)
    assert(self.targets.depth_normal.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==1279)
    assert(self.targets.occlusion_raw.params[graphics.BUFFER_TYPE_COLOR0_BIT].height==360)
    assert(self.targets.shadow.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==shadows.atlas_size)
    assert(self.targets.albedo.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==atlas.width)
    local count=#draws;w=0;update(self);assert(#draws==count)
    w=1279;update(self);assert(self.resizes==2)
end)
test("disabled effects stop their passes and re-enable without rebaking",function()
    local before=self.shadow_frames
    on_message(self,"renderer_configure",{shadows=false,bloom=false})
    draws={};update(self)
    assert(self.shadow_frames==before)
    for _,draw in ipairs(draws) do assert(draw.material~="shadow" and draw.material~="shadow_skinned" and draw.material~="bloom") end
    on_message(self,"renderer_configure",{shadows=true,bloom=true})
    update(self);assert(self.shadow_frames==before+1 and self.bake_draws==atlas.draw_count)
end)
test("occlusion toggles skip work, diagnostics retain depth, and weapon never samples world AO",function()
    on_message(self,"renderer_configure",{ambient_occlusion=false,contact_shadows=false,temporal_aa=false,reflections=false,glass=false,fog=false,combat_effects=false,auto_exposure=false,motion_blur=0,ads_dof=0})
    draws={};update(self)
    assert(self.prepass_draw_passes==0 and self.occlusion_draw_passes==0)
    for _,draw in ipairs(draws) do assert(draw.material~="prepass" and draw.material~="occlusion") end
    on_message(self,"renderer_configure",{combat_effects=true});update(self)
    assert(self.prepass_draw_passes==3,"Soft particles must retain opaque depth without other screen effects")
    on_message(self,"renderer_configure",{view="depth"});update(self)
    assert(self.prepass_draw_passes==3 and self.occlusion_draw_passes==0)
    on_message(self,"renderer_configure",{view="scene",ambient_occlusion=true});update(self)
    assert(self.prepass_draw_passes==3 and self.occlusion_draw_passes==2)
    assert(self.occlusion_constants.occlusion_params.args[3]==1 and self.occlusion_constants.occlusion_params.args[4]==0)
    on_message(self,"renderer_configure",{contact_shadows=true,fog=true});update(self)
end)
test("capture isolates the laboratory, hides HUD/actors, and restores ordinary passes",function()
    on_message(self,"capture_configure",{active=true,laboratory=true})
    for _=1,19 do update(self) end
    draws={};update(self)
    assert(draws[1].predicate=="capture_lab_shadow" and draws[9].predicate=="capture_lab")
    for _,draw in ipairs(draws) do
        assert(draw.predicate~="gui" and draw.predicate~="debug_text" and draw.predicate~="soldier_shadow")
    end
    on_message(self,"capture_configure",{active=false,laboratory=false})
    draws={};update(self)
    assert(draws[2].predicate=="soldier_shadow" and draws[#draws-1].predicate=="gui")
end)
test("volume updates clear stale slots and laboratory capture isolates world volumes",function()
    local volumes=require("game.world.generator").new(require "game.world.layout").lighting_volumes
    on_message(self,"renderer_volumes",{count=#volumes})
    for i,volume in ipairs(volumes) do
        on_message(self,"renderer_volumes",{index=i,volume=volume})
        assert(self.lighting.volume_data[(i-1)*5+1].args[1]==volume.minimum[1])
    end
    update(self)
    assert(self.volume_count==8 and #self.lighting.volume_data==40)
    assert(self.lighting.lighting_features.args[1]==1 and self.lighting.lighting_features.args[3]==8)
    on_message(self,"capture_configure",{active=true,laboratory=true});update(self)
    assert(self.lighting.lighting_features.args[1]==0)
    on_message(self,"capture_configure",{active=false,laboratory=false});update(self)
    assert(self.lighting.lighting_features.args[1]==1)
    on_message(self,"renderer_volumes",{count=1})
    on_message(self,"renderer_volumes",{index=1,volume=volumes[1]})
    assert(self.volume_count==1 and (self.lighting.volume_data[6].args[1] or 0)==0)
    on_message(self,"renderer_configure",{interior_lighting=false,environment_filter=false});update(self)
    assert(self.lighting.lighting_features.args[1]==0 and self.lighting.lighting_features.args[2]==0)
end)
test("capture history converges, holds and invalidates without retaining stale targets",function()
    on_message(self,"renderer_configure",{temporal_aa=true,weapon_aa=true,view="scene"})
    on_message(self,"capture_configure",{active=true,laboratory=false})
    for _=1,60 do update(self) end
    assert(self.temporal.age==32 and self.temporal_draw_passes==0)
    local held=self.targets.history_b
    update(self);assert(self.targets.history_b==held)
    on_message(self,"renderer_reset_history",{reason="teleport"})
    for _=1,3 do update(self) end;assert(self.temporal.age==1 and self.temporal.reason=="teleport")
    assert(self.targets.history_b~=held)
    on_message(self,"capture_configure",{active=true,laboratory=false,temporal_live=true})
    for _=1,40 do update(self) end
    assert(self.temporal.age==20 and self.temporal_draw_passes==1)
    on_message(self,"capture_configure",{active=false,laboratory=false})
end)
test("world and weapon antialiasing can be toggled independently",function()
    on_message(self,"renderer_configure",{temporal_aa=false,weapon_aa=true})
    update(self);assert(self.temporal.age==0 and self.temporal_draw_passes==0 and self.weapon_aa_draw_passes==1)
    on_message(self,"renderer_configure",{temporal_aa=true,weapon_aa=false})
    for _=1,3 do update(self) end;assert(self.temporal.age==1 and self.temporal_draw_passes==1 and self.weapon_aa_draw_passes==0)
    on_message(self,"renderer_configure",{weapon_aa=true})
end)
test("temporal diagnostics have their own output and never replace radiance history",function()
    on_message(self,"renderer_configure",{view="history"})
    draws={};update(self)
    assert(self.temporal_draw_passes==2 and self.weapon_aa_draw_passes==0)
    local temporal_targets={}
    for _,draw in ipairs(draws) do
        if draw.material=="temporal" then temporal_targets[#temporal_targets+1]=draw.target end
        if draw.target=="screen" and draw.material==nil and draw.predicate=="fullscreen" then assert(draw.scene_texture==self.targets.weapon_aa) end
    end
    assert(temporal_targets[1]==self.targets.history_b and temporal_targets[2]==self.targets.weapon_aa)
    on_message(self,"renderer_configure",{view="scene"});update(self)
    assert(self.temporal_constants.temporal_params.args[4]==0 and self.temporal_draw_passes==1)
end)
test("lighting and cloud changes stage complete pairs within the command budget",function()
    local previous=self.environment_updates
    local function seek(changes)
        on_message(self,"renderer_configure",changes)
        local before=self.environment_updates
        for i=1,18 do
            draws={};update(self,1/60)
            assert(self.environment_updates==before and self.weather_draws<=2)
        end
        update(self,1/60)
        assert(self.environment_updates==before+1 and self.bake_draws==atlas.draw_count)
    end
    seek({lighting="sunset"})
    assert(self.rig.hour==19.2 and self.temporal.reason=="atmosphere_seek")
    local sun=daylight.rig("sunset").sun_direction
    assert(self.lighting.daylight_data[1].args[2]==sun[2])
    seek({clouds=false})
    assert(self.bake_constants.atmosphere_data[3].args[3]==0)
    seek({lighting="daylight",clouds=true})
    assert(self.environment_updates==previous+3)
end)
test("fog uses world depth, supports analytic fallback, and skips all work when disabled",function()
    on_message(self,"renderer_configure",{fog=true,volumetric_fog=true})
    draws={};update(self)
    assert(self.atmosphere_draw_passes==2)
    local march,resolve,aa
    for i,d in ipairs(draws) do
        if d.material=="fog" then march=i;assert(d.target==self.targets.fog_raw) end
        if d.material=="fog_composite" then resolve=i;assert(d.target==self.targets.fog_scene) end
        if d.material=="temporal" then aa=i end
    end
    assert(march<resolve and resolve<aa)
    on_message(self,"renderer_configure",{volumetric_fog=false});update(self)
    assert(self.atmosphere_draw_passes==1)
    on_message(self,"renderer_configure",{fog=false});update(self)
    assert(self.atmosphere_draw_passes==0)
    on_message(self,"renderer_configure",{view="fog_scatter"});update(self)
    assert(self.atmosphere_draw_passes==1 and self.temporal.age==0)
    on_message(self,"renderer_configure",{view="scene",fog=true,volumetric_fog=true});update(self)
end)
test("photographic metering pauses, captures lock time, diagnostics bypass lens and presets release memory",function()
    on_message(self,"renderer_configure",{auto_exposure=true,motion_blur=.15,ads_dof=1,photographic_quality="high",view="scene"})
    on_message(self,"renderer_photographic_state",{ads=1,paused=false})
    for _=1,40 do update(self,1/60) end
    assert(self.exposure_draw_passes==5 and self.bloom_draw_passes==9 and self.lens_draw_passes==2)
    local time=self.grain_time
    on_message(self,"renderer_photographic_state",{ads=1,paused=true});update(self,1)
    assert(self.grain_time==time and self.exposure_draw_passes==0)
    on_message(self,"capture_configure",{active=true,laboratory=false})
    for _=1,40 do update(self,1) end
    assert(self.grain_time==time and self.pipeline.exposure_mode=="capture_metered")
    assert(self.photo_constants.adaptation.args[1]==0 and self.photo_constants.adaptation.args[2]==1)
    on_message(self,"renderer_configure",{view="depth"});update(self,1/60)
    assert(self.lens_draw_passes==0 and self.bloom_draw_passes==0 and self.pipeline.exposure_mode=="fixed")
    local old=self.targets.photo_dof
    on_message(self,"renderer_configure",{photographic_quality="low",view="scene"});update(self,1/60)
    assert(old.deleted and not self.targets.photo_dof and self.bloom_draw_passes==5)
    on_message(self,"renderer_configure",{photographic_quality="high"});update(self,1/60)
    assert(self.targets.photo_dof~=old and self.bloom_draw_passes==9)
    on_message(self,"capture_configure",{active=false,laboratory=false})
end)
test("static shadow caching copies depth and redraws animated casters every frame",function()
    on_message(self,"renderer_world_ready",{})
    on_message(self,"renderer_configure",{shadows=true,shadow_cache=true})
    draws={};update(self)
    assert(self.shadow_static_draw_passes==4 and self.shadow_copy_draw_passes==4 and self.shadow_dynamic_draw_passes==4)
    local count=self.shadow_cache_refreshes
    draws={};update(self)
    assert(self.shadow_static_draw_passes==0 and self.shadow_copy_draw_passes==4 and self.shadow_dynamic_draw_passes==4)
    assert(self.shadow_cache_refreshes==count)
    for _,draw in ipairs(draws) do if draw.material=="shadow_copy" then assert(draw.target==self.targets.shadow) end end
    on_message(self,"renderer_reset_history",{reason="teleport"});update(self)
    assert(self.shadow_static_draw_passes==4)
    on_message(self,"capture_configure",{active=true,laboratory=true});update(self)
    assert(self.shadow_static_draw_passes==4 and self.shadow_dynamic_draw_passes==0)
    update(self);assert(self.shadow_static_draw_passes==0 and self.shadow_dynamic_draw_passes==0)
    on_message(self,"renderer_configure",{shadow_cache=false});update(self)
    assert(self.shadow_static_draw_passes==4 and self.shadow_copy_draw_passes==0)
    on_message(self,"renderer_configure",{shadow_cache=true,shadows=false});update(self)
    assert(self.shadow_draw_passes==0 and self.shadow_copy_draw_passes==0)
    on_message(self,"renderer_configure",{shadows=true});update(self)
    assert(self.shadow_static_draw_passes==4)
    on_message(self,"capture_configure",{active=false,laboratory=false})
end)
test("continuous weather fits command capacity and retains history and allocations",function()
    on_message(self,"capture_configure",{active=false,laboratory=false})
    on_message(self,"renderer_photographic_state",{ads=0,paused=false})
    on_message(self,"renderer_world_ready",{})
    on_message(self,"renderer_configure",{weather_speed=10,time_rate=.1,view="scene",temporal_aa=true})
    for _=1,30 do update(self,1/60) end
    local resets,count,previous=self.temporal.resets,#targets,self.environment_updates
    for _=1,120 do update(self,1/60);assert(self.temporal.resets==resets and #targets==count and self.weather_draws<=2) end
    assert(self.environment_updates>previous+2)
    on_message(self,"renderer_photographic_state",{ads=0,paused=true})
    local hour,time,stage=self.weather.hour,self.weather.time,self.weather.stage
    for _=1,30 do update(self,1) end
    assert(self.weather.hour==hour and self.weather.time==time and self.weather.stage==stage)
    on_message(self,"renderer_configure",{weather_speed=0,time_rate=0})
end)
test("weather reuses scattering; changed and interrupted celestial bakes invalidate it",function()
    on_message(self,"capture_configure",{active=true,laboratory=false})
    local function complete(changes,integrations)
        on_message(self,"renderer_configure",changes)
        draws={}
        for _=1,19 do update(self,1/60);assert(self.weather_draws<=2) end
        local sky,misses=0,0
        for _,draw in ipairs(draws) do if draw.material=="atmosphere" then
            sky=sky+1;if draw.scattering_reuse==0 then misses=misses+1 end
        end end
        assert(sky==8 and misses==integrations,"Unexpected scattering work: "..misses)
        assert(self.scattering_rig==self.weather.rig and self.weather.stage==0)
    end
    complete({hour=12,weather_time=0,clouds=true},8)
    local initial=self.scattering_updates
    complete({weather_time=120},0)
    complete({weather_time=0,clouds=false},0)
    complete({clouds=true},0)
    assert(self.scattering_updates==initial)
    -- Return to the cached hour after only three strips have been overwritten.
    on_message(self,"renderer_configure",{hour=18})
    for _=1,4 do update(self,1/60) end
    assert(self.scattering_rig==nil)
    complete({hour=12},8)
    assert(self.scattering_updates==initial+1)
    complete({hour=1.5},8)
    complete({weather_time=120},0)
    assert(self.scattering_updates==initial+2)
end)
test("context restoration regenerates textures and finalization frees every target once",function()
    local scattering=self.scattering_updates
    listener(nil,"restored");assert(self.bake_step==0)
    assert(self.shadow_cached_fits==nil and self.scattering_rig==nil)
    while self.bake_step<atlas.job_count do update(self) end
    assert(self.scattering_updates==scattering+1 and self.scattering_rig==self.weather.rig)
    assert(self.bake_step==atlas.job_count and self.bake_draws==atlas.draw_count*2)
    final(self)
    for _,target in ipairs(targets) do assert(target.deleted) end
    assert(next(self.targets)==nil and listener==nil)
end)
test("OpenGL resize replaces complete depth/MRT targets without rebaking maps",function()
    graphics.get_adapter_info=function() return {family="opengl"} end
    local web={}
    init(web)
    while web.bake_step<atlas.job_count do update(web) end
    for _,size in ipairs({{961,641},{1279,719},{960,640}}) do
        local previous={}
        for name,target in pairs(web.targets) do previous[name]=target end
        local resets=web.temporal.resets
        w,h=size[1],size[2];update(web)
        for _,name in ipairs({"scene","weapon","depth_normal","depth_previous"}) do
            assert(previous[name].deleted and web.targets[name]~=previous[name])
            for _,attachment in pairs(web.targets[name].params) do
                assert(attachment.width==w and attachment.height==h)
            end
        end
        assert(web.targets.weapon.params[graphics.BUFFER_TYPE_DEPTH_BIT].flags==render.TEXTURE_BIT)
        for _,name in ipairs({"albedo","normal","material","sky","environment","shadow","shadow_static_1","photo_motion"}) do
            assert(web.targets[name]==previous[name] and not previous[name].deleted)
        end
        assert(web.bake_draws==atlas.draw_count and web.temporal.resets==resets+1)
        local allocations=#targets;update(web);assert(#targets==allocations)
    end
    final(web)
    for _,target in ipairs(targets) do assert(target.deleted) end
end)
test("all atlas qualities and context rebakes fit the command buffer",function()
    local original=atlas.new(atlas.quality)
    for _,quality in ipairs({"low","medium","high"}) do
        for key,value in pairs(atlas.new(quality)) do atlas[key]=value end
        local state={};init(state)
        local peak_commands=0
        for cycle=1,2 do
            if cycle==2 then listener(nil,"restored") end
            local frames=0
            while state.bake_step<atlas.job_count do
                update(state);frames=frames+1
                peak_commands=math.max(peak_commands,commands)
                assert(not renderer_stats().ready)
                assert(frames<60,"Bake scheduling regressed: "..quality)
            end
            assert(state.bake_draws==atlas.draw_count*cycle)
            update(state)
            assert(renderer_stats().ready and state.targets.scratch_a==nil)
        end
        print("BAKE",quality,"updates",state.bake_frames/2,"peak commands",peak_commands)
        final(state)
    end
    for key,value in pairs(original) do atlas[key]=value end
end)
print(tests.." renderer tests passed")
