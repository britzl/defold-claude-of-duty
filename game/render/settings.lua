-- Presentation settings only: never consume simulation RNG or alter gameplay.
local M = { atlas_tile = 256, surface_count = 5, environment_size = 64,
    shadow_size = 1024, shadow_extent = 32, radiance_range = 8, max_lights = 4 }
M.views = { scene = 0, albedo = 1, normals = 2, material = 3, shadow = 4, environment = 5 }
function M.defaults()
    return { shadows = true, normal_maps = true, local_lights = true, fog = true,
        bloom = true, exposure = 1, view = "scene" }
end
function M.configure(current, changes)
    local result = {}
    for k,v in pairs(current) do result[k] = v end
    for k,v in pairs(changes) do
        assert(current[k] ~= nil, "Unknown renderer setting: "..tostring(k))
        if k == "view" then assert(M.views[v], "Unknown renderer view")
        elseif k == "exposure" then
            assert(type(v)=="number" and v==v and v>=.25 and v<=4, "Exposure must be 0.25..4")
        else assert(type(v)=="boolean", k.." must be a boolean") end
        result[k] = v
    end
    return result
end
function M.dimensions(w,h)
    if w<=0 or h<=0 then return nil end
    return { width=w, height=h, bloom_width=math.max(1,math.floor(w/4)), bloom_height=math.max(1,math.floor(h/4)) }
end
function M.target_bytes(w,h)
    local d=M.dimensions(w,h)
    if not d then return 0 end
    -- RGBA8 colour and conservative 32-bit depth storage; excludes driver overhead.
    return w*h*16 + d.bloom_width*d.bloom_height*8 + M.shadow_size^2*8
        + M.atlas_tile^2*M.surface_count*4*3 + M.environment_size^2*6*4
end
return M
