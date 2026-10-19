-- Pure skeleton/body mapping. Native Bullet owns integration and constraints.
local rig=require "game.ai.rig"
local variants=require "game.ai.variants"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local M={lifetime=30}
local specs={
    {"Hips","Spine",.15,12,25,18}, {"Spine","Spine1",.14,8,22,18},
    {"Spine1","Spine2",.15,9,20,15}, {"Spine2","Neck",.16,12,20,15},
    {"Neck","Head",.055,1.5,30,25}, {"Head","HeadTop",.105,5,42,30},
    {"UpperArmR","ForearmR",.065,2.2,85,60}, {"ForearmR","HandR",.055,1.5,70,25},
    {"HandR","FingersR",.045,.5,45,30},
    {"UpperArmL","ForearmL",.065,2.2,85,60}, {"ForearmL","HandL",.055,1.5,70,25},
    {"HandL","FingersL",.045,.5,45,30},
    {"UpLegR","LegR",.08,7,75,35}, {"LegR","FootR",.065,3.5,65,15}, {"FootR","ToeR",.055,1,35,15},
    {"UpLegL","LegL",.08,7,75,35}, {"LegL","FootL",.065,3.5,65,15}, {"FootL","ToeL",.055,1,35,15},
}
M.count=#specs
function M.build(worlds,position,yaw,variant)
    local root=T.root(position,yaw)
    local frames=rig.joint_frames(worlds)
    local scale=variants.get(variant).scale
    local result={bodies={},bindings={},scale=scale,root=root}
    local indices={}
    for i,s in ipairs(specs) do
        local bone,tail=rig.index[s[1]],rig.index[s[2]]
        local a,b=T.origin(worlds[bone]),T.origin(worlds[tail])
        local length=V.length({x=b.x-a.x,y=b.y-a.y,z=b.z-a.z})
        local joint=T.mul(root,frames[bone].world)
        local body=T.mul(joint,T.identity(0,length*.5,0))
        local radius=s[3]*scale
        result.bodies[i]={name=s[1],bone=bone,world=body,joint=joint,
            dimensions={x=radius*2,y=length+.025*scale,z=radius*2},mass=s[4],
            swing=math.rad(s[5]),twist=math.rad(s[6])}
        indices[bone]=i
    end
    for i,b in ipairs(result.bodies) do
        local parent=rig.bones[b.bone].parent
        while parent>0 and not indices[parent] do parent=rig.bones[parent].parent end
        b.parent=indices[parent]
        if b.parent then
            -- Bullet cone twist uses X along the twist axis; our joints use Y.
            local frame=T.mul(b.joint,T.rotation(0,0,math.pi*.5))
            b.frame_a=T.mul(T.inverse(result.bodies[b.parent].world),frame)
            b.frame_b=T.mul(T.inverse(b.world),frame)
        end
    end
    for i,bone in ipairs(rig.bones) do
        local owner=i
        while not indices[owner] do owner=rig.bones[owner].parent end
        local index=indices[owner]
        result.bindings[i]={body=index,offset=T.mul(T.inverse(result.bodies[index].world),T.mul(root,worlds[i]))}
    end
    return result
end
-- Authoritative palettes retain the actor root; rendering can rebase it to the
-- moving pelvis so the mesh's conservative culling bounds follow a blasted body.
function M.palette(spec,transforms,out,root)
    out=out or {}
    local inverse=T.inverse(root or spec.root)
    for i,binding in ipairs(spec.bindings) do
        local world=T.mul(transforms[binding.body],binding.offset)
        local m=T.mul(inverse,world,out[i]);out[i]=m
        local p=rig.bones[i].bind;local s=spec.scale
        m[4]=m[4]-(m[1]*p.x+m[2]*p.y+m[3]*p.z)*s
        m[8]=m[8]-(m[5]*p.x+m[6]*p.y+m[7]*p.z)*s
        m[12]=m[12]-(m[9]*p.x+m[10]*p.y+m[11]*p.z)*s
    end
    return out
end
function M.hit_body(spec,part,region,point)
    local bone
    for _,box in ipairs(rig.hitboxes) do if box.name==part then bone=rig.index[box.bone];break end end
    if bone then return spec.bindings[bone].body end
    if region=="head" then return spec.bindings[rig.index.Head].body end
    local index,distance=1,math.huge
    if point then for i,b in ipairs(spec.bodies) do
        local p=T.origin(b.world);local d=(p.x-point.x)^2+(p.y-point.y)^2+(p.z-point.z)^2
        if d<distance then index,distance=i,d end
    end end
    return index
end
return M
