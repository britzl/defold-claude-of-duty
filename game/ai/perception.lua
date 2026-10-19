-- Evidence is copied at observation time. Hearing never grants a firing target.
local V=require "game.weapons.math"
local nav=require "game.ai.navigation"
local tactics=require "game.ai.tactics"
local suppression=require "game.ai.suppression"
local M={view_range=58,suppress_time=2.2,hearing={shot=90,step=11,run=24,explosion=120}}
function M.init(e)
    e.contact_age=1000;e.sense_timer=0;e.heard=nil;e.heard_age=1000;e.heard_count=0
    e.search_time=0;e.searches=0;e.investigations=0
end
function M.clear(e)
    e.memory=0;e.notice=0;e.visible=false;e.last_seen=nil;e.target_point=nil;e.contact_age=1000
    e.heard=nil;e.heard_age=1000;e.search_time=0;e.search_origin=nil
end
function M.hear(ctx,event,kind)
    if ctx.paused or ctx.capture_active or not ctx.ai.enabled or not ctx.player.enabled or not ctx.player.actor.alive then return end
    if kind~="explosion" and event.source and event.source~="player" then return end
    local point=event.origin or event.position
    if not point then return end
    local radius=M.hearing[kind]
    for _,id in ipairs(ctx.ai.order) do
        local e=ctx.ai.actors[id]
        if e.actor.alive and event.source~=e.id then
            local distance=nav.distance(e.position,point)
            if distance<radius then
                local service=ctx.services.soldiers
                local q=service and service.api.query(service,e) or e.query
                local audible=q and q:visible(suppression.eye(e),{x=point.x,y=point.y+.08,z=point.z})
                local reach=radius*(audible and 1 or .45)
                if distance<reach then
                    e.heard_count=e.heard_count+1
                    -- Preserve recent visual evidence over a less precise noise.
                    if e.contact_age>1.2 then
                        local p=V.copy(point)
                        local floor=q and q.ray and q:ray({x=p.x,y=p.y+.2,z=p.z},0,-3,0)
                        if floor and floor.ny>=.707 then p.y=floor.y+.004 end
                        e.heard={position=p,kind=kind};e.heard_age=0;e.think=0
                        e.search_time=0;e.search_origin=nil
                    end
                end
            end
        end
    end
end
function M.tick(ctx,e,query,dt)
    e.contact_age=e.contact_age+dt;e.heard_age=e.heard_age+dt
    e.sense_timer=e.sense_timer-dt
    if e.heard_age>=8 then e.heard=nil end
    if e.sense_timer>0 then return end
    e.sense_timer=e.sense_timer+.1
    local p=ctx.player.position
    local target={x=p.x,y=p.y+ctx.player.motion.height*.72,z=p.z}
    local delta=(math.atan2(-(p.x-e.position.x),-(p.z-e.position.z))-e.yaw+math.pi)%(2*math.pi)-math.pi
    local distance=nav.distance(suppression.eye(e),target)
    local aware=e.memory>0 or e.heard~=nil
    local sees=ctx.player.actor.alive and distance<M.view_range
        and (math.abs(delta)<(aware and math.rad(100) or math.rad(50)) or distance<4.5)
        and query:visible(suppression.eye(e),target)
    e.visible=sees
    e.notice=sees and math.min(1,e.notice+.1/(.16+distance*.0075+(aware and 0 or .28))) or math.max(0,e.notice-.035)
    if sees and e.notice>=1 then tactics.alert(ctx,e,p,target) end
end
function M.target(e)
    if e.memory>0 and e.target_point and (e.visible or e.contact_age<=M.suppress_time) then return e.target_point end
end
-- Investigation reaches the observation, then scans there for a bounded time.
function M.investigate(e,dt)
    local point=e.memory>0 and e.last_seen or e.heard and e.heard.position
    if not point then return end
    if nav.distance(e.position,point)>.65 then
        if e.state~="investigate" and e.state~="pursuit" then e.investigations=e.investigations+1 end
        e.state=e.memory>0 and "pursuit" or "investigate";return point
    end
    if not e.search_origin then e.search_origin=e.yaw;e.search_time=0;e.searches=e.searches+1 end
    e.state="search"
end
function M.search(e,dt)
    if e.state~="search" or not e.search_origin then return end
    e.search_time=e.search_time+dt
    e.yaw=e.search_origin+math.sin(e.search_time*1.6)*1.35
    if e.search_time>=3 then M.clear(e);e.think=0 end
end
return M
