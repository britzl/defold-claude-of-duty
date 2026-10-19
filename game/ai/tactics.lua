-- Squad intelligence contains only observed positions. Claims are encounter-wide;
-- receiving a radio report never extends its lifetime by rebroadcasting it.
local V = require "game.weapons.math"
local nav = require "game.ai.navigation"
local M = {}

function M.release_peek(ai,e)
    local squad=e.squad and ai.squads[e.squad]
    if squad and squad.peek_owner==e.id then squad.peek_owner=nil end
end
function M.release_cover(ai,e)
    M.release_peek(ai,e)
    if e.cover and ai.cover_claims[e.cover.id]==e.id then ai.cover_claims[e.cover.id]=nil end
    e.cover=nil;e.cover_peek=nil
    e.cover_phase=nil;e.peek_timer=0
end
function M.release_flank(ai,e)
    if e.flank and ai.flank_claims[e.flank.id]==e.id then ai.flank_claims[e.flank.id]=nil end
    e.flank=nil
end
function M.release(ai,e)
    M.release_cover(ai,e);M.release_flank(ai,e)
    if e.reposition and ai.position_claims then ai.position_claims[e.reposition.id]=nil end
    e.reposition=nil;e.role="patrol"
end
function M.alert(ctx,e,position,target)
    local squad=e.squad and ctx.ai.squads[e.squad]
    local lifetime=squad and 8 or 5
    target=target or {x=position.x,y=position.y+1.28,z=position.z}
    e.memory=lifetime;e.last_seen=V.copy(position);e.notice=1
    e.target_point=V.copy(target);e.contact_age=0;e.heard=nil;e.search_origin=nil;e.search_time=0
    if not squad then return end
    squad.last_seen=V.copy(position);squad.report_tick=ctx.time.tick
    for _,id in ipairs(squad.members) do
        local ally=ctx.ai.actors[id]
        if ally.actor.alive then
            ally.memory=lifetime;ally.last_seen=V.copy(position)
            ally.target_point=V.copy(target);ally.contact_age=0;ally.heard=nil;ally.search_origin=nil
        end
    end
end

local function protected(query,cover,target)
    local dx,dz=target.x-cover.x,target.z-cover.z
    return cover.height>=.75 and dx*cover.normal_x+dz*cover.normal_z<-.2
        and math.abs(target.y-cover.y)<.8
        and not query:visible({x=cover.x,y=cover.y+math.min(.55,cover.height*.6),z=cover.z},
            {x=target.x,y=target.y+1.25,z=target.z})
        and nav.distance(cover,target)<60
end
local function peek(query,cover,target)
    local chest={x=target.x,y=target.y+1.25,z=target.z}
    if query:visible({x=cover.x,y=cover.y+1.4,z=cover.z},chest) then return V.copy(cover) end
    if cover.height<1.35 or not cover.half_width then return end
    for _,side in ipairs({-1,1}) do
        local offset=(cover.half_width+.65)*side
        local p={x=cover.x-cover.normal_z*offset,y=cover.y,z=cover.z+cover.normal_x*offset}
        if query:walkable(cover,p) and (not query.fits or query:fits(p,1.78))
            and query:visible({x=p.x,y=p.y+1.4,z=p.z},chest) then return p end
    end
end
M.peek=peek
function M.cover_goal(e)
    return e.cover_phase=="peek" and e.cover_peek or e.cover
end
local function permission(ai,e)
    local squad=e.squad and ai.squads[e.squad]
    if not squad then return true end
    if squad.peek_owner then return squad.peek_owner==e.id end
    local first=e
    for _,id in ipairs(squad.members) do
        local ally=ai.actors[id]
        if ally.actor.alive and ally.cover_phase=="hide" and ally.peek_timer<=0
            and not ally.suppressed and (ally.reload_left or 0)==0
            and ((ally.last_peek or -1)<(first.last_peek or -1)
                or ((ally.last_peek or -1)==(first.last_peek or -1) and ally.index<first.index)) then first=ally end
    end
    if first~=e then return false end
    squad.peek_owner=e.id;return true
end

-- Timed exposure uses simulation time and actor index, leaving weapon RNG
-- untouched. Suppression cancels a peek immediately but retains valid cover.
function M.posture(e,dt,ai)
    local goal=M.cover_goal(e)
    local at_cover=e.cover and not e.flank and not e.reposition and e.memory>0
        and (e.cover_phase~=nil or nav.distance(e.position,goal)<=.32)
    if at_cover then
        if not e.cover_phase then e.cover_phase="hide";e.peek_timer=.75+(e.index%3)*.15 end
        e.peek_timer=math.max(0,e.peek_timer-dt)
        if e.suppressed or (e.reload_left or 0)>0 then
            if ai then M.release_peek(ai,e) end
            if e.cover_phase~="hide" then e.think=0 end
            e.cover_phase="hide";e.peek_timer=math.max(e.peek_timer,.6)
        elseif e.peek_timer==0 then
            if e.cover_phase=="peek" then
                e.cover_phase="hide";e.peek_timer=1+(e.index%3)*.1
                if ai then M.release_peek(ai,e) end
                e.think=0
            elseif not ai or permission(ai,e) then
                e.cover_phase="peek";e.peek_timer=1.3+(e.index%3)*.15+(e.cover_peek and nav.distance(e.cover,e.cover_peek)/1.5 or 0)
                e.peeks=e.peeks+1;e.last_peek=e.age;e.think=0
            end
        end
    else
        if ai then M.release_peek(ai,e) end
        e.cover_phase=nil;e.peek_timer=0
    end
    e.duck=e.suppressed or (e.cover_phase=="hide" and e.cover and e.cover.height<1.35)
end
function M.cover(ctx,e,query,options)
    local ai=ctx.ai
    if e.cover then
        local p=protected(query,e.cover,e.last_seen) and peek(query,e.cover,e.last_seen)
        if p then e.cover_peek=p;return M.cover_goal(e) end
        M.release_cover(ai,e)
    end
    if e.age<(e.cover_retry or 0) then return end
    e.cover_retry=e.age+2
    local candidates={}
    for _,c in ipairs(ctx.world.cover) do
        local distance,threat=nav.distance(e.position,c),nav.distance(e.last_seen,c)
        if not ai.cover_claims[c.id] and distance<26 and threat>3 and threat<60
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
        local p=peek(query,c,e.last_seen)
        local route=p and nav.route(ctx.world.navigation,e.position,c,query,ai.nav_cache,options)
        -- Another job can acquire this cover while clearance probes yield.
        if route and not ai.cover_claims[c.id] and protected(query,c,e.last_seen) then
            ai.cover_claims[c.id]=e.id;e.cover=c;e.cover_peek=p;e.cover_since=e.age
            e.route=route;e.route_goal=V.copy(c);e.route_age=0
            return c
        end
    end
end

function M.flank(ctx,e,query,options)
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
    if not e.squad or e.age<(e.flank_retry or 0) then return end
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
        if ally.actor.alive and ally~=engager and ally.actor.health>=34 and not ally.suppressed then flanker=ally;break end
    end
    if flanker~=e then return end
    for _,lane in ipairs(ctx.world.navigation.flanks or {}) do
        if not ai.flank_claims[lane.id] then
            local a,b=lane.points[1],lane.points[#lane.points]
            local forward=nav.distance(e.position,a)<nav.distance(e.position,b)
            local entrance,exit=forward and a or b,forward and b or a
            if math.abs(e.position.y-entrance.y)<.8 and nav.distance(e.position,entrance)<26 and nav.distance(e.last_seen,exit)+2<nav.distance(e.last_seen,entrance) then
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
    if query then
        local goal=M.reposition(ctx,e,query,options,false)
        if goal then
            local r=e.reposition
            e.flank={id=r.id,points={V.copy(goal)},index=1,target=V.copy(e.last_seen)}
            ai.flank_claims[r.id]=e.id;ai.position_claims[r.id]=nil;e.reposition=nil
            M.release_cover(ai,e);return goal
        end
    end
end

-- Pick reachable graph positions, never an unchecked point across a wall/floor.
function M.reposition(ctx,e,query,options,retreat)
    local ai=ctx.ai
    if e.reposition then
        if e.age<e.reposition.until_time and nav.distance(e.position,e.reposition)>.4 then return e.reposition end
        ai.position_claims[e.reposition.id]=nil;e.reposition=nil
        e.reposition_retry=e.age+8;return
    end
    if e.age<(e.reposition_retry or 0) then return end
    e.reposition_retry=e.age+3
    local candidates={};local current=nav.distance(e.position,e.last_seen)
    for _,n in ipairs(ctx.world.navigation.nodes) do
        local distance=nav.distance(e.position,n);local threat=nav.distance(e.last_seen,n)
        local id="position/"..n.id
        if distance>3 and distance<12 and math.abs(n.y-e.position.y)<.6 and threat>4 and threat<60
            and (not retreat or threat>current+2) and not ai.position_claims[id] and not ai.flank_claims[id] then
            local blocked=not query:visible({x=n.x,y=n.y+1.3,z=n.z},e.target_point or e.last_seen)
            local lateral=math.abs((n.x-e.position.x)*(e.last_seen.z-e.position.z)-(n.z-e.position.z)*(e.last_seen.x-e.position.x))/math.max(1,current)
            if retreat or lateral>3 then
                candidates[#candidates+1]={node=n,id=id,score=distance-(retreat and threat*.7+(blocked and 6 or 0) or lateral*.8)}
            end
        end
    end
    table.sort(candidates,function(a,b) return a.score==b.score and a.id<b.id or a.score<b.score end)
    for i=1,math.min(3,#candidates) do
        local c=candidates[i];local route=nav.route(ctx.world.navigation,e.position,c.node,query,ai.nav_cache,options)
        if route and not ai.position_claims[c.id] and not ai.flank_claims[c.id] then
            M.release_cover(ai,e);M.release_flank(ai,e)
            e.reposition=V.copy(c.node);e.reposition.id=c.id;e.reposition.until_time=e.age+7
            ai.position_claims[c.id]=e.id;e.route=route;e.route_goal=V.copy(c.node)
            e.repositions=(e.repositions or 0)+1
            if retreat then e.retreats=(e.retreats or 0)+1 end
            return e.reposition
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
