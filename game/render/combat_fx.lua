-- Bounded presentation-only pools. No gameplay random stream, damage or physics.
local V=require "game.weapons.math"
local M={particle_limit=24,decal_limit=32}
local function pool(n) local p={};for i=1,n do p[i]={life=0} end;return p end
function M.new()
    return {particles=pool(M.particle_limit),decals=pool(M.decal_limit),serial=0,emitted=0,impacts=0,shots=0}
end
local function spawn(state,items,kind,position,normal,size,life,colour)
    state.serial=state.serial+1
    local slot=1
    for i,e in ipairs(items) do
        if e.life<=0 then slot=i;break end
        if (e.serial or 0)<(items[slot].serial or 0) then slot=i end
    end
    local e={kind=kind,position=V.copy(position),normal=V.copy(normal or {x=0,y=0,z=1}),
        size=size,life=life,duration=life,colour=colour,serial=state.serial,
        seed=(state.serial*37%101)/101,velocity={x=0,y=0,z=0}}
    items[slot]=e;state.emitted=state.emitted+1
    return e
end
function M.impact(state,hit)
    state.impacts=state.impacts+1
    local n=hit.normal or {x=0,y=1,z=0}
    local p=V.point(hit.point,n,.008)
    local dust=hit.surface~="flesh" and hit.surface~="glass" and hit.surface~="water"
    if dust then
        local colour=hit.surface=="wood" and {.35,.24,.12} or {.48,.44,.37}
        local e=spawn(state,state.particles,0,p,n,.22,.85,colour)
        e.velocity={x=n.x*.28,y=.16+n.y*.28,z=n.z*.28}
        -- Separate entry/exit marks are allowed; moving actors never get a
        -- world-anchored decal. Depth + normal clipping restrict the receiver.
        if hit.surface~="fabric" and hit.surface~="foliage" then
            spawn(state,state.decals,2,V.point(hit.point,n,.003),n,hit.exit and .13 or .085,18,
                hit.surface=="metal" and {.18,.16,.13} or {.12,.095,.07})
        end
    end
end
function M.fire(state,position,direction,world_flash)
    state.shots=state.shots+1
    local e=spawn(state,state.particles,0,position,direction,.10,.55,{.36,.37,.38})
    e.velocity=V.point({x=0,y=.12,z=0},direction,.28)
    if world_flash then spawn(state,state.particles,1,position,direction,.22,.055,{1,.55,.12}) end
end
function M.update(state,dt)
    for _,items in ipairs({state.particles,state.decals}) do for _,e in ipairs(items) do
        if e.life>0 then
            e.life=math.max(0,e.life-dt)
            if e.kind==0 then e.position=V.point(e.position,e.velocity,dt) end
        end
    end end
end
function M.appearance(e)
    local age=1-e.life/e.duration
    if e.kind==2 then return e.size,math.min(1,e.life/2) end
    if e.kind==1 then return e.size*(.75+age*.4),1-age end
    return e.size*(1+age*2.5),math.min(1,age*12+.15)*(1-age)^2*.52
end
function M.snapshot(state)
    local p,d=0,0
    for _,e in ipairs(state.particles) do if e.life>0 then p=p+1 end end
    for _,e in ipairs(state.decals) do if e.life>0 then d=d+1 end end
    return {particles=p,decals=d,particle_limit=M.particle_limit,decal_limit=M.decal_limit,
        emitted=state.emitted,impacts=state.impacts,shots=state.shots}
end
return M
