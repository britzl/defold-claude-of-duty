-- Reference src/ai/rig.js joint names, hierarchy and metre proportions. Rotate
-- the source +Z-facing carry pose 180 degrees to our -Z forward convention.
-- Bind axes are identity here; ragdoll joint frames will need a separate mapping.
local T = require "game.ai.transform"
local V = require "game.weapons.math"
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

-- phase is distance-driven; aim/death/time are fixed-tick state interpolated
-- only by the presenter. The same evaluator supplies authoritative hit volumes.
-- Optional scratch belongs to one evaluator (simulation or presentation).
-- Never share it between those clocks, with hit volumes, or another soldier.
function M.pose(state,scratch)
    local rotations=scratch and scratch.rotations or {}
    local function rotate(name,x,y,z)
        local i=M.index[name]
        rotations[i]=T.rotation(x,y,z,rotations[i])
    end
    local death=V.smooth(state.death or 0)
    local crouch=V.clamp(state.crouch or 0,0,1)*(1-death)
    local walk=(state.walk or 0)*(1-death)*(1-crouch*.7)
    local phase=state.phase or 0
    local aim=(state.aim or 0)*(1-death)
    local breathe=math.sin((state.time or 0)*2.1)*.008*(1-death)
    local hip_pitch=-.85*crouch-.10*walk*(1-crouch)
    rotate("Hips",hip_pitch,0,.025*math.sin(phase)*walk*(1-crouch))
    rotate("Spine",breathe,0,0)
    -- The carried rifle points slightly down; bring it onto the aim line.
    rotate("Spine1",aim*(.05+(state.pitch or 0)*.45),0,0)
    rotate("Spine2",aim*(.05+(state.pitch or 0)*.55)+(state.recoil or 0)*.055,0,0)
    rotate("Head",.60*crouch-.07*aim,math.sin((state.time or 0)*.7)*.07*(1-aim),0)
    rotate("ClavicleR",.9*crouch,0,0)
    rotate("ClavicleL",.9*crouch,0,0)
    for _,side in ipairs({"R","L"}) do
        local swing=math.sin(phase+(side=="R" and 0 or math.pi))
        rotate("UpLeg"..side,swing*.42*walk,0,0)
        rotate("Leg"..side,-math.max(0,swing)*.65*walk,0,0)
        rotate("Foot"..side,-swing*.13*walk,0,0)
        if crouch>0 then
            -- Bend each leg toward a planted ankle as the pelvis lowers. This
            -- small sagittal solve prevents the duck from sinking feet below
            -- the floor; it is not terrain-following foot IK.
            local upper=M.bones[M.index["UpLeg"..side]].local_position
            local shin=M.bones[M.index["Leg"..side]].local_position
            local foot=M.bones[M.index["Foot"..side]].local_position
            local hy=.98-.70*crouch+math.cos(hip_pitch)*upper.y-math.sin(hip_pitch)*upper.z
            local hz=.005+.12*crouch+math.sin(hip_pitch)*upper.y+math.cos(hip_pitch)*upper.z
            local dy,dz=.088-hy,.022-hz
            local a=math.sqrt(shin.y^2+shin.z^2)
            local b=math.sqrt(foot.y^2+foot.z^2)
            local d=V.clamp(math.sqrt(dy*dy+dz*dz),math.abs(a-b)+.00001,a+b-.00001)
            local axis=math.atan2(-dz,-dy)
            local bend=math.acos(V.clamp((a*a+d*d-b*b)/(2*a*d),-1,1))
            local thigh=axis+bend
            local knee_y,knee_z=hy-math.cos(thigh)*a,hz-math.sin(thigh)*a
            local lower=math.atan2(-(.022-knee_z),-(.088-knee_y))
            local upper_angle=thigh-math.atan2(-shin.z,-shin.y)
            local lower_angle=lower-math.atan2(-foot.z,-foot.y)
            rotate("UpLeg"..side,upper_angle-hip_pitch,0,0)
            rotate("Leg"..side,lower_angle-upper_angle,0,0)
            rotate("Foot"..side,-lower_angle,0,0)
        end
    end
    local worlds,palette=scratch and scratch.worlds or {},scratch and scratch.palette or {}
    for i,bone in ipairs(M.bones) do
        local m=rotations[i] or T.identity()
        rotations[i]=m
        local p=bone.local_position
        m[4],m[8],m[12]=p.x,p.y,p.z
        if i==1 then
            m[8]=m[8]+math.abs(math.sin(phase))*.025*walk+breathe*.3
            -- Bounded authored collapse, not a simulated ragdoll.
            local fall=T.rotation(death*math.pi*.49,0,death*.10,scratch and scratch.fall)
            if scratch then scratch.fall=fall end
            fall[8]=-.77*death
            m=T.mul(fall,m,worlds[i])
            -- Rotate around pelvis, then lower it to the floor.
            m[8]=.98-.77*death-.70*crouch+breathe*.3+math.abs(math.sin(phase))*.025*walk*(1-crouch)
            m[12]=.005+.38*death+.12*crouch
        end
        worlds[i]=bone.parent>0 and T.mul(worlds[bone.parent],m,worlds[i]) or m
        -- Bind axes are identity: world * inverse_bind only changes translation.
        local w,b,out=worlds[i],bone.bind,palette[i] or {}
        out[1],out[2],out[3],out[4]=w[1],w[2],w[3],w[1]*-b.x+w[2]*-b.y+w[3]*-b.z+w[4]
        out[5],out[6],out[7],out[8]=w[5],w[6],w[7],w[5]*-b.x+w[6]*-b.y+w[7]*-b.z+w[8]
        out[9],out[10],out[11],out[12]=w[9],w[10],w[11],w[9]*-b.x+w[10]*-b.y+w[11]*-b.z+w[12]
        palette[i]=out
    end
    if scratch then scratch.rotations,scratch.worlds,scratch.palette=rotations,worlds,palette end
    return palette,worlds
end

M.hitboxes={
    {name="head",bone="Head",center=v(0,1.67,-.008),w=.235,h=.26,d=.235,headshot=true},
    {name="chest",bone="Spine2",center=v(0,1.30,0),w=.38,h=.36,d=.25},
    {name="hips",bone="Hips",center=v(0,1.02,0),w=.32,h=.22,d=.25},
    {name="leg_r",bone="UpLegR",center=v(.096,.73,-.01),w=.17,h=.43,d=.18},
    {name="leg_l",bone="UpLegL",center=v(-.096,.73,-.01),w=.17,h=.43,d=.18},
    {name="shin_r",bone="LegR",center=v(.1,.295,.008),w=.135,h=.39,d=.15},
    {name="shin_l",bone="LegL",center=v(-.1,.295,.008),w=.135,h=.39,d=.15},
}
function M.volumes(palette,position,yaw,id)
    local root=T.root(position,yaw)
    local out={}
    for i,box in ipairs(M.hitboxes) do
        local transform=T.mul(root,palette[M.index[box.bone]])
        local center=T.point(transform,box.center)
        transform[4],transform[8],transform[12]=center.x,center.y,center.z
        out[i]={id=id.."/"..box.name,actor=id,surface="flesh",headshot=box.headshot,
            x=center.x,y=center.y,z=center.z,w=box.w,h=box.h,d=box.d,transform=transform}
    end
    return out
end
return M
