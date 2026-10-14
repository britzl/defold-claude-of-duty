-- Squad intelligence contains only observed positions. Claims are encounter-wide;
-- receiving a radio report never extends its lifetime by rebroadcasting it.
local V = require "game.weapons.math"
local nav = require "game.ai.navigation"
local M = {}

function M.release_cover(ai,e)
    if e.cover and ai.cover_claims[e.cover.id]==e.id then ai.cover_claims[e.cover.id]=nil end
    e.cover=nil
end
function M.release_flank(ai,e)
    if e.flank and ai.flank_claims[e.flank.id]==e.id then ai.flank_claims[e.flank.id]=nil end
    e.flank=nil
end
function M.release(ai,e)
    M.release_cover(ai,e);M.release_flank(ai,e)
    e.role="patrol"
end
function M.alert(ctx,e,position)
    local squad=e.squad and ctx.ai.squads[e.squad]
    local lifetime=squad and 8 or 5
    e.memory=lifetime;e.last_seen=V.copy(position);e.notice=1
    if not squad then return end
    squad.last_seen=V.copy(position);squad.report_tick=ctx.time.tick
    for _,id in ipairs(squad.members) do
        local ally=ctx.ai.actors[id]
        if ally.actor.alive then
            ally.memory=lifetime;ally.last_seen=V.copy(position)
        end
    end
end

local function protected(query,cover,target)
    local dx,dz=target.x-cover.x,target.z-cover.z
    return dx*cover.normal_x+dz*cover.normal_z<-.2
        and math.abs(target.y-cover.y)<.8
        and not query:visible({x=cover.x,y=cover.y+math.min(.55,cover.height*.6),z=cover.z},
            {x=target.x,y=target.y+1.25,z=target.z})
        and nav.distance(cover,target)<10
        and query:visible({x=cover.x,y=cover.y+1.665,z=cover.z},
            {x=target.x,y=target.y+1.25,z=target.z})
end
function M.cover(ctx,e,query)
    local ai=ctx.ai
    if e.cover then
        if protected(query,e.cover,e.last_seen) then return e.cover end
        M.release_cover(ai,e)
    end
    if e.age<(e.cover_retry or 0) then return end
    e.cover_retry=e.age+2
    local candidates={}
    for _,c in ipairs(ctx.world.cover) do
        local distance,threat=nav.distance(e.position,c),nav.distance(e.last_seen,c)
        if not ai.cover_claims[c.id] and distance<14 and threat>3 and threat<20
            and not (e.bad_cover==c.id and e.age<(e.bad_cover_until or 0))
            and protected(query,c,e.last_seen) then
            candidates[#candidates+1]={cover=c,score=distance+threat*.15}
        end
    end
    table.sort(candidates,function(a,b)
        return a.score==b.score and a.cover.id<b.cover.id or a.score<b.score
    end)
    for i=1,math.min(3,#candidates) do
        local c=candidates[i].cover
        local route=nav.route(ctx.world.navigation,e.position,c,query,ai.nav_cache)
        if route then
            ai.cover_claims[c.id]=e.id;e.cover=c
            e.route=route;e.route_goal=V.copy(c);e.route_age=0
            return c
        end
    end
end

function M.flank(ctx,e)
    local ai=ctx.ai
    if e.flank then
        if nav.distance(e.last_seen,e.flank.target)>8 then
            M.release_flank(ai,e);e.flank_retry=e.age+5;e.route_goal=nil
            return
        end
        while e.flank.points[e.flank.index]
            and nav.distance(e.position,e.flank.points[e.flank.index])<.4 do
            e.flank.index=e.flank.index+1
        end
        local goal=e.flank.points[e.flank.index]
        if goal then return goal end
        M.release_flank(ai,e);e.flank_retry=e.age+12;e.flanks_completed=e.flanks_completed+1
        return
    end
    if not e.squad or e.age<(e.flank_retry or 0) or math.abs(e.last_seen.x)>8 or e.last_seen.y>.8 then return end
    local squad=ai.squads[e.squad]
    local engager,flanker
    for _,id in ipairs(squad.members) do
        local ally=ai.actors[id]
        if ally.actor.alive and ally.state=="fire" and ally.visible and not ally.flank then engager=engager or ally end
        if ally.flank then return end
    end
    if not engager then return end
    -- Prefer the last surviving squad member, leaving a consistent lead shooter.
    for i=#squad.members,1,-1 do
        local ally=ai.actors[squad.members[i]]
        if ally.actor.alive and ally~=engager then flanker=ally;break end
    end
    if flanker~=e then return end
    for _,lane in ipairs(ctx.world.navigation.flanks or {}) do
        if not ai.flank_claims[lane.id] then
            local a,b=lane.points[1],lane.points[#lane.points]
            local forward=nav.distance(e.position,a)<nav.distance(e.position,b)
            local entrance,exit=forward and a or b,forward and b or a
            if nav.distance(e.position,entrance)<18 and nav.distance(e.last_seen,exit)+2<nav.distance(e.last_seen,entrance) then
                local points={}
                for i=1,#lane.points do points[i]=V.copy(lane.points[forward and i or (#lane.points-i+1)]) end
                M.release_cover(ai,e)
                -- Actors already in the alley join its nearest approach point,
                -- instead of walking out to the street and immediately doubling back.
                local index=1
                for i=2,math.floor(#points/2) do
                    if nav.distance(e.position,points[i])<nav.distance(e.position,points[index]) then index=i end
                end
                e.flank={id=lane.id,points=points,index=index,target=V.copy(e.last_seen)}
                ai.flank_claims[lane.id]=e.id;e.route=nil;e.route_goal=nil
                return points[index]
            end
        end
    end
end

-- Allies neither damage each other nor shoot through one another. Use a capsule-
-- sized conservative volume along the complete firing line, excluding the shooter.
function M.clear_shot(ai,e,origin,target)
    local dx,dy,dz=target.x-origin.x,target.y-origin.y,target.z-origin.z
    local length2=dx*dx+dy*dy+dz*dz
    if length2<1e-8 then return false end
    for _,id in ipairs(ai.order) do
        local other=ai.actors[id]
        if other~=e and other.actor.alive then
            local p=other.position
            local t=V.clamp(((p.x-origin.x)*dx+(p.y+.9-origin.y)*dy+(p.z-origin.z)*dz)/length2,0,1)
            local x,y,z=origin.x+dx*t,origin.y+dy*t,origin.z+dz*t
            if (x-p.x)^2+(z-p.z)^2<.5^2 and y>p.y-.1 and y<p.y+1.95 then return false end
        end
    end
    return true
end

function M.steer(ai,e,dx,dz)
    local speed=math.sqrt(dx*dx+dz*dz)
    if speed<.001 then return dx,dz end
    for _,id in ipairs(ai.order) do
        local other=ai.actors[id]
        if other~=e and other.actor.alive and math.abs(e.position.y-other.position.y)<1 then
            local x,z=e.position.x-other.position.x,e.position.z-other.position.z
            local distance=math.sqrt(x*x+z*z)
            if distance<1.05 then
                if distance<.001 then x,z,distance=e.index<other.index and -1 or 1,0,1 end
                local force=(1.05-distance)*3
                dx,dz=dx+x/distance*force,dz+z/distance*force
                -- A lateral bias breaks head-on symmetry; sweeps still own walls.
                if x*dx+z*dz<0 then dx,dz=dx-dz*.3,dz+dx*.3 end
            end
        end
    end
    local length=math.sqrt(dx*dx+dz*dz)
    if length>speed then dx,dz=dx/length*speed,dz/length*speed end
    return dx,dz
end
return M
