-- Render scheduling/resource contracts without a GPU. Pixel/shader checks live
-- in renderer_smoke.py and run against Defold itself.
local settings=require "game.render.settings"
local tests=0
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
test("settings reject unknown, mistyped and nonfinite values atomically",function()
    local original=settings.defaults()
    for _,invalid in ipairs({{exposure=0/0},{exposure=math.huge},{exposure=0},{shadows=1},{view="missing"},{unknown=true}}) do
        assert(not pcall(settings.configure,original,invalid))
    end
    local changed=settings.configure(original,{exposure=2,shadows=false,view="shadow"})
    assert(original.exposure==1 and original.shadows and changed.exposure==2 and not changed.shadows)
end)
test("minimized and tiny windows have bounded valid target dimensions",function()
    assert(not settings.dimensions(0,100) and not settings.dimensions(100,0))
    local d=settings.dimensions(1,3)
    assert(d.bloom_width==1 and d.bloom_height==1)
    assert(settings.target_bytes(1920,1280)==52969472)
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
test("loading spreads three atlas and six cubemap passes across nine frames",function()
    init(self)
    assert(#targets==9)
    for frame=1,9 do
        update(self)
        assert(self.bake_step==frame and self.bake_draws==frame)
    end
    local atlas,cube=0,0
    for _,draw in ipairs(draws) do
        if draw.material=="bake" then atlas=atlas+1 end
        if draw.material=="environment" then cube=cube+1 end
    end
    assert(atlas==3 and cube==6)
    assert(self.shadow_frames==1)
    update(self)
    assert(self.bake_draws==9)
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
    assert(#targets==9 and self.resizes==2 and self.bake_draws==9)
    assert(self.targets.scene.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==1279)
    assert(self.bloom_width==319 and self.bloom_height==179)
    assert(self.targets.shadow.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==1024)
    assert(self.targets.albedo.params[graphics.BUFFER_TYPE_COLOR0_BIT].width==1280)
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
    update(self);assert(self.shadow_frames==before+1 and self.bake_draws==9)
end)
test("context restoration regenerates textures and finalization frees every target once",function()
    listener(nil,"restored");assert(self.bake_step==0)
    for _=1,9 do update(self) end
    assert(self.bake_step==9 and self.bake_draws==18 and #targets==9)
    final(self)
    for _,target in ipairs(targets) do assert(target.deleted) end
    assert(next(self.targets)==nil and listener==nil)
end)
print(tests.." renderer tests passed")
