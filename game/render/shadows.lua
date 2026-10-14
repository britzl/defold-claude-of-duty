-- Stable, overlapping receiver slices. Pure Lua fit math also runs in tests.
-- One 2x2 RGBA8 atlas keeps the existing single shadow sampler/target contract.
local M={count=4,size=1024,atlas_size=2048,splits={8,22,52,120},blend=.12,
    caster_distance=80,guard_texels=12,softness=.022,max_filter_texels=4}
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
local function cross(a,b) return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]} end
local function unit(a) local d=math.sqrt(dot(a,a));return {a[1]/d,a[2]/d,a[3]/d} end
function M.fit(eye,forward,tan_h,tan_v,sun)
    local z=unit(sun)
    local x=unit(cross(math.abs(z[2])>.98 and {0,0,1} or {0,1,0},z))
    local y=cross(z,x)
    local result={}
    for i,far in ipairs(M.splits) do
        local previous=i==1 and .1 or M.splits[i-1]
        local before=i<=2 and .1 or M.splits[i-2]
        -- Include the previous cascade's entire cross-fade band in this fit.
        local near=i==1 and .1 or previous-(previous-before)*M.blend
        local k2=tan_h*tan_h+tan_v*tan_v
        local distance=math.min(far,(far+near)*(1+k2)*.5)
        local radius=math.sqrt(math.max((distance-near)^2+near^2*k2,(far-distance)^2+far^2*k2))
        -- Rotation-invariant extent, padding for snap, normal bias and PCSS taps.
        radius=math.ceil(radius/(1-2*M.guard_texels/M.size)*16)/16
        local texel=2*radius/M.size
        local centre={eye[1]+forward[1]*distance,eye[2]+forward[2]*distance,eye[3]+forward[3]*distance}
        local cx=math.floor(dot(x,centre)/texel+.5)*texel
        local cy=math.floor(dot(y,centre)/texel+.5)*texel
        -- Quantize depth too, so packed caster depths do not drift sub-texel.
        local cz=math.floor(dot(z,centre)/texel+.5)*texel
        local range=2*radius+M.caster_distance
        result[i]={near=near,far=far,blend_start=far-(far-previous)*M.blend,
            radius=radius,texel=texel,range=range,centre={cx,cy,cz},
            rows={{x[1]/radius,x[2]/radius,x[3]/radius,-cx/radius},
                {y[1]/radius,y[2]/radius,y[3]/radius,-cy/radius},
                {-2*z[1]/range,-2*z[2]/range,-2*z[3]/range,(2*cz+M.caster_distance)/range}},
            viewport={(i-1)%2*M.size,math.floor((i-1)/2)*M.size,M.size,M.size}}
    end
    return result
end
function M.update(inverse_view,projection,sun,vector,matrix)
    local forward={-inverse_view.m02,-inverse_view.m12,-inverse_view.m22}
    local eye={inverse_view.m03,inverse_view.m13,inverse_view.m23}
    local fits=M.fit(eye,forward,1/projection.m00,1/projection.m11,sun)
    local data,matrices={},{}
    for i,fit in ipairs(fits) do
        local m=matrix()
        for row=0,2 do
            local r=fit.rows[row+1]
            for col=0,3 do m["m"..row..col]=r[col+1] end
            data[#data+1]=vector(r[1],r[2],r[3],r[4])
        end
        data[#data+1]=vector(fit.texel,1/fit.range,fit.far,fit.blend_start)
        matrices[i]=m
    end
    data[17]=vector(forward[1],forward[2],forward[3],-dot(forward,eye))
    data[18]=vector(1/M.atlas_size,1/M.size,M.softness,0)
    return fits,matrices,data
end
return M
