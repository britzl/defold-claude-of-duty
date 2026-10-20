-- Fixed-tick fuse and blast owner. Bullet owns motion; notifications never
-- apply health damage. Dedicated body slots cannot be recycled by bullet FX.
local events=require "game.events"
local combat=require "game.combat"
local V=require "game.weapons.math"
local M={limit=6,fuse=2.35,radius=6.5,damage=120,body_radius=.05,mass=.42}
function M.init(ctx)
    ctx.grenades={live={},serial=0,launched=0,detonated=0,rejected=0,damage_requests=0}
end
function M.launch(ctx,source,position,velocity)
    local s,a=ctx.grenades,ctx.services.dynamics
    if ctx.paused or ctx.capture_active or not ctx.world.ready or not a or not a.api.grenade
        or #s.live>=M.limit then s.rejected=s.rejected+1;return end
    local body=a.api.grenade(a,position,velocity)
    if not body then s.rejected=s.rejected+1;return end
    s.serial=s.serial+1;s.launched=s.launched+1
    local g={id=s.serial,source=source,position=V.copy(position),fuse=M.fuse,body=body,
        damage_scale=ctx.ai.damage_scale,age=0}
    s.live[#s.live+1]=g
    events.emit(ctx.events,events.GRENADE_THROW,{id=g.id,source=source,position=V.copy(position),velocity=V.copy(velocity),fuse=g.fuse})
    return g
end
local function clear(ctx,from,to)
    local q=ctx.services.capsule
    -- Reverse the ray: a resting body may be on a surface. The actor's eye is
    -- in free space and walls/floors must block the blast, including upstairs.
    return q and not q:ray(to,from.x-to.x,from.y-to.y,from.z-to.z)
end
function M.detonate(ctx,g)
    if g.detonated then return end
    g.detonated=true
    local s=ctx.grenades;s.detonated=s.detonated+1
    local origin=V.copy(g.position)
    local function hit(id,actor,feet,eye,player)
        if not actor.alive then return end
        local point=player and eye or feet
        local d=V.length({x=point.x-origin.x,y=point.y-origin.y,z=point.z-origin.z})
        local falloff=math.max(0,1-d/M.radius)^(player and 1.6 or 2)
        if falloff<= (player and .02 or 0) or not clear(ctx,origin,eye) then return end
        local direction=V.normalize({x=eye.x-origin.x,y=eye.y-origin.y+.35,z=eye.z-origin.z})
        if combat.request(ctx.combat,{target=id,source=g.source,amount=M.damage*falloff*g.damage_scale,
            kind="explosion",round=g,from=origin,point=eye,region="torso",
            impulse=V.point({x=0,y=0,z=0},direction,45*falloff)}) then
            s.damage_requests=s.damage_requests+1
        end
    end
    local p,m=ctx.player.position,ctx.player.motion
    hit("player",ctx.player.actor,p,{x=p.x,y=p.y+m.eye,z=p.z},true)
    -- One entry per actor, independent of how many animated hitboxes it has.
    for _,id in ipairs(ctx.ai.order) do
        local e=ctx.ai.actors[id]
        hit(id,e.actor,e.position,{x=e.position.x,y=e.position.y+e.motion.height*.86,z=e.position.z},false)
    end
    events.emit(ctx.events,events.EXPLOSION,{id=g.id,token=g,source=g.source,position=origin,
        radius=M.radius,damage=M.damage,impulse=8})
end
function M.fixed_update(ctx,dt)
    if not ctx.world.ready or ctx.capture_active then return end
    local a=ctx.services.dynamics
    for i=#ctx.grenades.live,1,-1 do
        local g=ctx.grenades.live[i]
        -- Pending bodies wait for Defold's creation boundary before ignition.
        if g.body.active then
            g.position=V.copy(g.body.position);g.fuse=math.max(0,g.fuse-dt);g.age=g.age+dt
            if g.fuse<=1e-8 then
                a.api.remove_grenade(a,g.body)
                table.remove(ctx.grenades.live,i)
                M.detonate(ctx,g)
            else
                events.emit(ctx.events,events.GRENADE_FUSE,{id=g.id,source=g.source,position=V.copy(g.position),fuse=g.fuse})
            end
        end
    end
end
function M.reset(ctx)
    local a=ctx.services.dynamics
    if a then for _,g in ipairs(ctx.grenades.live) do a.api.remove_grenade(a,g.body) end end
    -- Cancel queued blast damage as well as bodies on encounter replacement.
    for i=#ctx.combat.pending,1,-1 do
        if ctx.combat.pending[i].kind=="explosion" then table.remove(ctx.combat.pending,i) end
    end
    ctx.grenades.live={}
end
function M.snapshot(ctx)
    local s=ctx.grenades
    local out={live={},limit=M.limit,launched=s.launched,detonated=s.detonated,rejected=s.rejected,damage_requests=s.damage_requests}
    for _,g in ipairs(s.live) do out.live[#out.live+1]={id=g.id,source=g.source,position=V.copy(g.position),fuse=g.fuse,active=g.body.active or false} end
    return out
end
M.final=M.reset
return M
