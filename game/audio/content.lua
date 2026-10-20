-- Audio observes simulation notifications; it never advances gameplay RNG or AI.
local events=require "game.events"
local rng=require "game.rng"
local spatial=require "game.audio.spatial"
local M={}
function M.reset(a,seed)
    a.scene_random=rng.new(seed,"audio/scene")
    a.actors=setmetatable({},{__mode="k"});a.rounds=setmetatable({},{__mode="k"})
    a.bark_until={};a.scene_clock=0;a.battle_due=8+a.scene_random()*6;a.volley=nil
    a.deafness=0;a.duck=0;a.ui_until=0
end
function M.init(ctx,queue,cancel,surface)
    local a=ctx.audio
    M.reset(a,ctx.world.seed)
    local function cue(kind,key,position,gain,priority,bus)
        queue(a,{kind=kind,key=key,position=position,gain=gain,priority=priority or 1,bus=bus or "foley"})
    end
    local function bark(kind,id,position,force)
        id=id or "anonymous"
        if not position or (not force and a.scene_clock<(a.bark_until[id] or 0)) then return end
        a.bark_until[id]=a.scene_clock+(force and 1 or 3)
        queue(a,{kind="bark",key="bark/"..kind,position=position,source=id,gain=.6,bus="foley",priority=2,near=6,range=55})
    end
    a.bark=bark
    local function on(event,fn) events.on(ctx.events,event,a,function(_,p) fn(p or {}) end) end
    on(events.GRENADE_THROW,function(p)
        cue("grenade","grenade/pin",p.position,.42,2)
        bark("grenade",p.source,p.position,true)
    end)
    on(events.EXPLOSION,function(p)
        queue(a,{kind="explosion",key="explosion",position=p.position,gain=1,bus="weapons",priority=3,near=12,range=160})
        local at=a.listener.position
        if p.position and at then
            local _,_,d=spatial.mix(a.listener,p.position,1,10000)
            local strength=math.max(0,1-d/18)
            if a.backend then local b=a.backend:occluded(at,p.position);if b==true or (type(b)=="number" and b>0) then strength=strength*.3 end end
            if strength>.05 then
                cancel(a,"tinnitus")
                a.deafness=math.max(a.deafness,strength)
                a.duck=math.max(a.duck,strength)
                queue(a,{kind="tinnitus",key="tinnitus",gain=.25*strength,bus="foley",priority=3,internal=true,tag="tinnitus"})
            end
        end
    end)
    on(events.WEAPON_FIRE,function(p)
        local first=not p.source or p.source=="player"
        local name=(p.weapon=="smg" or p.weapon=="pistol") and p.weapon or "rifle"
        queue(a,{kind="shot",weapon=name,position=not first and (p.origin or p.position) or nil,
            gain=first and .8 or .9,bus="weapons",priority=first and 3 or 2,near=8,range=100})
        if first then a.duck=math.max(a.duck,.45) end
    end)
    on(events.WEAPON_DRY,function() cue("dry","mechanic/dry",nil,.35,3) end)
    on(events.WEAPON_RELOAD,function(p)
        local tag=p.source and p.source~="player" and "reload/"..p.source or "reload"
        if p.phase=="cancel" then cancel(a,tag);return end
        if p.phase=="end" then return end
        if p.phase=="start" and p.source then bark("reload",p.source,p.position) end
        queue(a,{kind="reload",key="mechanic/"..(p.phase=="bolt" and "boltrelease" or p.phase),position=p.position,gain=.45,priority=2,bus="foley",tag=tag})
    end)
    on(events.PLAYER_FOOTSTEP,function(p)
        local name=surface(p.surface);a.round[name]=(a.round[name] or 0)%2+1
        cue("step","step/"..name.."/"..a.round[name],nil,p.running and .55 or .34)
    end)
    on(events.PLAYER_LAND,function(p)
        queue(a,{kind="land",key="step/"..surface(p.surface).."/1",gain=math.min(.8,.2+(p.velocity or 0)*.055),speed=.8,bus="foley",priority=2})
    end)
    on(events.BULLET_IMPACT,function(p)
        if not p.exit then queue(a,{kind="impact",key="impact/"..surface(p.audio or p.surface),position=p.point,gain=.42,bus="foley",priority=1,near=5,range=45}) end
    end)
    on(events.PHYSICS_CONTACT,function(p)
        local key=p.kind=="casing" and "shell" or p.kind=="grenade" and "grenade/bounce" or p.kind=="body" and "body" or "impact/"..surface(p.surface)
        queue(a,{kind=p.kind=="casing" and "shell" or p.kind=="body" and "body" or "bounce",key=key,position=p.position,
            gain=math.min(p.kind=="casing" and .22 or .65,(p.speed or 1)*.09),bus="foley",priority=1,near=4,range=22})
    end)
    on(events.BULLET_SEGMENT,function(p)
        if not p.source or p.source=="player" or not p.round or a.rounds[p.round] or not ctx.player.actor.alive then return end
        local at=a.listener.position;local point,d,t=spatial.closest(at,p.from,p.to)
        -- Only a travelled, passing segment can whizz; suppress repeat segments
        -- of the same projectile and rounds hidden behind solid geometry.
        if not point or d>=6 or t<0 or t>1 or spatial.blocked(a.backend,at,point) then return end
        a.rounds[p.round]=true
        local key=(p.speed or 500)>343 and d<2 and "crack" or "whizz"
        queue(a,{kind="near_miss",key=key,position=point,gain=.7*(1-d/6),bus="foley",priority=3,near=6,range=12})
    end)
    on(events.PLAYER_HEARTBEAT,function(p)
        if ctx.player.actor.alive then queue(a,{kind="heartbeat",key="heartbeat",gain=.16+.3*(p.strength or 0),bus="foley",priority=3,internal=true,tag="heartbeat"}) end
    end)
    on(events.DAMAGE_TAKEN,function() cue("hurt","hurt",nil,.6,3) end)
    on(events.DAMAGE_DEALT,function(p)
        if p.source=="player" and p.target~="player" then
            queue(a,{kind="hit",key=p.killed and "ui/kill" or p.headshot and "ui/headshot" or "ui/hit",gain=.38,bus="foley",priority=3,internal=true})
        end
        local e=ctx.ai.actors[p.target]
        if e and not p.killed then bark("hurt",e.id,e.position) end
    end)
    on(events.ACTOR_DEATH,function(p)
        if p.actor=="player" then cancel(a);cancel(a,"heartbeat");return end
        local e=ctx.ai.actors[p.actor]
        if e then bark("death",e.id,e.position,true) end
        -- Body impact is driven by the ragdoll's first hard contact.
    end)
    on(events.PLAYER_STATE,function(p)
        if p.stance~=a.stance or p.sliding~=a.sliding or p.mantling~=a.mantling then
            if a.stance then cue("cloth","cloth",nil,.2) end
            a.stance,a.sliding,a.mantling=p.stance,p.sliding,p.mantling
        end
    end)
end
function M.fixed_update(ctx,dt,queue,surface)
    local a=ctx.audio
    if not a.ready or not ctx.world.ready or not ctx.player.enabled then return end
    a.scene_clock=a.scene_clock+dt
    a.duck=math.max(0,a.duck-dt*2.6)
    a.deafness=math.max(0,a.deafness-dt*(.1+a.deafness*.22))
    if ctx.ai.enabled then
        for _,id in ipairs(ctx.ai.order) do
            local e=ctx.ai.actors[id]
            local old=a.actors[e]
            if not old then old={travel=e.travel,steps=0};a.actors[e]=old end
            if e.actor.alive then
                if e.visible and not old.visible then a.bark("contact",id,e.position)
                elseif e.role~=old.role and e.role=="flank" then a.bark("flank",id,e.position)
                elseif e.suppressed and not old.suppressed then a.bark("suppress",id,e.position)
                elseif e.state~=old.state and e.role=="engage" then a.bark("advance",id,e.position) end
                if e.motion.grounded and not e.motion.mantle then
                    old.steps=old.steps+math.max(0,e.travel-old.travel)
                    local stride=e.motion.stance=="crouch" and .85 or 1.4
                    if old.steps>=stride then
                        old.steps=old.steps%stride;old.foot=(old.foot or 0)%2+1
                        queue(a,{kind="soldier_step",key="step/"..surface(e.motion.surface).."/"..old.foot,position=e.position,
                            gain=e.motion.stance=="crouch" and .2 or .45,bus="foley",priority=1,near=4,range=28})
                    end
                else old.steps=0 end
            end
            old.travel,old.visible,old.role,old.state,old.suppressed=e.travel,e.visible,e.role,e.state,e.suppressed
        end
    end
    -- Ambient war stays outside the play space and never emits weapon/explosion
    -- gameplay events. Schedule against simulation time so pause cannot backlog it.
    if a.scene_clock>=a.battle_due then
        local random=a.scene_random;local angle=random()*math.pi*2;local d=90+random()*60
        local p=ctx.player.position
        a.volley={left=2+math.floor(random()*4),at=a.scene_clock,
            position={x=p.x+math.sin(angle)*d,y=3,z=p.z+math.cos(angle)*d},boom=random()<.28}
        a.battle_due=a.scene_clock+9+random()*11
    end
    local volley=a.volley
    if volley and a.scene_clock>=volley.at then
        queue(a,{kind="battle",key=volley.boom and "explosion" or "shot/rifle/1/dry",position=volley.position,
            gain=volley.boom and .35 or .23,bus="ambience",priority=1,near=45,range=240,distant=true})
        volley.left=volley.boom and 0 or volley.left-1;volley.at=a.scene_clock+.11+a.scene_random()*.09
        if volley.left==0 then a.volley=nil end
    end
end
return M
