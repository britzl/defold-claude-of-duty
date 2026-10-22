-- Presentation settings only: never consume simulation RNG or alter gameplay.
local atlas=require "game.render.surface_atlas"
local daylight=require "game.render.daylight"
local shadows=require "game.render.shadows"
local local_lights=require "game.render.local_lights"
local photo=require "game.render.photographic"
local M = { atlas_tile = atlas.scratch_size, surface_count = #atlas.surfaces, environment_size = daylight.environment_size,
    shadow_size = shadows.size, radiance_range = 8, max_lights = 4 }
M.views = { scene = 0, albedo = 1, normals = 2, material = 3, shadow = 4, environment = 5, hdr_probe = 6, environment_atlas = 7, cascades = 8, shadow_visibility = 9, depth = 10, geometry_normals = 11, ao = 12, contact = 13, occlusion_raw = 14, motion = 15, history = 16, reflections = 17, local_shadow = 18, glass = 19, fog_scatter = 20, fog_transmittance = 21, bloom = 22, exposure = 23, grade = 24, coverage = 25 }
-- A format constant alone does not prove renderability/filtering/blending.
-- Enable the measured backend first; qualify WebGL/mobile before expanding it.
function M.pipeline(adapter, half_float, requested)
    assert(requested=="auto" or requested=="rgba8", "render.hdr must be auto or rgba8")
    local hdr=requested=="auto" and adapter.family=="metal" and half_float~=nil
    return {hdr=hdr,format=hdr and "rgba16f" or "rgba8_encoded",backend=adapter.family,
        reason=hdr and "Metal half-float path" or requested=="rgba8" and "Explicit compatibility override"
            or "Backend awaiting HDR qualification or missing RGBA16F",
        tone_mapper="agx_neutral",output="srgb",exposure_mode="fixed"}
end
function M.defaults()
    return { render_scale=1,shadow_resolution=1024,material_lod=0,effect_density=1,decal_limit=48,shadow_cache = true, local_shadow_cache = true, combat_materials = true, combat_effects = true, heat_distortion = true, soft_particles = true, impact_decals = true, lighting = "daylight", hour = 16.5, time_rate = 0, weather_speed = 1, weather_time = 0, cloud_shadows = true, clouds = true, volumetric_fog = true, fog_shadows = true, reflections = true, glass = true, local_shadows = true, muzzle_lights = true, temporal_aa = true, weapon_aa = true, ambient_occlusion = true, contact_shadows = true, shadows = true, normal_maps = true, local_lights = true, fog = true,
        interior_lighting = true, environment_filter = true, environment_level = 0,
        bloom = true, bloom_level = 0, weathering = true, micro_detail = true, parallax = true,
        photographic_quality = "high", auto_exposure = true, bloom_strength = .14, grade_strength = 1, sharpen = .25,
        motion_blur = .15, ads_dof = 1, vignette = .18, grain = .006, exposure = 1, view = "scene", atlas_half = 0, atlas_page = 0 }
end
function M.configure(current, changes)
    local result = {}
    for k,v in pairs(current) do result[k] = v end
    for k,v in pairs(changes) do
        assert(current[k] ~= nil, "Unknown renderer setting: "..tostring(k))
        if k == "lighting" then assert(type(v)=="string" and daylight.hours[v],"Unknown lighting preset")
        elseif k=="hour" or k=="time_rate" or k=="weather_speed" or k=="weather_time" then
            local ranges={hour={0,24},time_rate={-1,1},weather_speed={0,10},weather_time={0,86400}}
            local r=ranges[k];assert(type(v)=="number" and v==v and v>=r[1] and v<=r[2],k.." is out of range")
        elseif k=="render_scale" or k=="material_lod" or k=="effect_density" or k=="decal_limit" or k=="shadow_resolution" then
            local ranges={render_scale={.5,1},material_lod={0,2},effect_density={.25,1},decal_limit={1,48},shadow_resolution={256,2048}}
            local r=ranges[k]
            assert(type(v)=="number" and v==v and v>=r[1] and v<=r[2],k.." is out of range")
            if k=="shadow_resolution" then assert(v==256 or v==512 or v==1024 or v==2048,"Invalid shadow resolution") end
            if k=="decal_limit" then assert(v==math.floor(v),"Invalid decal limit") end
        elseif k == "photographic_quality" then photo.quality(v)
        elseif photo.ranges[k] then
            local r=photo.ranges[k]
            assert(type(v)=="number" and v==v and v>=r[1] and v<=r[2], k.." is out of range")
        elseif k == "view" then assert(M.views[v], "Unknown renderer view")
        elseif k == "bloom_level" then
            assert(type(v)=="number" and v==math.floor(v) and v>=0 and v<=5,"Bloom level must be 0..5")
        elseif k == "environment_level" then
            assert(type(v)=="number" and v==math.floor(v) and v>=0 and v<=7,"Environment level must be 0..7")
        elseif k == "atlas_page" then
            local pages=math.ceil(atlas.width/1024)*math.ceil(atlas.height/1024)
            assert(type(v)=="number" and v==math.floor(v) and v>=0 and v<=pages, "Invalid atlas page")
        elseif k == "atlas_half" then
            assert(type(v)=="number" and v==math.floor(v) and v>=0 and v<=2, "Atlas half must be 0, 1 or 2")
        elseif k == "exposure" then
            assert(type(v)=="number" and v==v and v>=.25 and v<=4, "Exposure must be 0.25..4")
        else assert(type(v)=="boolean", k.." must be a boolean") end
        result[k] = v
    end
    if changes.lighting and changes.hour==nil then result.hour=daylight.hours[changes.lighting] end
    return result
end
-- Prioritize room bounds near the displayed camera, including inspection views.
-- Stable ties retain authored order and the shader's four-light budget.
function M.select_lights(lights,camera) return local_lights.rank(lights,camera) end
function M.dimensions(w,h,scale)
    if w<=0 or h<=0 then return nil end
    w,h=math.max(1,math.floor(w*(scale or 1)+.5)),math.max(1,math.floor(h*(scale or 1)+.5))
    return { width=w, height=h, occlusion_width=math.max(1,math.ceil(w/2)), occlusion_height=math.max(1,math.ceil(h/2)), bloom_width=math.max(1,math.floor(w/4)), bloom_height=math.max(1,math.floor(h/4)) }
end
function M.target_bytes(w,h,hdr,baking,options)
    local d=M.dimensions(w,h)
    if not d then return 0 end
    -- HDR radiance, RGBA8 data maps, conservative 32-bit depth; no driver overhead.
    local colour=hdr and 8 or 4
    local shadow_size=options and options.shadow_resolution or shadows.size
    return local_lights.shadow_width*local_lights.shadow_height*8*2+w*h*((colour+4)*2+44+colour*7) + d.occlusion_width*d.occlusion_height*(8+colour) + photo.bytes(w,h,hdr,options or M.defaults()) + (shadow_size*2)^2*8 + shadows.count*shadow_size^2*8
        + atlas.width*atlas.height*4*3 + (baking and atlas.width*atlas.height*4+2*atlas.scratch_size^2*4 or 0) + (daylight.environment_width*daylight.environment_height+daylight.sky_width*daylight.sky_height)*colour*4
        + daylight.sky_width*daylight.sky_height*8*2 -- packed clear scattering in both sky staging targets
end
return M
