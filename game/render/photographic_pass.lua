-- Render-target ownership and bounded photographic passes. No gameplay state.
local photo=require "game.render.photographic"
local M={}
function M.resize(self,create)
    local resources=photo.resources(self.width,self.height,self.options)
    self.photo_resources=self.photo_resources or {}
    for name in pairs(self.photo_resources) do
        if not resources[name] then render.delete_render_target(self.targets[name]);self.targets[name]=nil end
    end
    for name,r in pairs(resources) do
        local old=self.photo_resources[name]
        if not old then self.targets[name]=create(r[1],r[2],false,not r[3] and name~="grade_lut",false,r[3] and self.radiance_format or nil)
        elseif old[1]~=r[1] or old[2]~=r[2] then render.set_render_target_size(self.targets[name],r[1],r[2]) end
    end
    self.photo_resources=resources
    self.exposure_valid=false
end
function M.draw(self,scene,weapon,dt,context,draw,bind)
    local t,o,c=self.targets,self.options,self.photo_constants
    local q=photo.quality(o.photographic_quality)
    local scene_view=o.view=="scene"
    local function pass(material,target,w,h)
        render.set_render_target(target);render.set_viewport(0,0,w,h);draw(self,material,c)
    end
    local function unbind(names) for _,name in ipairs(names) do render.disable_texture(name) end end
    if not self.grade_ready then
        pass("grade",t.grade_lut,photo.grade_size^2,photo.grade_size);self.grade_ready=true
    end
    local elapsed=photo.delta(dt,self.photo_state.paused,self.capture.active and not self.capture.temporal_live)
    if not self.capture.active then self.grain_time=(self.grain_time+elapsed)%256 end
    local lens_active=(scene_view or o.view=="bloom" or o.view=="exposure") and q.lens
    self.lens_draw_passes=0
    c.lens_screen=vmath.vector4(1/self.width,1/self.height,context.jx,context.jy)
    c.lens_motion=vmath.vector4(context.previous_jx,context.previous_jy,
        self.capture.active and 1 or 1/(60*math.max(dt or 1/60,1/240)),context.valid and not self.photo_state.paused and 1 or 0)
    c.sky_reprojection=context.sky
    if lens_active then
        bind("depth_normal_texture",t.depth_normal)
        render.enable_texture("motion_texture",t.depth_normal,graphics.BUFFER_TYPE_COLOR1_BIT)
        for _,effect in ipairs({{"photo_motion",0,o.motion_blur},{"photo_dof",1,o.ads_dof*self.photo_state.ads}}) do
            if t[effect[1]] and effect[3]>.001 then
                render.set_render_target(t[effect[1]])
                bind("source_texture",scene)
                c.lens=vmath.vector4(effect[2],effect[3],q.taps,q.radius)
                pass("lens",t[effect[1]],self.width,self.height)
                scene=t[effect[1]];self.lens_draw_passes=self.lens_draw_passes+1
            end
        end
        unbind({"source_texture","depth_normal_texture","motion_texture"})
    end
    self.exposure_draw_passes=0
    local auto=o.auto_exposure and (scene_view or o.view=="exposure" or o.view=="bloom")
    -- Capture auto exposure is a deterministic instantaneous meter. Default
    -- stills use fixed exposure; live mode is explicitly requested for adaptation.
    local capture_fixed=self.capture.active and not self.capture.temporal_live
    if auto and (not self.photo_state.paused or not self.exposure_valid or capture_fixed) then
        render.set_render_target(t.meter_1)
        bind("source_texture",scene);bind("weapon_texture",weapon);bind("depth_normal_texture",t.depth_normal);bind("previous_texture",t.exposure_b)
        c.meter=vmath.vector4(0,0,0,0)
        pass("exposure",t.meter_1,64,64)
        for i=2,#photo.meter_sizes do
            local n=photo.meter_sizes[i]
            render.set_render_target(t["meter_"..i])
            bind("source_texture",t["meter_"..(i-1)])
            c.meter=vmath.vector4(1,1/(n*4),1/(n*4),0)
            pass("exposure",t["meter_"..i],n,n)
        end
        local lo,hi=photo.exposure_limits(self.rig.night)
        c.adaptation=vmath.vector4(elapsed,(not self.exposure_valid or capture_fixed) and 1 or 0,lo,hi)
        c.meter=vmath.vector4(2,0,0,0)
        render.set_render_target(t.exposure_a)
        bind("source_texture",t.meter_4);bind("previous_texture",t.exposure_b)
        pass("exposure",t.exposure_a,1,1)
        unbind({"source_texture","previous_texture","weapon_texture","depth_normal_texture"})
        t.exposure_a,t.exposure_b=t.exposure_b,t.exposure_a
        self.exposure_valid=true;self.exposure_draw_passes=5
    elseif not auto then
        render.set_render_target(t.exposure_b)
        bind("source_texture",t.grade_lut);bind("weapon_texture",weapon)
        bind("depth_normal_texture",t.depth_normal);bind("previous_texture",t.exposure_a)
        c.meter=vmath.vector4(3,0,0,0)
        pass("exposure",t.exposure_b,1,1)
        unbind({"source_texture","previous_texture","weapon_texture","depth_normal_texture"})
        self.exposure_valid=false;self.exposure_draw_passes=1
    end
    self.bloom_draw_passes=0
    local bloom=t.bloom_up_1
    if o.bloom and (scene_view or o.view=="bloom") then
        local source=scene
        render.set_render_target(t.bloom_down_1)
        -- Bind every declared sampler, including unused branches. Leaving the
        -- upsample input unbound aliases the exposure slot on Metal overrides.
        bind("weapon_texture",weapon);bind("exposure_texture",t.exposure_b);bind("lower_texture",t.grade_lut)
        for i=1,q.levels do
            local name="bloom_down_"..i
            local r=self.photo_resources[name]
            render.set_render_target(t[name])
            bind("source_texture",source)
            local sw=i==1 and self.width or self.photo_resources["bloom_down_"..(i-1)][1]
            local sh=i==1 and self.height or self.photo_resources["bloom_down_"..(i-1)][2]
            c.bloom_step=vmath.vector4(1/sw,1/sh,i==1 and 0 or 1,o.exposure)
            pass("bloom",t[name],r[1],r[2]);source=t[name]
        end
        for i=q.levels-1,1,-1 do
            local r=self.photo_resources["bloom_up_"..i]
            local small=self.photo_resources["bloom_down_"..(i+1)]
            render.set_render_target(t["bloom_up_"..i])
            bind("source_texture",source);bind("lower_texture",t["bloom_down_"..i])
            c.bloom_step=vmath.vector4(1/small[1],1/small[2],2,o.exposure)
            pass("bloom",t["bloom_up_"..i],r[1],r[2]);source=t["bloom_up_"..i]
        end
        unbind({"source_texture","lower_texture","weapon_texture","exposure_texture"})
        self.bloom_draw_passes=q.levels*2-1
    else
        render.set_render_target(bloom);render.clear({[graphics.BUFFER_TYPE_COLOR0_BIT]=vmath.vector4()})
    end
    self.pipeline.exposure_mode=auto and (capture_fixed and "capture_metered" or "adaptive_bounded") or "fixed"
    return scene,bloom
end
return M
