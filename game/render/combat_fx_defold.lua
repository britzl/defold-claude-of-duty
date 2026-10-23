local fx=require "game.render.combat_fx"
local geometry=require "game.weapons.geometry"
local V=require "game.weapons.math"
local events=require "game.events"
local M={}
local K=fx.kind
local function new_state(ctx)
    local state=fx.new(ctx.world.seed)
    fx.ambient_sources(state,ctx.world.layout)
    return state
end
local function visible(part,value)
    if part.visible~=value then msg.post(part.url,value and "enable" or "disable");part.visible=value end
end
-- This adapter exclusively owns the pooled objects. Retain the exact Lua
-- inputs last submitted, rather than comparing double inputs with float vmath
-- outputs. This also notices in-place fixture edits and recycled pool slots.
local function present(a,part,e,camera_rotation)
    local c=part.presented or {};part.presented=c
    local p=e.position
    if c.px~=p.x or c.py~=p.y or c.pz~=p.z then
        go.set_position(vmath.vector3(p.x,p.y,p.z),part.id)
        c.px,c.py,c.pz=p.x,p.y,p.z
    end
    local angle=e.seed*6.2831853+e.spin*(e.duration-e.life)
    local stretch=1
    if e.kind==K.spark then
        local v=e.velocity
        if c.spark_camera~=a.camera_revision or c.vx~=v.x or c.vy~=v.y or c.vz~=v.z then
            if a.inverse_revision~=a.camera_revision then
                a.camera_inverse=vmath.conj(camera_rotation);a.inverse_revision=a.camera_revision
            end
            local projected=vmath.rotate(a.camera_inverse,vmath.vector3(v.x,v.y,v.z))
            c.spark_angle=math.atan2(projected.y,projected.x)
            c.stretch=1+math.min(12,vmath.length(projected)*.8)
            c.spark_camera=a.camera_revision;c.vx,c.vy,c.vz=v.x,v.y,v.z
        end
        angle,stretch=c.spark_angle,c.stretch
    end
    if e.decal then
        local n=e.normal
        if not c.decal or c.angle~=angle or c.nx~=n.x or c.ny~=n.y or c.nz~=n.z then
            local r=V.forward_rotation(n)
            go.set_rotation(vmath.quat(r.x,r.y,r.z,r.w)*vmath.quat_rotation_z(angle),part.id)
            c.angle=angle;c.nx,c.ny,c.nz=n.x,n.y,n.z
        end
    elseif c.decal or c.angle~=angle or c.camera_revision~=a.camera_revision then
        go.set_rotation(camera_rotation*vmath.quat_rotation_z(angle),part.id)
        c.angle=angle;c.camera_revision=a.camera_revision
    end
    c.decal=e.decal
    local size,opacity=fx.appearance(e)
    local sx=size*stretch
    if c.sx~=sx or c.sy~=size then
        go.set_scale(vmath.vector3(sx,size,size),part.id);c.sx,c.sy=sx,size
    end
    local age=1-e.life/e.duration
    if c.kind~=e.kind or c.opacity~=opacity or c.seed~=e.seed or c.age~=age then
        go.set(part.url,"particle",vmath.vector4(e.kind,opacity,e.seed,age))
        c.kind,c.opacity,c.seed,c.age=e.kind,opacity,e.seed,age
    end
    if part.group~="haze" then
        local colour,variant=e.colour,e.variant or 0
        if c.r~=colour[1] or c.g~=colour[2] or c.b~=colour[3] or c.variant~=variant then
            go.set(part.url,"tint",vmath.vector4(colour[1],colour[2],colour[3],variant))
            c.r,c.g,c.b,c.variant=colour[1],colour[2],colour[3],variant
        end
    end
end
function M.new(ctx)
    local a={state=new_state(ctx),parts={},pending={},ctx=ctx}
    -- World-only rays never put a decal on a moving corpse or fragment.
    a.query={ray=function(_,p,dx,dy,dz)
        local hit=physics.raycast(vmath.vector3(p.x,p.y,p.z),vmath.vector3(p.x+dx,p.y+dy,p.z+dz),{hash("world")})
        if not hit then return end
        local shape=ctx.services.world.by_id[hit.id]
        return {x=hit.position.x,y=hit.position.y,z=hit.position.z,nx=hit.normal.x,ny=hit.normal.y,nz=hit.normal.z,
            surface=shape and shape.surface or "concrete"}
    end}
    local b=geometry.quad()
    local data=buffer.create(b.vertex_count,{
        {name=hash("position"),type=buffer.VALUE_TYPE_FLOAT32,count=3},
        {name=hash("normal"),type=buffer.VALUE_TYPE_FLOAT32,count=3}})
    for name,values in pairs({position=b.positions,normal=b.normals}) do
        local stream=buffer.get_stream(data,hash(name));for i,v in ipairs(values) do stream[i]=v end
    end
    buffer.set_metadata(data,"AABB",{-.5,-.5,-.01,.5,.5,.01},buffer.VALUE_TYPE_FLOAT32)
    a.resource=resource.create_buffer("/generated/combat_quad.bufferc",{buffer=data})
    for _,group in ipairs({{"particles",fx.particle_limit},{"ambient",fx.ambient_limit},{"decals",fx.decal_limit},{"haze",fx.haze_limit}}) do
    for i=1,group[2] do
        local id=factory.create(group[1]=="haze" and "#combat_haze" or "#combat_particle")
        local part={id=id,url=msg.url(nil,id,"mesh"),visible=true,group=group[1],index=i}
        go.set(part.url,"vertices",a.resource);visible(part,false);a.parts[#a.parts+1]=part
    end
    end
    events.on(ctx.events,events.BULLET_IMPACT,a,function(_,hit) fx.impact(a.state,hit,a.query) end)
    events.on(ctx.events,events.PLAYER_FOOTSTEP,a,function(_,step) fx.footstep(a.state,step,a.query,false) end)
    events.on(ctx.events,events.PLAYER_LAND,a,function(_,step) fx.footstep(a.state,step,a.query,true) end)
    events.on(ctx.events,events.ACTOR_DEATH,a,function(_,hit)
        local actor=ctx.ai.actors[hit.actor]
        if actor then fx.death(a.state,actor.position,a.query) end
    end)
    events.on(ctx.events,events.EXPLOSION,a,function(_,blast) fx.explosion(a.state,blast,a.query) end)
    events.on(ctx.events,events.WEAPON_FIRE,a,function(_,shot)
        if shot.position then fx.fire(a.state,shot.position,shot.direction,true)
        else
            -- Resolve player muzzle after viewmodel animation; the event's
            -- ballistic origin is the eye and must not spawn smoke in the face.
            a.pending[#a.pending+1]=shot.dir
            while #a.pending>2 do table.remove(a.pending,1) end
        end
    end)
    return a
end
function M.reset(a)
    a.state=new_state(a.ctx);a.pending={};a.fixture=nil
    if a.options then fx.configure(a.state,a.options) end
    for _,p in ipairs(a.parts) do visible(p,false) end
end
function M.fixture(a,enabled)
    a.fixture=nil
    if not enabled then return end
    local state=fx.new()
    -- Concrete pavement top, with particles partly intersecting it. Production
    -- spawn/update/shader paths are used; no fixture-only rendering branches.
    fx.impact(state,{point={x=.3,y=0,z=6.4},normal={x=0,y=1,z=0},surface="concrete"})
    fx.impact(state,{point={x=-.1,y=0,z=6.6},normal={x=0,y=1,z=0},surface="wood"})
    fx.fire(state,{x=.65,y=.5,z=6.1},{x=0,y=0,z=-1},true)
    fx.update(state,.015)
    state.particles[1].size=.85;state.particles[1].position.y=.07
    state.particles[1].life=.65
    state.decals[1].size=.35;state.decals[2].size=.24
    if enabled=="glass" then
        state=fx.new()
        -- Emitters on opposite sides of both panes; centred draw objects share
        -- the pane sort queue rather than rendering all smoke after all glass.
        fx.fire(state,{x=42.2,y=1.1,z=-.9},{x=0,y=0,z=1},false)
        fx.fire(state,{x=41.8,y=1.3,z=1.5},{x=0,y=0,z=1},false)
        fx.fire(state,{x=42.4,y=1.6,z=.3},{x=0,y=0,z=1},true)
        fx.update(state,.015)
        for _,e in ipairs(state.particles) do if e.life>0 and e.kind==0 then
            e.size=.8;e.life=e.duration*.65
        end end
    end
    a.fixture=state
end
function M.configure(a,options)
    a.options=options;fx.configure(a.state,options)
end
function M.update(a,dt,camera_rotation,muzzle,capture,enabled,camera_position,sun)
    if profiler then profiler.scope_begin("effects.simulate") end
    if not capture then
        local env
        if a.ctx.world.ready and enabled then
            local forward=vmath.rotate(camera_rotation,vmath.vector3(0,0,-1))
            env={position=camera_position,forward=forward,sun=sun}
        end
        fx.update(a.state,a.ctx.world.ready and dt or 0,a.query,env)
    end
    if profiler then profiler.scope_end();profiler.scope_begin("effects.pending_fire") end
    if not capture then
        for i,direction in ipairs(a.pending) do fx.fire(a.state,muzzle,direction,false);a.pending[i]=nil end
    end
    if profiler then profiler.scope_end();profiler.scope_begin("effects.present") end
    local state=a.fixture or a.state
    local show=enabled and (not capture or a.fixture~=nil)
    if a.camera_x~=camera_rotation.x or a.camera_y~=camera_rotation.y
        or a.camera_z~=camera_rotation.z or a.camera_w~=camera_rotation.w then
        a.camera_x,a.camera_y,a.camera_z,a.camera_w=camera_rotation.x,camera_rotation.y,camera_rotation.z,camera_rotation.w
        a.camera_revision=(a.camera_revision or 0)+1
    end
    local haze=0
    for i,part in ipairs(a.parts) do
        local e=state[part.group][part.index]
        visible(part,show and e.life>0)
        if part.visible then
            present(a,part,e,camera_rotation)
            if part.group=="haze" then haze=haze+1 end
        end
    end
    if profiler then profiler.scope_end();profiler.scope_begin("effects.haze_count") end
    if haze~=a.haze_count then
        a.haze_count=haze;msg.post("@render:","renderer_combat_state",{haze=haze})
    end
    if profiler then profiler.scope_end() end
end
function M.snapshot(a)
    local s=fx.snapshot(a.fixture or a.state);s.fixture=a.fixture~=nil
    s.meshes=#a.parts;s.buffers=1;s.mesh_bytes=6*6*4
    return s
end
function M.final(a,ctx)
    events.off_owner(ctx.events,a)
    for _,part in ipairs(a.parts) do go.delete(part.id) end
    resource.release(a.resource)
end
return M
