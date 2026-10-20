-- Reference src/ai/rig.js joint names, hierarchy and metre proportions. Rotate
-- the source +Z-facing carry pose 180 degrees to our -Z forward convention.
-- Render bind axes are identity; joint_frames supplies physics-oriented frames.
local T = require "game.ai.transform"
local V = require "game.weapons.math"
local variants=require "game.ai.variants"
local IK=require "game.ai.ik"
local M = {}
local function elbow(s,w,pole)
    local axis=V.normalize({x=w.x-s.x,y=w.y-s.y,z=w.z-s.z})
    local d=math.min(.29+.255-.0001,V.length({x=w.x-s.x,y=w.y-s.y,z=w.z-s.z}))
    local a=(.29*.29-.255*.255+d*d)/(2*d)
    local h=math.sqrt(math.max(0,.29*.29-a*a))
    local dot=pole.x*axis.x+pole.y*axis.y+pole.z*axis.z
    local perp=V.normalize(V.point(pole,axis,-dot))
    return V.point(V.point(s,axis,a),perp,h)
end
local bore=V.normalize({x=-.115,y=-.10,z=-1})
local function along(t,drop) return V.point({x=.148,y=1.398-drop,z=.078},bore,t) end
M.grip_r,M.grip_l=along(.26,.095),along(.45,.05)
M.muzzle=along(.80,0)
local sr,sl={x=.172,y=1.425,z=-.004},{x=-.172,y=1.425,z=-.004}
local er,el=elbow(sr,M.grip_r,{x=.35,y=-1,z=.45}),elbow(sl,M.grip_l,{x=-.55,y=-1,z=.2})
local function v(x,y,z) return {x=x,y=y,z=z} end
local specs={
    {"Hips",0,v(0,.98,.005)}, {"Spine",1,v(0,1.09,.012)},
    {"Spine1",2,v(0,1.215,0)}, {"Spine2",3,v(0,1.345,-.006)},
    {"Neck",4,v(0,1.475,.008)}, {"Head",5,v(0,1.552,-.004)}, {"HeadTop",6,v(0,1.8,-.012)},
    {"ClavicleR",4,v(.038,1.408,-.016)}, {"UpperArmR",8,sr}, {"ForearmR",9,er},
    {"HandR",10,M.grip_r}, {"FingersR",11,V.point(M.grip_r,V.normalize(v(-.30,-.35,-.89)),.075)},
    {"ClavicleL",4,v(-.038,1.408,-.016)}, {"UpperArmL",13,sl}, {"ForearmL",14,el},
    {"HandL",15,M.grip_l}, {"FingersL",16,V.point(M.grip_l,V.normalize(v(.32,-.30,-.90)),.075)},
    {"UpLegR",1,v(.092,.945,0)}, {"LegR",18,v(.098,.505,-.02)},
    {"FootR",19,v(.103,.088,.022)}, {"ToeR",20,v(.103,.03,-.108)},
    {"UpLegL",1,v(-.092,.945,0)}, {"LegL",22,v(-.098,.505,-.02)},
    {"FootL",23,v(-.103,.088,.022)}, {"ToeL",24,v(-.103,.03,-.108)},
}
M.bones,M.index={},{}
for i,s in ipairs(specs) do
    local parent=s[2]>0 and specs[s[2]][3] or v(0,0,0)
    M.bones[i]={name=s[1],parent=s[2],bind=s[3],local_position=v(s[3].x-parent.x,s[3].y-parent.y,s[3].z-parent.z)}
    M.index[s[1]]=i
end
M.count=#M.bones

-- A single evaluator owns skinning, hit volumes and ragdoll handoff frames.
function M.pose(state,scratch)
    scratch=scratch or {}
    local rotations,worlds,palette=scratch.rotations or {},scratch.worlds or {},scratch.palette or {}
    local angles={}
    local function add(name,x,y,z)
        local i=M.index[name];local a=angles[i] or {0,0,0};angles[i]=a
        a[1],a[2],a[3]=a[1]+(x or 0),a[2]+(y or 0),a[3]+(z or 0)
    end
    local death=V.smooth(state.death or 0);local live=1-death
    local crouch=V.clamp(state.crouch or 0,0,1)*live
    local walk=V.clamp(state.walk or 0,0,1)*live
    local run=V.clamp(state.run or 0,0,1)*walk*(1-crouch)
    local phase=state.phase or 0
    local aim=V.clamp(state.aim or 0,0,1)*live
    local hurt=V.clamp(state.wounded or 0,0,1)*live
    local breathe=math.sin((state.time or 0)*2.1)*.008*live
    local turn=math.sin(math.pi*V.clamp(state.turn or 0,0,1))*(state.turn_weight or 0)*live
    local turn_side=(state.turn_direction or 1)>=0 and "R" or "L"
    local vault=math.sin(math.pi*V.clamp(state.vault or 0,0,1))*(state.vault_weight or 0)*live
    local reload=math.min(1,(state.reload or 0)*6,(1-(state.reload or 0))*6)*(state.reload_weight or 0)*live
    local pitch=V.clamp(state.pitch or 0,-.6,.6)*aim
    local yaw=V.clamp(state.aim_yaw or 0,-.75,.75)*aim
    local recoil=(state.recoil or 0)*live
    add("Hips",-.85*crouch-.10*walk-.12*run-.12*hurt-.32*vault,turn*.08,.025*math.sin(phase)*walk+.04*hurt)
    add("Spine",breathe+.32*crouch-.12*hurt-.20*vault,0,-.03*hurt)
    add("Spine1",.22*crouch+pitch*.4+.05*aim-.09*hurt-.12*vault,yaw*.4-reload*.10,0)
    add("Spine2",.30*crouch+pitch*.6+.05*aim+recoil*.055-.05*hurt-.10*vault,yaw*.6-reload*.28,-reload*.05)
    add("Head",-.07*aim+.12*crouch-pitch*.25,math.sin((state.time or 0)*.7)*.07*(1-aim)+yaw*.15,0)
    add("Neck",-.07*hurt,0,0)
    add("ClavicleR",.12*crouch,0,0);add("ClavicleL",.12*crouch,0,0)
    for _,side in ipairs({"R","L"}) do
        local swing=math.sin(phase+(side=="R" and 0 or math.pi))
        local stride=walk*(1-crouch*.55)
        add("UpLeg"..side,swing*(.42+.30*run)*stride-.8*vault,0,0)
        add("Leg"..side,-math.max(0,swing)*(.65+.65*run)*stride-1.0*vault,0,0)
        add("Foot"..side,-swing*.13*stride+.35*vault,0,0)
        if side==turn_side then add("UpLeg"..side,-.18*turn,0,0);add("Leg"..side,-.5*turn,0,0) end
    end
    local hit=(state.hit or 0)*live
    local side=state.hit_side or 1
    local region=state.hit_region or "torso"
    if hit>0 then
        if region=="head" then
            add("Head",-.35*hit,side*.24*hit,side*.14*hit);add("Neck",-.22*hit,0,0)
        elseif region=="arm" then
            add(side>0 and "ClavicleR" or "ClavicleL",-.24*hit,side*.1*hit,side*.18*hit)
            add("Spine2",-.09*hit,side*.10*hit,0)
        elseif region=="leg" then
            add("Hips",-.14*hit,0,-side*.10*hit)
            add(side>0 and "UpLegR" or "UpLegL",-.24*hit,0,side*.1*hit)
        else
            add("Spine",-.10*hit,side*.05*hit,side*.03*hit)
            add("Spine1",-.16*hit,side*.08*hit,side*.05*hit)
            add("Spine2",-.19*hit,side*.10*hit,side*.07*hit)
        end
    end
    local pelvis=(state.pelvis or 0)*live
    for i,bone in ipairs(M.bones) do
        local a=angles[i] or {0,0,0}
        local m=T.rotation(a[1],a[2],a[3],rotations[i]);rotations[i]=m
        local p=bone.local_position;m[4],m[8],m[12]=p.x,p.y,p.z
        if i==1 then
            local fall=T.rotation(death*math.pi*.49,0,death*.10)
            m=T.mul(fall,m)
            m[8]=.98-.77*death-.70*crouch-.10*hurt+breathe*.3+math.abs(math.sin(phase))*.025*walk+pelvis+.10*vault
            m[12]=.005+.38*death+.12*crouch+.03*hurt
        end
        if bone.parent>0 then worlds[i]=T.mul(worlds[bone.parent],m,worlds[i])
        else
            worlds[i]=worlds[i] or {};for k=1,12 do worlds[i][k]=m[k] end
        end
    end
    -- Lower the pelvis enough to reach planted ankles without stretching knees.
    local reach_drop=0
    if live>0 and vault<.001 then
        for _,side in ipairs({"R","L"}) do
            local foot=state.feet and state.feet[side]
            if foot and foot.weight>0 then
                local hip=T.origin(worlds[M.index["UpLeg"..side]])
                local knee=T.origin(worlds[M.index["Leg"..side]])
                local ankle=T.origin(worlds[M.index["Foot"..side]])
                local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
                local reach=distance(hip,knee)+distance(knee,ankle)-.003
                local p=foot.target
                local vertical=math.sqrt(math.max(.01,reach^2-(hip.x-p.x)^2-(hip.z-p.z)^2))
                reach_drop=math.min(reach_drop,(p.y+vertical-hip.y)*foot.weight*live)
            end
        end
        reach_drop=math.max(-.32,reach_drop)
        for _,w in ipairs(worlds) do w[8]=w[8]+reach_drop end
    end
    scratch.reach_drop=reach_drop
    -- Correct feet after the additive layers, before solving the carried weapon.
    for _,side in ipairs({"R","L"}) do
        local foot=state.feet and state.feet[side]
        local solve=live>0 and vault<.001 and ((foot and foot.weight>1e-6) or (not foot and (crouch>0 or hurt>0)))
        if solve then
            local at=T.origin(worlds[M.index["Foot"..side]])
            local target=foot and foot.target or {x=side=="R" and .103 or -.103,y=.088,z=.022}
            local weight=foot and foot.weight or 1
            target={x=V.lerp(at.x,target.x,weight*live),y=V.lerp(at.y,target.y,weight*live),z=V.lerp(at.z,target.z,weight*live)}
            IK.solve(worlds,M.bones,M.index["UpLeg"..side],M.index["Leg"..side],M.index["Foot"..side],target,{x=side=="R" and .10 or -.10,y=.05,z=-1})
            local normal=foot and foot.normal or {x=0,y=1,z=0}
            -- Source caps sole tilt at 0.35 radians; reject steep wall normals.
            local ny=math.max(math.cos(.35),normal.y)
            local horizontal=math.sqrt(normal.x^2+normal.z^2)
            local limit=math.sqrt(math.max(0,1-ny*ny))
            local k=horizontal>1e-7 and math.min(1,limit/horizontal) or 0
            IK.orient(worlds,M.bones,M.index["Foot"..side],T.between({x=0,y=1,z=0},V.normalize({x=normal.x*k,y=ny,z=normal.z*k})))
        end
    end
    -- A rigid weapon frame follows the chest. Both hands solve to its sockets.
    local chest=worlds[M.index.Spine2]
    local gun=T.mul(chest,T.identity(-M.bones[M.index.Spine2].bind.x,-M.bones[M.index.Spine2].bind.y,-M.bones[M.index.Spine2].bind.z))
    local pivot=M.grip_r
    local layer=T.mul(T.identity(pivot.x,pivot.y,pivot.z),T.rotation(-.24*run+.08*reload,.10*reload,-.10*run-.20*reload))
    layer=T.mul(layer,T.identity(-pivot.x,-pivot.y,-pivot.z))
    gun=T.mul(gun,layer)
    local right=T.point(gun,M.grip_r)
    IK.solve(worlds,M.bones,M.index.UpperArmR,M.index.ForearmR,M.index.HandR,right,{x=.35,y=-1,z=.45})
    IK.orient(worlds,M.bones,M.index.HandR,gun)
    -- Use the solved hand frame so the support hand always follows the mesh.
    local hand=worlds[M.index.HandR]
    gun=T.mul(hand,T.identity(-M.grip_r.x,-M.grip_r.y,-M.grip_r.z))
    local support=T.point(gun,variants.support(state.variant))
    if reload>0 then
        local mag=T.point(gun,variants.magazine)
        local pouch=T.point(worlds[M.index.Spine2],{x=.02,y=-.155,z=-.164})
        local t=state.reload
        local a,b,w
        if t<.18 then a,b,w=support,mag,t/.18
        elseif t<.42 then a,b,w=mag,pouch,(t-.18)/.24
        elseif t<.62 then a,b,w=pouch,mag,(t-.42)/.20
        elseif t<.78 then a,b,w=mag,mag,0
        else a,b,w=mag,support,(t-.78)/.22 end
        support={x=V.lerp(a.x,b.x,V.smooth(w)),y=V.lerp(a.y,b.y,V.smooth(w)),z=V.lerp(a.z,b.z,V.smooth(w))}
    end
    if vault>0 then
        local shoulder=T.origin(worlds[M.index.UpperArmL])
        local plant=state.vault_hand or {x=shoulder.x-.10,y=shoulder.y-.35,z=shoulder.z-.18}
        support={x=V.lerp(support.x,plant.x,vault),y=V.lerp(support.y,plant.y,vault),z=V.lerp(support.z,plant.z,vault)}
    end
    -- Off-hand lob leaves the weapon in the right hand. The grenade release
    -- socket is this same solved hand in simulation and interpolated skinning.
    if (state.throw_weight or 0)>0 then
        local t=state.throw or 0
        local shoulder=T.origin(worlds[M.index.UpperArmL])
        local windup={x=shoulder.x-.12,y=shoulder.y+.24,z=shoulder.z+.20}
        local release={x=shoulder.x-.10,y=shoulder.y+.18,z=shoulder.z-.40}
        local from,to,w
        if t<.35 then from,to,w=support,windup,t/.35
        elseif t<.54 then from,to,w=windup,release,(t-.35)/.19
        else from,to,w=release,support,(t-.54)/.46 end
        w=V.smooth(w)
        local weight=(state.throw_weight or 0)*live
        support={x=V.lerp(support.x,V.lerp(from.x,to.x,w),weight),
            y=V.lerp(support.y,V.lerp(from.y,to.y,w),weight),
            z=V.lerp(support.z,V.lerp(from.z,to.z,w),weight)}
    end
    IK.solve(worlds,M.bones,M.index.UpperArmL,M.index.ForearmL,M.index.HandL,support,{x=-.55,y=-1,z=.2})
    IK.orient(worlds,M.bones,M.index.HandL,gun)
    scratch.support_error=V.length({x=worlds[M.index.HandL][4]-support.x,y=worlds[M.index.HandL][8]-support.y,z=worlds[M.index.HandL][12]-support.z})
    scratch.support_target=support;scratch.weapon_frame=gun
    local scale=variants.get(state.variant).scale
    for i,bone in ipairs(M.bones) do
        local w=worlds[i];w[4],w[8],w[12]=w[4]*scale,w[8]*scale,w[12]*scale
        local b=bone.bind;local out=palette[i] or {}
        for k=1,12 do out[k]=w[k] end
        out[4]=w[4]-(w[1]*b.x+w[2]*b.y+w[3]*b.z)*scale
        out[8]=w[8]-(w[5]*b.x+w[6]*b.y+w[7]*b.z)*scale
        out[12]=w[12]-(w[9]*b.x+w[10]*b.y+w[11]*b.z)*scale
        palette[i]=out
    end
    scratch.rotations,scratch.worlds,scratch.palette=rotations,worlds,palette
    return palette,worlds
end

-- Physics frames use +Y down each joint, +Z approximately actor-forward. The
-- local offsets map those frames back to our identity-axis rendering skeleton.
function M.joint_frames(worlds)
    local frames={}
    for i,bone in ipairs(M.bones) do
        local child
        for j=i+1,#M.bones do if M.bones[j].parent==i then child=j;break end end
        local origin=T.origin(worlds[i]);local direction
        if child then
            local tail=T.origin(worlds[child]);direction=V.normalize({x=tail.x-origin.x,y=tail.y-origin.y,z=tail.z-origin.z})
        else direction=T.direction(worlds[i],{x=0,y=1,z=0}) end
        local forward=T.direction(worlds[i],{x=0,y=0,z=-1})
        local x=T.cross(direction,forward)
        if V.length(x)<1e-6 then x=T.cross(direction,{x=1,y=0,z=0}) end
        x=V.normalize(x);local z=T.cross(x,direction)
        local f={x.x,direction.x,z.x,origin.x,x.y,direction.y,z.y,origin.y,x.z,direction.z,z.z,origin.z}
        frames[i]={world=f,render_from_joint=T.mul(T.inverse(f),worlds[i])}
        if bone.parent>0 then frames[i].parent_local=T.mul(T.inverse(frames[bone.parent].world),f) end
    end
    return frames
end

M.hitboxes={
    {name="head",bone="Head",center=v(0,1.67,-.008),w=.235,h=.26,d=.235,headshot=true,region="head",damage_scale=4},
    {name="chest",bone="Spine2",center=v(0,1.30,0),w=.38,h=.36,d=.25,region="torso",damage_scale=1},
    {name="hips",bone="Hips",center=v(0,1.02,0),w=.32,h=.22,d=.25,region="torso",damage_scale=.9},
    {name="leg_r",bone="UpLegR",center=v(.096,.73,-.01),w=.17,h=.43,d=.18,region="leg",damage_scale=.7},
    {name="leg_l",bone="UpLegL",center=v(-.096,.73,-.01),w=.17,h=.43,d=.18,region="leg",damage_scale=.7},
    {name="shin_r",bone="LegR",center=v(.1,.295,.008),w=.135,h=.39,d=.15,region="leg",damage_scale=.7},
    {name="shin_l",bone="LegL",center=v(-.1,.295,.008),w=.135,h=.39,d=.15,region="leg",damage_scale=.7},
}
-- Reference arm scale/radius, split at the elbow so both segments follow the
-- actual mesh bones. The bind frame aligns each box's long axis with the limb.
for _,side in ipairs({"R","L"}) do
    for _,segment in ipairs({{"upper_arm_","UpperArm","Forearm"},{"forearm_","Forearm","Hand"}}) do
        local bone,tail=segment[2]..side,segment[3]..side
        local a,b=M.bones[M.index[bone]].bind,M.bones[M.index[tail]].bind
        local delta=v(b.x-a.x,b.y-a.y,b.z-a.z)
        local y=V.normalize(delta)
        local x=V.normalize(v(y.y,-y.x,0))
        local z=v(x.y*y.z-x.z*y.y,x.z*y.x-x.x*y.z,x.x*y.y-x.y*y.x)
        M.hitboxes[#M.hitboxes+1]={name=segment[1]..side:lower(),bone=bone,center=V.point(a,delta,.5),
            w=.144,h=V.length(delta)+.04,d=.144,region="arm",damage_scale=.65,
            orientation={x.x,y.x,z.x,0,x.y,y.y,z.y,0,x.z,y.z,z.z,0}}
    end
end
function M.volumes(palette,position,yaw,id,variant)
    local definition=variants.get(variant);local scale=definition.scale
    local root=T.root(position,yaw)
    local out={}
    for i,box in ipairs(M.hitboxes) do
        local transform=T.mul(root,palette[M.index[box.bone]])
        local center=T.point(transform,{x=box.center.x*scale,y=box.center.y*scale,z=box.center.z*scale})
        if box.orientation then transform=T.mul(transform,box.orientation) end
        transform[4],transform[8],transform[12]=center.x,center.y,center.z
        out[i]={id=id.."/"..box.name,actor=id,surface="flesh",headshot=box.headshot,
            region=box.region,part=box.name,damage_scale=box.damage_scale,
            x=center.x,y=center.y,z=center.z,w=box.w*scale*(box.region=="head" and 1 or definition.bulk),h=box.h*scale,d=box.d*scale*(box.region=="head" and 1 or definition.bulk),transform=transform}
    end
    return out
end
return M
