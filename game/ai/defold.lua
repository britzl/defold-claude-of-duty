local geometry = require "game.ai.geometry"
local rig = require "game.ai.rig"
local capsule = require "game.player.bullet"
local V = require "game.weapons.math"
local M = {}
local WORLD={hash("world")}
local function vector(p) return vmath.vector3(p.x,p.y,p.z) end
local function matrix(t,out)
    out=out or vmath.matrix4()
    out.m00,out.m01,out.m02,out.m03=t[1],t[2],t[3],t[4]
    out.m10,out.m11,out.m12,out.m13=t[5],t[6],t[7],t[8]
    out.m20,out.m21,out.m22,out.m23=t[9],t[10],t[11],t[12]
    return out
end
local function upload(a)
    local b=geometry.build()
    local streams={{"position",3,b.positions},{"normal",3,b.normals},{"color",4,b.colors},
        {"joint_indices",4,b.joints},{"joint_weights",4,b.weights}}
    local declarations={}
    for _,s in ipairs(streams) do declarations[#declarations+1]={name=hash(s[1]),type=buffer.VALUE_TYPE_FLOAT32,count=s[2]} end
    local data=buffer.create(b.vertex_count,declarations)
    for _,s in ipairs(streams) do
        local out=buffer.get_stream(data,hash(s[1]))
        for i,v in ipairs(s[3]) do out[i]=v end
    end
    buffer.set_metadata(data,"AABB",b.bounds,buffer.VALUE_TYPE_FLOAT32)
    a.resource=resource.create_buffer("/generated/soldier_"..hash_to_hex(go.get_id())..".bufferc",{buffer=data})
    a.vertices,a.bytes=b.vertex_count,b.bytes
end
function M.new(ctx,world,mesh_factory,mover_factory,hit_factory)
    return {api=M,ctx=ctx,world=world,mesh_factory=mesh_factory,mover_factory=mover_factory,
        hit_factory=hit_factory,by_id={},instances={},retired={},uploads=0,present_seconds=0,peak_present=0,mat=vmath.matrix4()}
end
function M.create(a,e)
    if not a.resource then upload(a) end
    local item={mesh=factory.create(a.mesh_factory,vector(e.position)),
        mover=factory.create(a.mover_factory,vector(e.position)),hits={},born=a.ctx.time.frame}
    item.url=msg.url(nil,item.mesh,"mesh")
    go.set(item.url,"vertices",a.resource)
    item.prepass=msg.url(nil,item.mesh,"prepass")
    go.set(item.prepass,"vertices",a.resource)
    local volumes=rig.volumes(e.palette,e.position,e.yaw,e.id)
    for _,shape in ipairs(volumes) do
        local id=factory.create(a.hit_factory,vector(shape))
        local url=msg.url(nil,id,"collision")
        physics.set_shape(url,"box",{type=physics.SHAPE_TYPE_BOX,dimensions=vmath.vector3(shape.w,shape.h,shape.d)})
        a.by_id[id]=shape
        item.hits[#item.hits+1]={id=id,url=url}
    end
    a.instances[e.id]=item
    M.present(a,e,e.palette,e.position,e.yaw)
end
local function visible(_,from,to)
    return not physics.raycast(vector(from),vector(to),WORLD)
end
local function walkable(query,from,to)
    local distance=V.length({x=to.x-from.x,y=to.y-from.y,z=to.z-from.z})
    if distance>60 or math.abs(to.y-from.y)>4 then return false end
    local steps=math.max(1,math.ceil(distance/.45))
    local previous
    for i=0,steps do
        local f=i/steps
        local point={x=V.lerp(from.x,to.x,f),y=V.lerp(from.y,to.y,f),z=V.lerp(from.z,to.z,f)}
        local hit=physics.raycast(vmath.vector3(point.x,point.y+.43,point.z),
            vmath.vector3(point.x,point.y-.45,point.z),WORLD)
        if not hit or hit.normal.y<.707 or math.abs(hit.position.y-point.y)>.42 then return false end
        point.y=hit.position.y+.43
        if previous then
            if query:sweep(previous,1.35,point.x-previous.x,point.y-previous.y,point.z-previous.z) then return false end
        end
        previous=point
    end
    return true
end
function M.query(a,e)
    for i=#a.retired,1,-1 do
        local id=a.retired[i]
        if not go.exists(id) then a.by_id[id]=nil;table.remove(a.retired,i) end
    end
    local item=a.instances[e.id]
    if a.ctx.time.frame<=item.born then return end
    if not item.query then
        item.query=capsule.new(msg.url(nil,item.mover,"collision"),a.world.by_id)
        item.query.visible=visible;item.query.walkable=walkable
        for _,h in ipairs(item.hits) do h.object=assert(bullet3d.get_collision_object(h.url)) end
    end
    return item.query
end
function M.sync(a,e)
    local item=a.instances[e.id]
    if not item.query or item.disabled then return end
    item.query:sync(e.position,e.motion.height)
    local volumes=rig.volumes(e.palette,e.position,e.yaw,e.id)
    for i,shape in ipairs(volumes) do
        local hit=item.hits[i]
        a.by_id[hit.id]=shape
        local m=matrix(shape.transform,a.mat)
        local q=vmath.quat_matrix4(m)
        bullet3d.collision_object.set_world_transform(hit.object,vector(shape),q)
    end
end
function M.disable(a,e)
    local item=a.instances[e.id]
    if item.disabled then return end
    item.disabled=true
    msg.post(msg.url(nil,item.mover,"collision"),"disable")
    for _,h in ipairs(item.hits) do
        a.by_id[h.id].disabled=true
        msg.post(h.url,"disable")
    end
end
function M.present(a,e,palette,position,yaw)
    local started=os.clock()
    local item=a.instances[e.id]
    go.set_position(vector(position),item.mesh)
    go.set_rotation(vmath.quat_rotation_y(yaw),item.mesh)
    local current_world=vmath.matrix4_rotation_y(yaw)
    current_world.m03,current_world.m13,current_world.m23=position.x,position.y,position.z
    go.set(item.prepass,"previous_world",item.previous_world or current_world)
    item.previous_bones=item.previous_bones or {}
    for i,t in ipairs(palette) do
        local current=matrix(t)
        go.set(item.url,"bone_palette",current,{index=i})
        go.set(item.prepass,"bone_palette",current,{index=i})
        go.set(item.prepass,"previous_bones",item.previous_bones[i] or current,{index=i})
        item.previous_bones[i]=current
    end
    item.previous_world=current_world
    a.uploads=a.uploads+1
    local elapsed=os.clock()-started
    a.present_seconds=a.present_seconds+elapsed;a.peak_present=math.max(a.peak_present,elapsed)
end
function M.remove(a,e)
    local item=a.instances[e.id]
    if not item then return end
    M.disable(a,e)
    for _,h in ipairs(item.hits) do go.delete(h.id);a.retired[#a.retired+1]=h.id end
    go.delete(item.mover);go.delete(item.mesh)
    a.instances[e.id]=nil
end
function M.snapshot(a)
    local actors,objects,boxes=0,0,0
    for _,item in pairs(a.instances) do
        actors=actors+1;objects=objects+2+#item.hits
        if not item.disabled then boxes=boxes+#item.hits end
    end
    return {actors=actors,objects=objects,active_hitboxes=boxes,buffers=a.resource and 1 or 0,
        vertices=a.vertices or 0,mesh_bytes=a.bytes or 0,palette_bytes=rig.count*64*3,
        palette_uploads=a.uploads,palette_calls_per_actor=rig.count*3+1,
        mean_upload_ms=a.uploads>0 and a.present_seconds*1000/a.uploads or 0,peak_upload_ms=a.peak_present*1000}
end
function M.final(a)
    assert(next(a.instances)==nil,"Soldier instances must be removed before their shared buffer")
    if a.resource then resource.release(a.resource);a.resource=nil end
    a.by_id={};a.retired={}
end
return M
