-- Local low-obstacle links reuse the player's complete swept vault validation.
local capsule=require "game.player.capsule"
local mantle=require "game.player.mantle"
local V=require "game.weapons.math"
local nav=require "game.ai.navigation"
local animation=require "game.ai.animation"
local M={}
function M.shortcut(e,goal,q,options)
    local distance=nav.distance(e.position,goal)
    if not q.ray or distance<1 or distance>6 or math.abs(goal.y-e.position.y)>.3 then return end
    if options and options.checkpoint then options.checkpoint() end
    local dx,dz=goal.x-e.position.x,goal.z-e.position.z
    local length=math.sqrt(dx*dx+dz*dz);dx,dz=dx/length,dz/length
    local hit=q:ray({x=e.position.x,y=e.position.y+.6,z=e.position.z},dx*distance,0,dz*distance)
    if not hit or math.abs(hit.ny)>.2 then return end
    local approach={x=hit.x-dx*.6,y=e.position.y,z=hit.z-dz*.6}
    if (approach.x-e.position.x)*dx+(approach.z-e.position.z)*dz<-.1 then approach=V.copy(e.position) end
    local m=capsule.new(V.copy(approach));m.grounded=true;m.yaw=math.atan2(-dx,-dz)
    m.velocity={x=dx*3.2,y=0,z=dz*3.2}
    if not mantle.try_begin(m,{enabled=true,move_x=0,move_z=-1},q) or m.mantle.kind~="vault" then return end
    local target=m.mantle.target
    if nav.distance(target,goal)>=distance or not q:walkable(e.position,approach) or not q:walkable(target,goal) then return end
    approach.vault_goal=V.copy(goal)
    return {approach,V.copy(goal)}
end
function M.begin(e,waypoint,q)
    if not waypoint or not waypoint.vault_goal or e.motion.mantle or e.suppressed or e.reload_left>0 then return false end
    local p=e.position;local target=waypoint.vault_goal
    local desired=math.atan2(-(target.x-p.x),-(target.z-p.z))
    local delta=(desired-e.yaw+math.pi)%(2*math.pi)-math.pi
    if nav.distance(p,waypoint)>.18 or math.abs(delta)>.1 then return false end
    local m=e.motion
    -- The accepted link supplies intent; speed is used only for the probe and
    -- exit momentum, never to teleport or bypass a clearance check.
    local old=V.copy(m.velocity)
    m.velocity.x,m.velocity.z=-math.sin(e.yaw)*3.2,-math.cos(e.yaw)*3.2
    if not mantle.try_begin(m,{enabled=true,move_x=0,move_z=-1},q) then
        m.velocity=old;return false
    end
    animation.vault(e,m.mantle.duration)
    e.vaults=e.vaults+1
    return true
end
return M
