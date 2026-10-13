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
function M.pose(state)
    local rotations={}
    local function rotate(name,x,y,z) rotations[M.index[name]]=T.rotation(x,y,z) end
    local death=V.smooth(state.death or 0)
    local walk=(state.walk or 0)*(1-death)
    local phase=state.phase or 0
    local aim=(state.aim or 0)*(1-death)
    local breathe=math.sin((state.time or 0)*2.1)*.008*(1-death)
    rotate("Hips",-.10*walk,0,.025*math.sin(phase)*walk)
    rotate("Spine",breathe,0,0)
    -- The carried rifle points slightly down; bring it onto the aim line.
    rotate("Spine1",aim*(.05+(state.pitch or 0)*.45),0,0)
    rotate("Spine2",aim*(.05+(state.pitch or 0)*.55)+(state.recoil or 0)*.055,0,0)
    rotate("Head",-.07*aim,math.sin((state.time or 0)*.7)*.07*(1-aim),0)
    for _,side in ipairs({"R","L"}) do
        local swing=math.sin(phase+(side=="R" and 0 or math.pi))
        rotate("UpLeg"..side,swing*.42*walk,0,0)
        rotate("Leg"..side,-math.max(0,swing)*.65*walk,0,0)
        rotate("Foot"..side,-swing*.13*walk,0,0)
    end
    local worlds,palette={},{}
    for i,bone in ipairs(M.bones) do
        local m=rotations[i] or T.identity()
        local p=bone.local_position
        m[4],m[8],m[12]=p.x,p.y,p.z
        if i==1 then
            m[8]=m[8]+math.abs(math.sin(phase))*.025*walk+breathe*.3
            -- Bounded authored collapse, not a simulated ragdoll.
            local fall=T.rotation(death*math.pi*.49,0,death*.10)
            fall[8]=-.77*death
            m=T.mul(fall,m)
            -- Rotate around pelvis, then lower it to the floor.
            m[8]=.98-.77*death+breathe*.3+math.abs(math.sin(phase))*.025*walk
            m[12]=.005+.38*death
        end
        worlds[i]=bone.parent>0 and T.mul(worlds[bone.parent],m) or m
        palette[i]=T.mul(worlds[i],T.identity(-bone.bind.x,-bone.bind.y,-bone.bind.z))
    end
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
