-- Bounded, engine-independent combat presentation. Never owns combat state.
local map_style=require("game.ui.style").map
local events=require "game.events"
local defs=require "game.weapons.defs"
local weapons=require "game.systems.weapons"
local M={contacts=16,grenades=4,numbers=16,arcs=6,objectives=6}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function copy(p) return {x=p.x,y=p.y,z=p.z} end
local function push(list,item,limit)
    if #list==limit then table.remove(list,1) end
    list[#list+1]=item
end
local function point(p)
    assert(type(p)=="table","position required")
    for _,k in ipairs({"x","y","z"}) do assert(type(p[k])=="number" and math.abs(p[k])<1e6,"finite position required") end
    return copy(p)
end
local function label(s,n) return tostring(s or ""):gsub("[%c]"," "):sub(1,n) end

function M.reset(ctx)
    ctx.hud.feedback={numbers={},arcs={},objectives={},prompt=false,banner=false,hit=false,serial=0,clock=0}
end
function M.init(ctx)
    M.reset(ctx)
    events.on(ctx.events,events.DAMAGE_DEALT,ctx.hud,function(_,hit)
        if hit.source~="player" or hit.target=="player" then return end
        local s=ctx.hud.feedback
        local kind=hit.killed and "kill" or hit.headshot and "head" or "hit"
        local life=hit.killed and .42 or hit.headshot and .32 or .26
        s.hit={kind=kind,age=0,life=life}
        if hit.point then
            s.serial=s.serial+1
            push(s.numbers,{position=copy(hit.point),amount=math.floor(hit.amount+.5),kind=kind,
                age=0,life=hit.killed and 1.25 or .95,drift=(s.serial%5-2)*7},M.numbers)
        end
        if hit.killed then s.banner={title="ENEMY ELIMINATED",sub=hit.headshot and "HEADSHOT" or "CONFIRMED",age=0,life=2.1} end
    end)
    events.on(ctx.events,events.DAMAGE_TAKEN,ctx.hud,function(_,hit)
        local e=ctx.ai.actors[hit.source]
        local p=hit.from or e and e.position
        if not p then return end
        local at=ctx.presentation.position
        local dx,dz=p.x-at.x,p.z-at.z
        if dx*dx+dz*dz<1e-8 then return end
        push(ctx.hud.feedback.arcs,{dx=dx,dz=dz,age=0,life=2,intensity=clamp((hit.amount or 10)/35,.25,1)},M.arcs)
    end)
end
function M.update(ctx,dt)
    local s=ctx.hud.feedback
    s.clock=s.clock+dt
    for _,list in ipairs({s.numbers,s.arcs}) do
        for i=#list,1,-1 do
            list[i].age=list[i].age+dt
            if list[i].age>=list[i].life then table.remove(list,i) end
        end
    end
    for _,key in ipairs({"hit","banner"}) do
        local v=s[key]
        if v then v.age=v.age+dt;if v.age>=v.life then s[key]=false end end
    end
end

-- Optional display capabilities; callers retain ownership of interactions/objectives.
function M.set_prompt(ctx,p)
    if not p then ctx.hud.feedback.prompt=false;return end
    assert(type(p)=="table","prompt must be a table")
    local progress=p.progress
    assert(progress==nil or type(progress)=="number" and progress==progress and math.abs(progress)<math.huge,"finite progress required")
    ctx.hud.feedback.prompt={key=label(p.key or "F",8),text=label(p.text or "INTERACT",32),
        sub=label(p.sub,48),progress=progress and clamp(progress,0,1) or -1}
end
function M.set_objectives(ctx,list)
    assert(type(list)=="table" and #list<=M.objectives,"at most six objectives")
    local result={}
    for i,o in ipairs(list) do result[i]={position=point(o.position),label=label(o.label,3),name=label(o.name,24)} end
    ctx.hud.feedback.objectives=result
end

-- Inverse of camera Y * X * Z rotation, followed by perspective projection.
-- Coordinates use the visible GUI rectangle, including non-reference aspects.
function M.project(p,c,width,height,margin)
    local dx,dy,dz=p.x-c.camera.x,p.y-c.camera.y,p.z-c.camera.z
    local cy,sy=math.cos(c.yaw),math.sin(c.yaw)
    local x,z=cy*dx-sy*dz,sy*dx+cy*dz
    local cp,sp=math.cos(c.pitch or 0),math.sin(c.pitch or 0)
    local y=cp*dy+sp*z
    z=-sp*dy+cp*z
    local cr,sr=math.cos(c.roll or 0),math.sin(c.roll or 0)
    x,y=cr*x+sr*y,-sr*x+cr*y
    local behind=z>=-.01
    local f=height/(2*math.tan((c.fov or math.rad(70))/2))
    local px,py=x*f/math.max(.01,math.abs(z)),y*f/math.max(.01,math.abs(z))
    local mx=math.max(1,width/2-(type(margin)=="table" and margin.x or margin))
    local my=math.max(1,height/2-(type(margin)=="table" and margin.y or margin))
    local off=behind or math.abs(px)>mx or math.abs(py)>my
    if off then
        if math.abs(px)+math.abs(py)<.001 then py=-my end
        local scale=math.min(mx/math.max(.001,math.abs(px)),my/math.max(.001,math.abs(py)))
        px,py=px*scale,py*scale
    end
    return {x=px,y=py,offscreen=off,behind=behind,angle=-math.deg(math.atan2(px,py)),
        distance=math.sqrt(dx*dx+dy*dy+dz*dz)}
end
function M.map_point(p,at,size,range,edge)
    local x,y=(p.x-at.x)*size/(2*range),(at.z-p.z)*size/(2*range)
    local limit=size/2-7
    if not edge and (math.abs(x)>limit or math.abs(y)>limit) then return nil end
    return {x=clamp(x,-limit,limit),y=clamp(y,-limit,limit),floor=p.y-at.y>2 and 1 or p.y-at.y< -2 and -1 or 0}
end
function M.snapshot(ctx)
    local s=ctx.hud.feedback
    local w=weapons.snapshot(ctx)
    local d=defs[w.weapon]
    local reload=w.clip=="reloadTac" or w.clip=="reloadEmpty"
    local mag_out=reload and w.progress>=(w.clip=="reloadTac" and .20 or .16)
        and w.progress<(w.clip=="reloadTac" and .81 or .71)
    local b=s.banner
    local h=s.hit
    local alpha=b and math.min(1,b.age/.16,math.max(0,(b.life-b.age)/.46)) or 0
    return {numbers=#s.numbers,arcs=#s.arcs,objectives=#s.objectives,clock=s.clock,
        banner=b and b.title or "",banner_sub=b and b.sub or "",banner_alpha=alpha,
        prompt=s.prompt or {},hit_kind=h and h.kind or "",hit_alpha=h and clamp((1-h.age/h.life)/.45,0,1) or 0,
        ammo=w.ammo,mag=mag_out and 0 or w.mag,capacity=d.magSize,chambered=w.chambered,reserve=w.reserve,
        reload=reload,progress=reload and clamp(w.progress,0,1) or 0,
        ammo_low=w.ammo>0 and w.ammo<=d.magSize*.34,ammo_empty=w.ammo==0}
end
function M.items(ctx,width,height)
    local s,out=ctx.hud.feedback,ctx.presentation
    local result={contacts={},grenades={},numbers={},arcs={},objectives={}}
    for _,id in ipairs(ctx.ai.order) do
        local e=ctx.ai.actors[id]
        if e.actor.alive and #result.contacts<M.contacts then
            local p=M.map_point(e.position,out.position,map_style.size,22,false)
            if p then p.id=id;result.contacts[#result.contacts+1]=p end
        end
    end
    local danger={}
    for _,g in ipairs(ctx.grenades.live) do
        local p=g.position
        local dx,dy,dz=p.x-out.position.x,p.y-out.position.y,p.z-out.position.z
        if dx*dx+dy*dy+dz*dz<100 and g.fuse>0 then danger[#danger+1]=g end
    end
    table.sort(danger,function(a,b) return a.fuse==b.fuse and (a.id or 0)<(b.id or 0) or a.fuse<b.fuse end)
    for i=1,math.min(M.grenades,#danger) do
        local g=danger[i];local p=M.project(g.position,out,width,height,{x=78,y=150})
        -- Keep edge warnings out of the map/compass band and separate nearby fuses.
        local bottom,top=-height/2+150,height/2-(p.x< -width/2+230 and 250 or 150)
        p.y=clamp(p.y,bottom,top)
        for _,offset in ipairs({0,-60,60,-120,120,-180,180,-240,240}) do
            local y=p.y+offset
            local clear=y>=bottom and y<=top
            for _,old in ipairs(result.grenades) do
                if math.abs(p.x-old.x)<110 and math.abs(y-old.y)<59 then clear=false end
            end
            if clear then p.y=y;break end
        end
        p.fuse=g.fuse;p.fill=clamp(g.fuse/2.35,0,1)
        p.floor=g.position.y-out.position.y>2 and " ABOVE" or g.position.y-out.position.y< -2 and " BELOW" or ""
        p.alpha=.7+.3*math.sin(s.clock*(g.fuse<1 and 28 or 14))^2
        result.grenades[i]=p
    end
    for i,v in ipairs(s.numbers) do
        local p=M.project(v.position,out,width,height,30)
        local u=v.age/v.life
        p.x=p.x+v.drift*(1-(1-u)^2);p.y=p.y+42*(1-(1-u)^3)
        p.alpha=p.offscreen and 0 or clamp((1-u)/.45,0,1)
        p.amount=v.amount;p.kind=v.kind
        result.numbers[i]=p
    end
    for i,v in ipairs(s.arcs) do
        local c,sn=math.cos(out.yaw),math.sin(out.yaw)
        local angle=math.atan2(v.dx*c-v.dz*sn,-v.dx*sn-v.dz*c)
        result.arcs[i]={angle=angle,alpha=(.35+.65*v.intensity)*clamp((v.life-v.age)/1.64,0,1)}
    end
    for i,v in ipairs(s.objectives) do
        local p=M.project(v.position,out,width,height,100)
        p.label=v.label;p.name=v.name
        local map=M.map_point(v.position,out.position,map_style.size,22,true)
        p.map_x,p.map_y,p.floor=map.x,map.y,map.floor
        result.objectives[i]=p
    end
    return result
end
return M
