local geometry = require "game.weapons.geometry"
local pose = require "game.weapons.viewmodel"
local trace = require "game.weapons.trace"
local origin_index = require "game.weapons.origin_index"
local V = require "game.weapons.math"
local events = require "game.events"
local arms = require "game.weapons.arms"
local M = {}
local POSITION,NORMAL,COLOR=hash("position"),hash("normal"),hash("color")
local GROUPS={hash("world"),hash("enemy"),hash("debris")}
local function vector(p) return vmath.vector3(p[1],p[2],p[3]) end
local function rotation(r) return vmath.quat_rotation_y(r[2])*vmath.quat_rotation_x(r[1])*vmath.quat_rotation_z(r[3]) end
local function upload(adapter,batch,factory_url)
    local declarations={
        {name=POSITION,type=buffer.VALUE_TYPE_FLOAT32,count=3},
        {name=NORMAL,type=buffer.VALUE_TYPE_FLOAT32,count=3},
        {name=COLOR,type=buffer.VALUE_TYPE_FLOAT32,count=4}}
    if batch.joints then declarations[#declarations+1]={name=hash("joint"),type=buffer.VALUE_TYPE_FLOAT32,count=1} end
    local data=buffer.create(batch.vertex_count,declarations)
    local p,n,c=buffer.get_stream(data,POSITION),buffer.get_stream(data,NORMAL),buffer.get_stream(data,COLOR)
    for i=1,#batch.positions do p[i]=batch.positions[i];n[i]=batch.normals[i] end
    for i=1,#batch.colors do c[i]=batch.colors[i] end
    if batch.joints then
        local joints=buffer.get_stream(data,hash("joint"))
        for i,v in ipairs(batch.joints) do joints[i]=v end
    end
    buffer.set_metadata(data,"AABB",batch.bounds,buffer.VALUE_TYPE_FLOAT32)
    local id=factory.create(factory_url)
    local path=resource.create_buffer("/generated/weapon_"..hash_to_hex(id)..".bufferc",{buffer=data})
    go.set(msg.url(nil,id,"mesh"),"vertices",path)
    adapter.objects[#adapter.objects+1]=id;adapter.buffers[#adapter.buffers+1]=path
    adapter.vertices=adapter.vertices+batch.vertex_count
    return {id=id,url=msg.url(nil,id,"mesh"),visible=true}
end
local function visible(part,enabled)
    if part.visible~=enabled then
        msg.post(part.url,enabled and "enable" or "disable")
        if part.prepass then msg.post(part.prepass,enabled and "enable" or "disable") end
        part.visible=enabled
    end
end
function M.new(ctx,mesh_factory,effect_factory)
    local a={models={},objects={},buffers={},effects={},effect_cursor=0,vertices=0,arms={}}
    for _,id in ipairs({"rifle","smg","pistol"}) do
        local model=geometry.weapon(id)
        a.models[id]=model
        for _,name in ipairs(geometry.part_names) do
            model.parts[name]=upload(a,model.parts[name],name=="flash" and "#weapon_flash" or mesh_factory)
            visible(model.parts[name],false)
        end
        go.set_scale(.14,model.parts.flash.id)
        go.set(model.parts.reticle.url,"tint",vmath.vector4(1,1,1,1))
    end
    for _,side in ipairs({"left","right"}) do
        a.arms[side]=upload(a,arms.geometry(side=="left" and -1 or 1),"#weapon_arm")
        a.arms[side].palette={}
        visible(a.arms[side],false)
    end
    -- Fixed resource budget for short-lived surface particles and tracers.
    local cube=geometry.batch();geometry.box(cube,0,0,0,1,1,1,{1,1,1,0})
    for _=1,24 do
        local part=upload(a,cube,effect_factory);part.life=0
        part.prepass=msg.url(nil,part.id,"prepass")
        go.set(part.prepass,"vertices",a.buffers[#a.buffers])
        visible(part,false);a.effects[#a.effects+1]=part
    end
    local function effect(position,velocity,color,size,life)
        a.effect_cursor=a.effect_cursor%#a.effects+1
        local e=a.effects[a.effect_cursor]
        e.position=V.copy(position);e.velocity=velocity;e.life=life;e.duration=life;e.size=size
        e.tracer=false;e.previous_world=nil
        go.set(e.url,"tint",vmath.vector4(color[1],color[2],color[3],0))
        go.set_rotation(vmath.quat(),e.id)
        visible(e,true)
        return e
    end
    events.on(ctx.events,events.BULLET_IMPACT,a,function(_,hit)
        local colors={sparks={1,.66,.15},splinters={.46,.28,.11},dust={.76,.68,.50},flesh={.45,.10,.07}}
        local color=colors[hit.effect] or {.57,.57,.52}
        for i=1,3 do
            local n=hit.normal
            local e=effect(hit.point,{x=n.x*(.7+i*.3)+(i-2)*.4,y=n.y+1+i*.2,z=n.z*(.7+i*.3)},color,
                hit.effect=="sparks" and .018 or .035, .25+i*.04)
            if hit.effect=="sparks" then go.set(e.url,"tint",vmath.vector4(color[1],color[2],color[3],1)) end
        end
    end)
    events.on(ctx.events,events.BULLET_TRACER,a,function(_,shot)
        local delta={x=shot.to.x-shot.from.x,y=shot.to.y-shot.from.y,z=shot.to.z-shot.from.z}
        local length=V.length(delta)
        if length<.01 then return end
        local e=effect(V.point(shot.from,delta,.5),{x=0,y=0,z=0},{.95,.78,.36},.008,.035)
        e.tracer=true;e.length=length
        go.set(e.url,"tint",vmath.vector4(.95,.78,.36,1))
        local q=V.forward_rotation(delta)
        go.set_rotation(vmath.quat(q.x,q.y,q.z,q.w),e.id)
    end)
    return a
end
function M.update(a,ctx,dt,shown,capture_pose,capture_weapon,capture_flash)
    local w=ctx.weapons
    local equipped=capture_pose and (capture_weapon or "rifle") or w.equipped
    local active=a.models[equipped]
    local sample=capture_pose and pose.capture(active,capture_pose=="ads",equipped) or pose.pose(ctx,active)
    if capture_flash then sample.parts.flash.visible=true end
    local q=rotation(sample.rotation)
    local root=vector(sample.position)
    for id,model in pairs(a.models) do
        for name,part in pairs(model.parts) do
            local part_pose=sample.parts[name]
            local enabled=shown and id==equipped and part_pose.visible
            visible(part,enabled)
            if enabled then
                go.set_position(root+vmath.rotate(q,vector(part_pose.position)),part.id)
                go.set_rotation(q*rotation(part_pose.rotation),part.id)
            end
        end
    end
    for side,part in pairs(a.arms) do
        visible(part,shown)
        if shown then
            for i,t in ipairs(sample.arms[side]) do
                local m=part.palette[i] or vmath.matrix4();part.palette[i]=m
                m.m00,m.m01,m.m02,m.m03=t[1],t[2],t[3],t[4]
                m.m10,m.m11,m.m12,m.m13=t[5],t[6],t[7],t[8]
                m.m20,m.m21,m.m22,m.m23=t[9],t[10],t[11],t[12]
            end
            go.set(part.url,"arm_palette",part.palette)
        end
    end
    a.sample=sample
    for _,e in ipairs(a.effects) do
        if capture_pose then visible(e,false)
        elseif e.life>0 then
            e.life=math.max(0,e.life-dt)
            if not e.tracer then
                e.velocity.y=e.velocity.y-9.81*dt
                e.position=V.point(e.position,e.velocity,dt)
            end
            go.set_position(vmath.vector3(e.position.x,e.position.y,e.position.z),e.id)
            go.set_scale(vmath.vector3(e.size,e.size,e.tracer and e.length or e.size),e.id)
            local transform=vmath.matrix4_quat(go.get_rotation(e.id))
            local scale={e.size,e.size,e.tracer and e.length or e.size}
            for col=0,2 do for row=0,2 do
                local key="m"..row..col;transform[key]=transform[key]*scale[col+1]
            end end
            transform.m03,transform.m13,transform.m23=e.position.x,e.position.y,e.position.z
            go.set(e.prepass,"previous_world",e.previous_world or transform)
            e.previous_world=transform
            visible(e,e.life>0)
        end
    end
    return sample
end
function M.query(registries,options)
    options=options or {}
    local groups={}
    for _,group in ipairs(options.groups or GROUPS) do groups[group]=true end
    return {segment=function(_,from,dir,length)
        if length<=1e-9 then return {} end
        -- This immediate API refreshes broadphase bounds after skeleton setters.
        -- physics.raycast can otherwise miss a moved limb until the next step.
        local hits=bullet3d.world.cast_ray(bullet3d.get_world(),vmath.vector3(from.x,from.y,from.z),
            vmath.vector3(dir.x*length,dir.y*length,dir.z*length),{include_triggers=false})
        local result,seen={},{}
        for _,hit in ipairs(hits) do
            hit.id=bullet3d.get_gameobject_id(hit.object)
            if hit.id and groups[physics.get_group(msg.url(nil,hit.id,"collision"))] then
                local shape
                for _,registry in ipairs(registries) do shape=registry[hit.id] or shape end
                if shape and shape.disabled then
                    seen[hit.id]=true
                elseif shape then
                    local interval=trace.box(shape,from,dir,length)
                    if interval then result[#result+1]=interval;seen[hit.id]=true end
                else
                    local actor=options.actors and options.actors[hit.id]
                    result[#result+1]={id=hash_to_hex(hit.id),surface=actor and "flesh" or "concrete",actor=actor,enter=hit.fraction*length,
                        normal={x=hit.normal.x,y=hit.normal.y,z=hit.normal.z}}
                end
            end
        end
        -- Bullet rays starting inside a shape do not report its entry. Include
        -- only containing boxes, using the very same collider descriptions.
        for _,registry in ipairs(registries) do
            local index=options.origin_indices and options.origin_indices[registry]
            local candidates=index and origin_index.candidates(index,from,dir) or registry
            for id,shape in pairs(candidates) do
                if not seen[id] and not shape.disabled and trace.contains_origin(shape,from,dir) then
                    local interval=trace.box(shape,from,dir,length)
                    if interval and interval.enter<=1e-7 then result[#result+1]=interval end
                end
            end
        end
        return result
    end}
end
function M.reset(a)
    for _,e in ipairs(a.effects) do e.life=0;e.previous_world=nil;visible(e,false) end
end
function M.final(a,ctx)
    events.off_owner(ctx.events,a)
    for _,id in ipairs(a.objects) do go.delete(id) end
    for _,path in ipairs(a.buffers) do resource.release(path) end
end
return M
