local shadows=require "game.render.shadows"
local sun=require("game.render.daylight").sun_direction
local tests=0
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
local function project(fit,p)
    local q={}
    for i,r in ipairs(fit.rows) do q[i]=dot(r,p)+r[4] end
    return q
end
test("every overlapping receiver corner fits, including wide windows and camera rotation",function()
    for _,aspect in ipairs({.5,1,16/9,3}) do for _,fov in ipairs({45,75,100}) do
        local v=math.tan(math.rad(fov/2));local h=v*aspect
        for _,yaw in ipairs({0,.7,2.1}) do
            local forward={-math.sin(yaw),0,-math.cos(yaw)}
            local right={math.cos(yaw),0,-math.sin(yaw)}
            local eye={-24,7,91}
            local fits=shadows.fit(eye,forward,h,v,sun)
            for _,fit in ipairs(fits) do for _,depth in ipairs({fit.near,fit.far}) do
                for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do
                    local p={}
                    for j=1,3 do p[j]=eye[j]+forward[j]*depth+right[j]*sx*depth*h+(j==2 and sy*depth*v or 0) end
                    local q=project(fit,p)
                    assert(math.abs(q[1])<1 and math.abs(q[2])<1 and math.abs(q[3])<1)
                    -- A caster 60 m toward the sun must not be camera-frustum culled.
                    local length=math.sqrt(dot(sun,sun))
                    for j=1,3 do p[j]=p[j]+sun[j]/length*60 end
                    q=project(fit,p);assert(math.abs(q[3])<1)
                end end
            end end
        end
    end end
end)
test("rotation preserves texel scale and all cascade overlap bands are covered",function()
    local a=shadows.fit({0,2,0},{0,0,-1},1,.7,sun)
    local b=shadows.fit({0,2,0},{1,0,0},1,.7,sun)
    for i,fit in ipairs(a) do
        assert(fit.radius==b[i].radius and fit.texel==b[i].texel)
        if i>1 then assert(math.abs(fit.near-a[i-1].blend_start)<1e-8) end
        assert(fit.blend_start<fit.far)
    end
end)
test("light-space grid moves only in whole texels and returns exactly after teleport",function()
    local eye={1,2,3};local original=shadows.fit(eye,{0,0,-1},1,.7,sun)
    for step=1,100 do
        local fits=shadows.fit({eye[1]+step*.0001,eye[2],eye[3]},{0,0,-1},1,.7,sun)
        for i,fit in ipairs(fits) do for axis=1,3 do
            local delta=(fit.centre[axis]-original[i].centre[axis])/fit.texel
            assert(math.abs(delta-math.floor(delta+.5))<1e-8)
        end end
    end
    shadows.fit({900,180,-700},{1,0,0},1,.7,sun)
    local restored=shadows.fit(eye,{0,0,-1},1,.7,sun)
    for i,fit in ipairs(original) do for j=1,3 do for k=1,4 do assert(fit.rows[j][k]==restored[i].rows[j][k]) end end end
end)
test("atlas tiles are disjoint, in bounds and preserve guard space for the filter",function()
    local fits=shadows.fit({0,0,0},{0,0,-1},1,.7,sun)
    local seen={}
    for _,fit in ipairs(fits) do
        local v=fit.viewport;local key=v[1]..":"..v[2]
        assert(not seen[key]);seen[key]=true
        assert(v[1]>=0 and v[2]>=0 and v[1]+v[3]<=shadows.atlas_size and v[2]+v[4]<=shadows.atlas_size)
        assert(shadows.guard_texels>shadows.max_filter_texels+2)
    end
end)
test("near-vertical sun and distant fixtures retain a finite shadow projection",function()
    for _,direction in ipairs({{0,1,0},{0,-1,0},sun}) do
        local fits=shadows.fit({160,3,-15},{0,0,-1},1,.7,direction)
        for _,fit in ipairs(fits) do for _,row in ipairs(fit.rows) do for _,x in ipairs(row) do assert(x==x and math.abs(x)<math.huge) end end end
    end
end)
print(tests.." shadow tests passed")
