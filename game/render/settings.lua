-- Presentation settings only: never consume simulation RNG or alter gameplay.
local atlas=require "game.render.surface_atlas"
local daylight=require "game.render.daylight"
local shadows=require "game.render.shadows"
local M = { atlas_tile = atlas.scratch_size, surface_count = #atlas.surfaces, environment_size = daylight.environment_size,
    shadow_size = shadows.size, radiance_range = 8, max_lights = 4 }
M.views = { scene = 0, albedo = 1, normals = 2, material = 3, shadow = 4, environment = 5, hdr_probe = 6, environment_atlas = 7, cascades = 8, shadow_visibility = 9 }
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
    return { shadows = true, normal_maps = true, local_lights = true, fog = true,
        interior_lighting = true, environment_filter = true, environment_level = 0,
        bloom = true, weathering = true, micro_detail = true, parallax = true,
        exposure = 1, view = "scene", atlas_half = 0, atlas_page = 0 }
end
function M.configure(current, changes)
    local result = {}
    for k,v in pairs(current) do result[k] = v end
    for k,v in pairs(changes) do
        assert(current[k] ~= nil, "Unknown renderer setting: "..tostring(k))
        if k == "view" then assert(M.views[v], "Unknown renderer view")
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
    return result
end
-- Prioritize room bounds near the displayed camera, including inspection views.
-- Stable ties retain authored order and the shader's four-light budget.
function M.select_lights(lights,camera)
    local candidates={}
    for i,light in ipairs(lights) do
        if light.kind ~= "sun" then
            local lo,hi=light.minimum,light.maximum
            local distance=0
            for _,axis in ipairs({"x","y","z"}) do
                local d=math.max(lo[axis]-camera[axis],0,camera[axis]-hi[axis])
                distance=distance+d*d
            end
            candidates[#candidates+1]={light=light,distance=distance,index=i}
        end
    end
    table.sort(candidates,function(a,b)
        if a.distance == b.distance then return a.index<b.index end
        return a.distance<b.distance
    end)
    local selected={}
    for i=1,math.min(M.max_lights,#candidates) do selected[i]=candidates[i].light end
    return selected
end
function M.dimensions(w,h)
    if w<=0 or h<=0 then return nil end
    return { width=w, height=h, bloom_width=math.max(1,math.floor(w/4)), bloom_height=math.max(1,math.floor(h/4)) }
end
function M.target_bytes(w,h,hdr,baking)
    local d=M.dimensions(w,h)
    if not d then return 0 end
    -- HDR radiance, RGBA8 data maps, conservative 32-bit depth; no driver overhead.
    local colour=hdr and 8 or 4
    return w*h*(colour+4)*2 + d.bloom_width*d.bloom_height*colour*2 + shadows.atlas_size^2*8
        + atlas.width*atlas.height*4*3 + (baking and atlas.width*atlas.height*4+2*atlas.scratch_size^2*4 or 0) + daylight.environment_width*daylight.environment_height*colour
end
return M
