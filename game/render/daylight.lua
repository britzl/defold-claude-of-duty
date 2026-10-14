-- One linear-light daylight rig for sky, direct sun, filtered IBL and shadows.
-- Static by design: time-of-day/environment updates belong to rendering step 10.
local M={
    sun_direction={-.6,.85,.4}, sun_radiance={3.6,3.1,2.45,0},
    sky_horizon={.78,.92,1.10,0}, sky_zenith={.12,.32,.72,0},
    ground_radiance={.18,.145,.10,0},
    -- Sky halo and visible disc scale with direct sunlight, retaining its colour.
    sun_shape={.22,1.7,32,.9994},
    indirect={.62,1,.18,.025}, -- diffuse gain, specular gain, interior floor, warm bounce
    environment_size=64, environment_rows=9, reflection_levels=6, max_volumes=8,
}
M.environment_stride=M.environment_size+2
M.environment_width=M.environment_stride*6
M.environment_height=M.environment_stride*M.environment_rows
function M.snapshot()
    local result={}
    for k,v in pairs(M) do
        if type(v)=="number" then result[k]=v
        elseif type(v)=="table" then result[k]={};for i,n in ipairs(v) do result[k][i]=n end end
    end
    return result
end
function M.constants(vector)
    local result={daylight_data={}}
    for i,name in ipairs({"sun_direction","sun_radiance","sky_horizon","sky_zenith","ground_radiance","sun_shape"}) do
        local v=M[name];result.daylight_data[i]=vector(v[1],v[2],v[3],v[4] or 0)
    end
    local v=M.indirect;result.indirect=vector(v[1],v[2],v[3],v[4])
    result.environment_layout=vector(M.environment_size,M.environment_stride,M.reflection_levels,M.environment_rows)
    return result
end
return M
