-- Presentation policy shared by allocation, runtime settings and qualification.
local M={grade_size=33, meter_sizes={64,16,4,1}}
M.qualities={low={levels=3,taps=5,radius=8,lens=false},medium={levels=4,taps=9,radius=12,lens=true},high={levels=5,taps=13,radius=16,lens=true}}
M.ranges={bloom_strength={0,.5},grade_strength={0,1},sharpen={0,.5},motion_blur={0,1},ads_dof={0,1},vignette={0,.5},grain={0,.03}}
function M.quality(name) return assert(M.qualities[name],"Unknown photographic quality") end
function M.resources(w,h,o)
    local q=M.quality(o.photographic_quality)
    local r={grade_lut={M.grade_size^2,M.grade_size,false},exposure_a={1,1,false},exposure_b={1,1,false}}
    for i,n in ipairs(M.meter_sizes) do r["meter_"..i]={n,n,false} end
    for i=1,q.levels do
        local d={math.max(1,math.floor(w/2^(i+1))),math.max(1,math.floor(h/2^(i+1))),true}
        r["bloom_down_"..i]=d
        if i<q.levels then r["bloom_up_"..i]=d end
    end
    if q.lens and o.motion_blur>0 then r.photo_motion={w,h,true} end
    if q.lens and o.ads_dof>0 then r.photo_dof={w,h,true} end
    return r
end
function M.bytes(w,h,hdr,o)
    local bytes,count=0,0
    for _,r in pairs(M.resources(w,h,o)) do bytes=bytes+r[1]*r[2]*(r[3] and hdr and 8 or 4);count=count+1 end
    return bytes,count
end
function M.exposure_limits(lighting)
    local night=type(lighting)=="number" and math.max(0,math.min(1,lighting)) or lighting=="night" and 1 or 0
    return .65+.15*night,1.8-.5*night
end
-- Seconds are capped after stalls; a paused or frozen capture never evolves.
function M.delta(dt,paused,capture) return (paused or capture) and 0 or math.max(0,math.min(dt or 0,.1)) end
return M
