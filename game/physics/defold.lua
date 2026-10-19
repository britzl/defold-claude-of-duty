-- Bounded native Bullet bodies. Defold steps the world once at 120 Hz; this
-- service only creates/configures bodies and samples completed physics steps.
local events=require "game.events"
local R=require "game.physics.rig"
local rig=require "game.ai.rig"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local geometry=require "game.weapons.geometry"
local M={debris_limit=32,ragdoll_limit=6}
local C,B=bullet3d.collision_object,bullet3d.rigid_body
local ZERO=vmath.vector3()
local function vector(p) return vmath.vector3(p.x,p.y,p.z) end
local function matrix(t)
    local m=vmath.matrix4()
    m.m00,m.m01,m.m02,m.m03=t[1],t[2],t[3],t[4]
    m.m10,m.m11,m.m12,m.m13=t[5],t[6],t[7],t[8]
    m.m20,m.m21,m.m22,m.m23=t[9],t[10],t[11],t[12]
    return m
end
local function transform(p,q)
    local m=vmath.matrix4_quat(q)
    return {m.m00,m.m01,m.m02,p.x,m.m10,m.m11,m.m12,p.y,m.m20,m.m21,m.m22,p.z}
end
local function visible(item,enabled)
    if item.visible==enabled then return end
    msg.post(item.mesh,enabled and "enable" or "disable")
    msg.post(item.prepass,enabled and "enable" or "disable");item.visible=enabled
end
local function body(a,world)
    local id=factory.create("#physics_body",vector(T.origin(world)),vmath.quat_matrix4(matrix(world)))
    local item={id=id,url=msg.url(nil,id,"collision"),born=a.ctx.time.frame}
    msg.post(item.url,"disable")
    return item
end
local function configure(a,item,spec,velocity,spin)
    item.object=assert(bullet3d.get_collision_object(item.url))
    item.body=assert(bullet3d.get_rigid_body(item.url))
    physics.set_shape(item.url,"box",{type=physics.SHAPE_TYPE_BOX,dimensions=vector(spec.dimensions)})
    B.set_mass(item.body,spec.mass)
    B.clear_forces(item.body)
    B.set_damping(item.body,.18,item.corpse and .7 or .45)
    B.set_sleeping_thresholds(item.body,.16,.35)
    C.set_friction(item.object,.8);C.set_restitution(item.object,item.corpse and .02 or .18)
    local d=spec.dimensions;local radius=math.min(d.x,d.y,d.z)*.4
    C.set_ccd_motion_threshold(item.object,radius)
    C.set_ccd_swept_sphere_radius(item.object,radius)
    local p,q=vector(T.origin(spec.world)),vmath.quat_matrix4(matrix(spec.world))
    C.set_world_transform(item.object,p,q)
    B.set_linear_velocity(item.body,vector(velocity or {x=0,y=0,z=0}))
    B.set_angular_velocity(item.body,vector(spin or {x=0,y=0,z=0}))
    C.force_activation_state(item.object,C.ACTIVE_TAG)
    C.set_deactivation_time(item.object,0)
    msg.post(item.url,"enable")
    item.position,item.rotation,item.previous,item.previous_rotation=p,q,p,q
    item.spec=spec;item.active=true;item.sleeping=false;item.quiet=0
    -- A recycled slot is a new solid to rounds already tracking a penetration.
    local key="body/"..hash_to_hex(item.id).."/"..(item.serial or 0)
    item.shape={id=key,surface=item.corpse and "flesh" or (spec.surface or "metal"),part=spec.name,
        w=d.x,h=d.y,d=d.z,x=p.x,y=p.y,z=p.z,transform=spec.world}
    a.by_id[item.id]=item.shape;a.by_key[key]=item
end
local function sample(item)
    item.previous,item.previous_rotation=item.position,item.rotation
    item.position,item.rotation=C.get_world_transform(item.object)
    item.shape.x,item.shape.y,item.shape.z=item.position.x,item.position.y,item.position.z
    item.shape.transform=transform(item.position,item.rotation)
end
local function settled(item,dt,distance,angle)
    local p,q=item.rotation,item.previous_rotation
    local dot=math.abs(p.x*q.x+p.y*q.y+p.z*q.z+p.w*q.w)
    return vmath.length(item.position-item.previous)<=distance*dt and dot>=math.cos(angle*dt*.5)
end
local function sleep(item)
    B.set_linear_velocity(item.body,ZERO);B.set_angular_velocity(item.body,ZERO)
    C.force_activation_state(item.object,C.DISABLE_SIMULATION)
    item.previous,item.previous_rotation=item.position,item.rotation
end
local function deactivate(a,item)
    if item.object then
        C.force_activation_state(item.object,C.DISABLE_SIMULATION)
        B.set_linear_velocity(item.body,ZERO);B.set_angular_velocity(item.body,ZERO)
    end
    msg.post(item.url,"disable")
    if item.shape then
        a.by_key[item.shape.id]=nil
        -- Defold applies disable/delete at the frame boundary. Keep an ignored
        -- registry entry until then so a same-tick ray cannot see a false wall.
        a.by_id[item.id]={disabled=true};item.shape=nil
    end
    item.active=false;item.pending=nil;item.saved_state=nil
    if item.mesh then visible(item,false) end
end
local function impulse(item,push,point)
    if not item.active then return end
    item.sleeping=false;item.quiet=0
    if item.doll then
        item.doll.sleeping=false;item.doll.quiet=0
        for _,b in ipairs(item.doll.bodies) do
            C.force_activation_state(b.object,C.ACTIVE_TAG);C.set_deactivation_time(b.object,0)
        end
    end
    C.force_activation_state(item.object,C.ACTIVE_TAG);C.set_deactivation_time(item.object,0)
    local offset=point and vector(point)-item.position or ZERO
    B.apply_impulse(item.body,vector(push),offset)
end
local function player_origin(ctx,offset)
    local p=ctx.player.position
    local motion=ctx.player.motion
    local local_offset=V.rotate(offset,0,motion.yaw,0)
    return {x=p.x+local_offset.x,y=p.y+motion.height*.93+local_offset.y,z=p.z+local_offset.z}
end
function M.new(ctx)
    local a={api=M,ctx=ctx,debris={},ragdolls={},by_id={},by_key={},retired={},serial=0,spawned=0,recycled=0,impulses=0,
        peak_bodies=0,work_seconds=0,ticks=0,peak_tick=0,paused=false}
    local cube=geometry.batch();geometry.box(cube,0,0,0,1,1,1,{1,1,1,0})
    local data=buffer.create(cube.vertex_count,{{name=hash("position"),type=buffer.VALUE_TYPE_FLOAT32,count=3},
        {name=hash("normal"),type=buffer.VALUE_TYPE_FLOAT32,count=3},{name=hash("color"),type=buffer.VALUE_TYPE_FLOAT32,count=4}})
    for name,values in pairs({position=cube.positions,normal=cube.normals,color=cube.colors}) do
        local stream=buffer.get_stream(data,hash(name));for i,v in ipairs(values) do stream[i]=v end
    end
    buffer.set_metadata(data,"AABB",cube.bounds,buffer.VALUE_TYPE_FLOAT32)
    a.resource=resource.create_buffer("/generated/debris.bufferc",{buffer=data})
    for i=1,M.debris_limit do
        local item=body(a,T.identity(0,-1000,0));item.visual=factory.create("#weapon_effect")
        item.mesh=msg.url(nil,item.visual,"mesh");item.prepass=msg.url(nil,item.visual,"prepass")
        go.set(item.mesh,"vertices",a.resource);go.set(item.prepass,"vertices",a.resource)
        visible(item,false);a.debris[i]=item
    end
    events.on(ctx.events,events.WEAPON_SHELL,a,function(_,shell)
        M.spawn(a,"casing",player_origin(ctx,{x=.22,y=-.18,z=-.32}),shell.velocity,shell.weapon)
    end)
    events.on(ctx.events,events.WEAPON_FIRE,a,function(_,shot)
        if shot.position then
            local d=shot.direction or {x=0,y=0,z=-1}
            M.spawn(a,"casing",shot.position,{x=-d.z*2,y=1,z=d.x*2})
        end
    end)
    events.on(ctx.events,events.WEAPON_RELOAD,a,function(_,beat)
        if beat.phase=="magdrop" then
            M.spawn(a,"magazine",beat.position or player_origin(ctx,{x=-.16,y=-.38,z=-.38}),
                V.rotate({x=-.35,y=-.2,z=-.2},0,ctx.player.motion.yaw,0),beat.weapon)
        end
    end)
    events.on(ctx.events,events.BULLET_IMPACT,a,function(_,hit)
        if hit.exit then return end
        local item=a.by_key[hit.collider]
        if item then
            local push=V.point({x=0,y=0,z=0},hit.incident,math.min(10,(hit.damage or 0)*.12))
            impulse(item,push,hit.point);a.impulses=a.impulses+1
        elseif hit.surface~="flesh" and hit.surface~="water" and hit.surface~="foliage" and hit.surface~="fabric" then
            M.spawn(a,"debris",V.point(hit.point,hit.normal,.045),V.point({x=0,y=1,z=0},hit.normal,1.2),hit.surface)
        end
    end)
    events.on(ctx.events,events.EXPLOSION,a,function(_,blast) M.blast(a,blast) end)
    events.on(ctx.events,events.ACTOR_DEATH,a,function(_,hit)
        local e=ctx.ai.actors[hit.actor]
        if e and not e.ragdoll then M.kill(a,e,hit) end
    end)
    return a
end
function M.spawn(a,kind,position,velocity,material)
    if a.paused then return end
    local item=a.debris[1]
    for _,candidate in ipairs(a.debris) do
        if not candidate.active and not candidate.pending then item=candidate;break end
        if (candidate.serial or 0)<(item.serial or 0) then item=candidate end
    end
    if item.active or item.pending then a.recycled=a.recycled+1;deactivate(a,item) end
    a.serial=a.serial+1;a.spawned=a.spawned+1;item.serial=a.serial;item.age=0;item.kind=kind
    local dimensions,mass,life,colour,surface
    if kind=="casing" then dimensions={x=.012,y=.012,z=.035};mass=.008;life=10;colour={.58,.42,.16,-1};surface="metal"
    elseif kind=="magazine" then
        dimensions={x=.035,y=material=="pistol" and .10 or .18,z=.065};mass=.22;life=18;colour={.16,.18,.17,0};surface="metal"
    else dimensions={x=.045,y=.035,z=.055};mass=.06;life=8;colour=material=="wood" and {.42,.27,.12,0} or {.48,.44,.37,0};surface=material end
    item.life=life;item.colour=colour;item.previous_world=nil
    item.pending={world=T.root(position,a.serial*2.399),dimensions=dimensions,mass=mass,surface=surface,
        velocity=velocity,spin={x=4,y=(a.serial%7)-3,z=7}}
    return item
end
function M.kill(a,e,hit)
    if #a.ragdolls>=M.ragdoll_limit then M.remove_ragdoll(a,a.ragdolls[1]) end
    local worlds=e.joints
    if not worlds then local palette;palette,worlds=rig.pose(require("game.systems.ai").pose_state(e)) end
    local spec=R.build(worlds,e.position,e.yaw,e.variant)
    local doll={spec=spec,bodies={},constraints={},actor=e,age=0,hit=hit,born=a.ctx.time.frame,transforms={}}
    for i,s in ipairs(spec.bodies) do
        local item=body(a,s.world);item.corpse=true;item.doll=doll;doll.bodies[i]=item;doll.transforms[i]=s.world
    end
    doll.palette=R.palette(spec,doll.transforms)
    e.ragdoll=doll;a.ragdolls[#a.ragdolls+1]=doll
end
local function start_ragdoll(a,doll)
    local velocity=doll.actor.motion.velocity
    for i,item in ipairs(doll.bodies) do configure(a,item,doll.spec.bodies[i],velocity) end
    for i,spec in ipairs(doll.spec.bodies) do if spec.parent then
        local f,g=spec.frame_a,spec.frame_b
        local joint=bullet3d.constraint.create_cone_twist(doll.bodies[spec.parent].body,doll.bodies[i].body,{
            frame_a_position=vector(T.origin(f)),frame_a_rotation=vmath.quat_matrix4(matrix(f)),
            frame_b_position=vector(T.origin(g)),frame_b_rotation=vmath.quat_matrix4(matrix(g)),collide_connected=false})
        bullet3d.constraint.set_cone_twist_limits(joint,spec.swing,spec.swing,spec.twist,.9,.3,1)
        doll.constraints[#doll.constraints+1]=joint
    end end
    local hit=doll.hit
    if hit.impulse then
        local index=R.hit_body(doll.spec,hit.part,hit.region,hit.point)
        impulse(doll.bodies[index],hit.impulse,hit.point)
    end
    doll.ready=true
end
function M.remove_ragdoll(a,doll)
    for _,joint in ipairs(doll.constraints) do if bullet3d.constraint.is_valid(joint) then bullet3d.constraint.destroy(joint) end end
    for _,item in ipairs(doll.bodies) do deactivate(a,item);go.delete(item.id);a.retired[#a.retired+1]=item.id end
    doll.bodies={};doll.constraints={};doll.expired=true
    for i,d in ipairs(a.ragdolls) do if d==doll then table.remove(a.ragdolls,i);break end end
end
function M.remove_actor(a,e)
    if e.ragdoll and not e.ragdoll.expired then M.remove_ragdoll(a,e.ragdoll) end
end
function M.fixed_update(a,dt)
    if a.paused then return end
    local start=os.clock();local count=0
    for i=#a.retired,1,-1 do
        local id=a.retired[i]
        if not go.exists(id) then a.by_id[id]=nil;table.remove(a.retired,i) end
    end
    for _,item in ipairs(a.debris) do
        if item.pending and a.ctx.time.frame>item.born then
            local spec=item.pending;configure(a,item,spec,spec.velocity,spec.spin);item.pending=nil
        end
        if item.active then
            item.age=item.age+dt
            if item.age>=item.life then deactivate(a,item)
            else
                if not item.sleeping then
                    sample(item)
                    item.quiet=settled(item,dt,.06,1.2) and item.quiet+dt or 0
                    if item.quiet>.75 then item.sleeping=true;sleep(item) end
                end
                count=count+1
            end
        end
    end
    for i=#a.ragdolls,1,-1 do
        local doll=a.ragdolls[i];doll.age=doll.age+dt
        if not doll.ready and a.ctx.time.frame>doll.born then start_ragdoll(a,doll) end
        if doll.ready and not doll.sleeping then
            local quiet=true
            for j,item in ipairs(doll.bodies) do
                sample(item);doll.transforms[j]=item.shape.transform
                if not settled(item,dt,.30,4.8) then quiet=false end
            end
            doll.palette=R.palette(doll.spec,doll.transforms,doll.palette)
            doll.quiet=quiet and (doll.quiet or 0)+dt or 0
            -- Sleep the complete articulation together. Tiny constrained
            -- contacts can otherwise keep individual bodies renewing an island.
            if doll.quiet>.75 then
                doll.sleeping=true
                for _,item in ipairs(doll.bodies) do sleep(item) end
            end
        end
        if doll.ready then count=count+#doll.bodies end
        if doll.age>=R.lifetime then M.remove_ragdoll(a,doll) end
    end
    a.peak_bodies=math.max(a.peak_bodies,count)
    local elapsed=os.clock()-start;a.work_seconds=a.work_seconds+elapsed;a.ticks=a.ticks+1;a.peak_tick=math.max(a.peak_tick,elapsed)
end
function M.palette(doll,alpha)
    if not doll.ready or doll.expired then return doll.palette,T.origin(doll.spec.root) end
    if doll.sleeping and doll.presentation_sleep then return doll.presentation,doll.render_position end
    local transforms=doll.transforms
    if not doll.sleeping then
        transforms={}
        for i,item in ipairs(doll.bodies) do
            transforms[i]=transform(vmath.lerp(alpha,item.previous,item.position),vmath.slerp(alpha,item.previous_rotation,item.rotation))
        end
    end
    local root={};for i=1,12 do root[i]=doll.spec.root[i] end
    for _,i in ipairs({4,8,12}) do root[i]=root[i]+transforms[1][i]-doll.spec.bodies[1].world[i] end
    doll.render_position=T.origin(root);doll.presentation_sleep=doll.sleeping
    doll.presentation=R.palette(doll.spec,transforms,doll.presentation,root)
    return doll.presentation,doll.render_position
end
function M.present(a,alpha,hidden)
    for _,item in ipairs(a.debris) do
        visible(item,item.active and not hidden)
        if item.visible then
            local p=vmath.lerp(alpha,item.previous,item.position)
            local q=vmath.slerp(alpha,item.previous_rotation,item.rotation)
            go.set_position(p,item.visual);go.set_rotation(q,item.visual);go.set_scale(vector(item.spec.dimensions),item.visual)
            local c=item.colour;go.set(item.mesh,"tint",vmath.vector4(c[1],c[2],c[3],c[4]))
            local m=vmath.matrix4_quat(q);local d=item.spec.dimensions
            for col,scale in ipairs({d.x,d.y,d.z}) do for row=0,2 do
                local key="m"..row..(col-1);m[key]=m[key]*scale
            end end
            m.m03,m.m13,m.m23=p.x,p.y,p.z
            go.set(item.prepass,"previous_world",item.previous_world or m);item.previous_world=m
        end
    end
end
function M.suspend(a,paused)
    if a.paused==paused then return end
    a.paused=paused
    local function freeze(item)
        if not item.active then return end
        if paused then
            item.saved_state=C.get_activation_state(item.object)
            C.force_activation_state(item.object,C.DISABLE_SIMULATION)
        else
            C.force_activation_state(item.object,item.saved_state or C.ACTIVE_TAG);item.saved_state=nil
        end
    end
    for _,item in ipairs(a.debris) do freeze(item) end
    for _,doll in ipairs(a.ragdolls) do for _,item in ipairs(doll.bodies) do freeze(item) end end
end
function M.blast(a,blast)
    local origin=blast.position or blast.point;local radius=blast.radius or 0
    if not origin or radius<=0 or a.paused then return end
    local function push(item)
        if not item.active then return end
        local p=item.position;local delta={x=p.x-origin.x,y=p.y-origin.y,z=p.z-origin.z}
        local distance=V.length(delta)
        if distance>=radius then return end
        if distance>.001 and physics.raycast(vector(origin),p,{hash("world")}) then return end
        local direction=distance>.001 and V.normalize(delta) or {x=0,y=1,z=0}
        -- impulse is a radial velocity budget; mass scaling prevents tiny cases
        -- receiving humanoid-sized velocity changes. No health writes here.
        impulse(item,V.point({x=0,y=0,z=0},direction,(blast.impulse or 8)*(1-distance/radius)*item.spec.mass))
        a.impulses=a.impulses+1
    end
    for _,item in ipairs(a.debris) do push(item) end
    for _,doll in ipairs(a.ragdolls) do for _,item in ipairs(doll.bodies) do push(item) end end
end
function M.snapshot(a)
    local out={debris=0,ragdolls=#a.ragdolls,bodies=0,awake=0,constraints=0,pending=0,
        debris_limit=M.debris_limit,ragdoll_limit=M.ragdoll_limit,objects=M.debris_limit*2,buffers=1,mesh_bytes=36*10*4,
        spawned=a.spawned,recycled=a.recycled,impulses=a.impulses,peak_bodies=a.peak_bodies,paused=a.paused,
        mean_tick_ms=a.work_seconds*1000/math.max(1,a.ticks),peak_tick_ms=a.peak_tick*1000,max_linear_speed=0,max_angular_speed=0,
        registry_entries=0,retired=#a.retired,states={},articulations={}}
    for _ in pairs(a.by_id) do out.registry_entries=out.registry_entries+1 end
    local function count(item)
        if item.active then out.bodies=out.bodies+1;if C.is_awake(item.object) then out.awake=out.awake+1 end
            out.max_linear_speed=math.max(out.max_linear_speed,vmath.length(B.get_linear_velocity(item.body)))
            out.max_angular_speed=math.max(out.max_angular_speed,vmath.length(B.get_angular_velocity(item.body)))
            local state=tostring(C.get_activation_state(item.object));out.states[state]=(out.states[state] or 0)+1
        end
        if item.pending then out.pending=out.pending+1 end
    end
    for _,item in ipairs(a.debris) do count(item);if item.active then out.debris=out.debris+1 end end
    for _,doll in ipairs(a.ragdolls) do
        out.objects=out.objects+#doll.bodies;out.constraints=out.constraints+#doll.constraints
        out.articulations[#out.articulations+1]={actor=doll.actor.id,quiet=doll.quiet or 0,sleeping=doll.sleeping or false}
        for _,item in ipairs(doll.bodies) do count(item) end
    end
    return out
end
function M.reset(a)
    while #a.ragdolls>0 do M.remove_ragdoll(a,a.ragdolls[#a.ragdolls]) end
    for _,item in ipairs(a.debris) do deactivate(a,item) end
end
function M.final(a)
    events.off_owner(a.ctx.events,a);M.reset(a)
    for _,item in ipairs(a.debris) do go.delete(item.id);go.delete(item.visual) end
    resource.release(a.resource)
end
return M
