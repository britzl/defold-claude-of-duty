-- Four persistent room slots. Incumbents get hysteresis; replacements fade via
-- zero energy, never interpolate a light through a wall. Capture resets are exact.
local M={count=4,shadow_count=2,shadow_size=256,shadow_width=768,shadow_height=1024,fade_seconds=.18}
local function distance(light,camera)
    local d=0
    for _,axis in ipairs({"x","y","z"}) do
        local v=math.max(light.minimum[axis]-camera[axis],0,camera[axis]-light.maximum[axis])
        d=d+v*v
    end
    return d
end
function M.rank(lights,camera,slots,count)
    local active={}
    for _,slot in ipairs(slots or {}) do if slot.light then active[slot.light.id]=true end end
    local candidates={}
    for i,l in ipairs(lights) do if l.kind~="sun" then
        local d=distance(l,camera)
        candidates[#candidates+1]={light=l,score=d-(active[l.id] and 2 or 0),index=i}
    end end
    table.sort(candidates,function(a,b) return a.score==b.score and a.index<b.index or a.score<b.score end)
    local result={}
    for i=1,math.min(count or M.count,#candidates) do result[i]=candidates[i].light end
    return result
end
function M.update(state,lights,camera,dt,reset,count)
    count=count or M.count
    state=state or {slots={}}
    local wanted=M.rank(lights,camera,not reset and state.slots or nil,count)
    if reset or #state.slots==0 then
        state.slots={}
        for i,l in ipairs(wanted) do state.slots[i]={light=l,gain=1} end
        return state
    end
    local keep,used={},{}
    for _,l in ipairs(wanted) do keep[l.id]=true end
    local step=math.max(0,math.min(dt,.1))/M.fade_seconds
    for _,slot in ipairs(state.slots) do
        if slot.light and keep[slot.light.id] then slot.gain=math.min(1,slot.gain+step);used[slot.light.id]=true
        else slot.gain=math.max(0,slot.gain-step);if slot.gain==0 then slot.light=nil end end
    end
    for _,l in ipairs(wanted) do if not used[l.id] then
        for i=1,count do
            local slot=state.slots[i]
            if not slot or not slot.light then state.slots[i]={light=l,gain=0};used[l.id]=true;break end
        end
    end end
    return state
end
-- Cube orientation matches environment_sampling.glsl; a 3x2 block per light.
M.directions={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
M.ups={{0,-1,0},{0,-1,0},{0,0,1},{0,0,-1},{0,-1,0},{0,-1,0}}
function M.faces(position)
    local result={}
    local eye=vmath.vector3(position.x,position.y,position.z)
    local projection=vmath.matrix4_perspective(math.pi/2,1,.025,math.max(.1,position.w))
    for i,d in ipairs(M.directions) do
        local u=M.ups[i]
        result[i]=projection*vmath.matrix4_look_at(eye,eye+vmath.vector3(d[1],d[2],d[3]),vmath.vector3(u[1],u[2],u[3]))
    end
    return result
end
-- Only position/range affect a room's shadow map. Slot gains and colours can
-- fade every frame without changing either its geometry or its projection.
function M.same_shadow_positions(a,b)
    if not a or not b then return false end
    for i=1,M.shadow_count do
        for _,axis in ipairs({"x","y","z","w"}) do
            if a[i][axis]~=b[i][axis] then return false end
        end
    end
    return true
end
return M
