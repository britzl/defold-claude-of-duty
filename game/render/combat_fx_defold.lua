local fx=require "game.render.combat_fx"
local geometry=require "game.weapons.geometry"
local V=require "game.weapons.math"
local events=require "game.events"
local M={}
local function visible(part,value)
    if part.visible~=value then msg.post(part.url,value and "enable" or "disable");part.visible=value end
end
function M.new(ctx)
    local a={state=fx.new(),parts={},pending={}}
    local b=geometry.quad()
    local data=buffer.create(b.vertex_count,{
        {name=hash("position"),type=buffer.VALUE_TYPE_FLOAT32,count=3},
        {name=hash("normal"),type=buffer.VALUE_TYPE_FLOAT32,count=3}})
    for name,values in pairs({position=b.positions,normal=b.normals}) do
        local stream=buffer.get_stream(data,hash(name));for i,v in ipairs(values) do stream[i]=v end
    end
    buffer.set_metadata(data,"AABB",{-.5,-.5,-.01,.5,.5,.01},buffer.VALUE_TYPE_FLOAT32)
    a.resource=resource.create_buffer("/generated/combat_quad.bufferc",{buffer=data})
    for i=1,fx.particle_limit+fx.decal_limit do
        local id=factory.create("#combat_particle")
        local part={id=id,url=msg.url(nil,id,"mesh"),visible=true}
        go.set(part.url,"vertices",a.resource);visible(part,false);a.parts[i]=part
    end
    events.on(ctx.events,events.BULLET_IMPACT,a,function(_,hit) fx.impact(a.state,hit) end)
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
    a.state=fx.new();a.pending={};a.fixture=nil
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
function M.update(a,dt,camera_rotation,muzzle,capture,enabled)
    if not capture then
        fx.update(a.state,dt)
        for _,direction in ipairs(a.pending) do fx.fire(a.state,muzzle,direction,false) end
        a.pending={}
    end
    local state=a.fixture or a.state
    local show=enabled and (not capture or a.fixture~=nil)
    for i,part in ipairs(a.parts) do
        local e=i<=fx.particle_limit and state.particles[i] or state.decals[i-fx.particle_limit]
        visible(part,show and e.life>0)
        if part.visible then
            local size,opacity=fx.appearance(e)
            go.set_position(vmath.vector3(e.position.x,e.position.y,e.position.z),part.id)
            local q=camera_rotation
            if e.kind==2 then
                local r=V.forward_rotation(e.normal);q=vmath.quat(r.x,r.y,r.z,r.w)
            end
            go.set_rotation(q*vmath.quat_rotation_z(e.seed*6.2831853),part.id)
            go.set_scale(vmath.vector3(size,size,size),part.id)
            go.set(part.url,"particle",vmath.vector4(e.kind,opacity,e.seed,0))
            go.set(part.url,"tint",vmath.vector4(e.colour[1],e.colour[2],e.colour[3],1))
        end
    end
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
