-- Render scheduling/resource contracts without a GPU. Pixel/shader checks live
-- in renderer_smoke.py and run against Defold itself.
local settings=require "game.render.settings"
local atlas=require "game.render.surface_atlas"
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
    assert(settings.target_bytes(1920,1280)==1920*1280*8*2+480*320*4*2+1024^2*8+atlas.width*atlas.height*12+64^2*6*4)
end)
test("HDR requires a qualified backend and format; compatibility remains explicit",function()
    assert(settings.pipeline({family="metal"},1,"auto").hdr)
    for _,backend in ipairs({"opengl","vulkan","null"}) do
        assert(not settings.pipeline({family=backend},1,"auto").hdr)
    end
    assert(not settings.pipeline({family="metal"},nil,"auto").hdr)
    assert(not settings.pipeline({family="metal"},1,"rgba8").hdr)
    assert(not pcall(settings.pipeline,{family="metal"},1,"unknown"))
    assert(settings.target_bytes(1280,720,true)-settings.target_bytes(1280,720,false)==7931904)
end)

test("camera light selection covers both buildings and every floor within four slots",function()
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

-- The stub records resource ownership and pass inputs; matrix maths is tested
-- by the native screenshots, rather than reimplementing vmath here.
graphics=setmetatable({},{__index=function(t,k) rawset(t,k,k);return k end})
graphics.get_adapter_info=function() return {family="metal"} end
sys={get_config_string=function(_,default) return default end}
hash=function(s) return s end
local matrix_mt={}
local function value(...) return setmetatable({x=0,y=0,z=0,w=1,args={...}},matrix_mt) end
matrix_mt.__add=function() return value() end
matrix_mt.__mul=function() return value() end
vmath={matrix4=value,matrix4_orthographic=value,matrix4_look_at=value,normalize=value,
    vector3=value,vector4=value,inv=value}
camera={get_view=value,get_projection=value}
local w,h=960,640
local targets,draws,bindings,messages={},{},{},{}
local active,material,listener
local function noop() end
render={RENDER_TARGET_DEFAULT="screen",CONTEXT_EVENT_CONTEXT_RESTORED="restored"}
for _,name in ipairs({"set_viewport","set_camera","set_view","set_projection","set_depth_mask",
    "set_stencil_mask","disable_state","enable_state","set_depth_func","clear","draw_debug3d","set_blend_func"}) do
    render[name]=noop
end
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
render.enable_texture=function(name,target) assert(not target.deleted);bindings[name]=target end
render.disable_texture=function(name) bindings[name]=nil end
render.set_listener=function(fn) listener=fn end
render.draw=function(predicate,options)
    for _,target in pairs(bindings) do assert(target~=active,"render-target feedback loop") end
    draws[#draws+1]={predicate=predicate,material=material,target=active}
end
msg={post=function(receiver,name,data) messages[#messages+1]={name=name,data=data} end}
dofile("render/game.render_script")
local self={}
test("recipes, padded mip chains and cube faces finish before the world draws",function()
    init(self)
    assert(#targets==12)
    assert(self.pipeline.hdr and self.pipeline.tone_mapper=="agx_neutral")
    for _,name in ipairs({"scene","weapon","environment","bloom_a","bloom_b"}) do
        assert(self.targets[name].params[graphics.BUFFER_TYPE_COLOR0_BIT].format==graphics.TEXTURE_FORMAT_RGBA16F)
    end
    local frames=0
    while self.bake_step<atlas.job_count do
        local previous=self.bake_step
        update(self);frames=frames+1
        assert(self.bake_step>previous and self.bake_step-previous<=8)
        assert(self.bake_draws>=self.bake_step)
        if self.bake_step<atlas.job_count then assert(self.shadow_frames==0) end
        assert(frames<atlas.job_count)
    end
    local recipes,filters,cube=0,0,0
    for _,draw in ipairs(draws) do
        if draw.material=="bake" then recipes=recipes+1 end
        if draw.material=="surface_filter" then filters=filters+1 end
        if draw.material=="environment" then cube=cube+1 end
    end
    assert(recipes==#atlas.surfaces*2 and filters==atlas.draw_count-#atlas.surfaces*2-6 and cube==6)
    assert(self.shadow_frames==1)
    update(self)
    assert(self.targets.scratch_a==nil and self.targets.atlas_spare==nil)
    assert(self.bake_draws==atlas.draw_count)
end)
test("shadow, world, weapon, post and HUD execute in order without texture feedback",function()
    draws={};update(self)
    local expected={"world_shadow","soldier_shadow","fullscreen","model","viewmodel","fullscreen","fullscreen","fullscreen","gui","debug_text"}
    assert(#draws==#expected)
    for i,name in ipairs(expected) do assert(draws[i].predicate==name,i.." "..draws[i].predicate) end
    assert(draws[1].material=="shadow" and draws[2].material=="shadow_skinned")
    assert(draws[4].target==self.targets.scene and draws[5].target==self.targets.weapon)
    assert(draws[8].target=="screen" and draws[8].material==nil)
    assert(next(bindings)==nil)
end)
test("resize reuses screen targets and leaves generated textures intact",function()
    w,h=1279,719;update(self)
    assert(#targets==12 and self.resizes==2 and self.bake_draws==atlas.draw_count)
    assert(self.targets.scene.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==1279)
    assert(self.bloom_width==319 and self.bloom_height==179)
    assert(self.targets.shadow.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==1024)
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
test("capture isolates the laboratory, hides HUD/actors, and restores ordinary passes",function()
    on_message(self,"capture_configure",{active=true,laboratory=true})
    draws={};update(self)
    assert(draws[1].predicate=="capture_lab_shadow" and draws[3].predicate=="capture_lab")
    for _,draw in ipairs(draws) do
        assert(draw.predicate~="gui" and draw.predicate~="debug_text" and draw.predicate~="soldier_shadow")
    end
    on_message(self,"capture_configure",{active=false,laboratory=false})
    draws={};update(self)
    assert(draws[2].predicate=="soldier_shadow" and draws[#draws-1].predicate=="gui")
end)
test("context restoration regenerates textures and finalization frees every target once",function()
    listener(nil,"restored");assert(self.bake_step==0)
    while self.bake_step<atlas.job_count do update(self) end
    assert(self.bake_step==atlas.job_count and self.bake_draws==atlas.draw_count*2 and #targets==15)
    final(self)
    for _,target in ipairs(targets) do assert(target.deleted) end
    assert(next(self.targets)==nil and listener==nil)
end)
print(tests.." renderer tests passed")
