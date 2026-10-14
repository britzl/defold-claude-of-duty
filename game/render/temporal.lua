-- Presentation-only history state. Capture convergence is frame-counted, never timed.
local M={samples=8,capture_samples=32}
local function halton(index,base)
    local value,scale=0,1
    while index>0 do scale=scale/base;value=value+(index%base)*scale;index=math.floor(index/base) end
    return value
end
function M.jitter(frame)
    local i=frame%M.samples+1
    return halton(i,2)-.5,halton(i,3)-.5
end
function M.new() return {age=0,warmup=2,resets=0,reason="initial"} end
function M.reset(state,reason)
    state.age=0;state.warmup=2;state.resets=state.resets+1;state.reason=reason
end
function M.cut(previous,current)
    if not previous then return false end
    local distance=0
    for _,k in ipairs({"m03","m13","m23"}) do distance=distance+(previous[k]-current[k])^2 end
    local forward=previous.m02*current.m02+previous.m12*current.m12+previous.m22*current.m22
    return distance>4 or forward<.70710678
end
return M
