local V = require "game.weapons.math"
local T = require "game.ai.transform"
local clips = require "game.weapons.clips"
local defs = require "game.weapons.defs"
local arms = require "game.weapons.arms"
local geometry = require "game.weapons.geometry"
local M = {}
local function vector(p) return {x=p[1],y=p[2],z=p[3]} end
local function transform(p,r)
    local t=T.rotation(r[1],r[2],r[3]);t[4],t[8],t[12]=p[1],p[2],p[3];return t
end
local function pivot(part,point,rotation)
    local t=T.rotation(rotation,0,0);local p=T.direction(t,vector(point))
    part.position={point[1]-p.x,point[2]-p.y,point[3]-p.z};part.rotation={rotation,0,0}
end
function M.pose(ctx,model)
    local w=ctx.weapons
    local d=defs[w.equipped]
    local alpha=ctx.time.alpha
    local ads=V.smooth(V.lerp(w.previous_ads,w.ads,alpha))
    local recoil={}
    for k,s in pairs(w.recoil) do recoil[k]=V.lerp(w.previous_recoil[k],s.x,alpha) end
    local clip_time=w.clip_time or 0
    if w.clip and w.previous_clip==w.clip then clip_time=V.lerp(w.previous_clip_time,clip_time,alpha) end
    local clip=clips.sample(w.clip,w.clip and clip_time/w.clip_duration or 0,model,d)
    local transition=w.clip_transition
    if transition then
        local old=clips.sample(transition.name,transition.progress,model,d)
        local weight=V.smooth(transition.age/.12)
        for _,key in ipairs({"pos","rot","mag_position"}) do
            for i=1,3 do clip[key][i]=V.lerp(old[key][i],clip[key][i],weight) end
        end
        for _,key in ipairs({"position","finger","back"}) do
            for i=1,3 do clip.left[key][i]=V.lerp(old.left[key][i],clip.left[key][i],weight) end
        end
        if weight<.5 then clip.left.pose,clip.left.next_pose,clip.left.blend=old.left.pose,old.left.next_pose,old.left.blend end
    end
    local function motion(key)
        local m=w.motion
        return m and V.lerp(m.previous[key],m.current[key],alpha) or 0
    end
    local p,r={},{}
    for i=1,3 do
        p[i]=V.lerp(d.hipPos[i],d.sprintPos[i],motion("sprint"))
        p[i]=V.lerp(p[i],d.lowReadyPos[i],motion("low"))
        r[i]=V.lerp(d.hipRot[i],d.sprintRot[i],motion("sprint"))
        r[i]=V.lerp(r[i],d.lowReadyRot[i],motion("low"))
        r[i]=V.lerp(r[i],d.adsCant[i],ads)+clip.rot[i]
    end
    p[1]=p[1]+motion("x");p[2]=p[2]+motion("y")+recoil.up;p[3]=p[3]+motion("z")+recoil.back
    r[1]=r[1]+motion("pitch")+recoil.pitch*.8
    r[2]=r[2]+motion("yaw");r[3]=r[3]+motion("roll")+recoil.roll
    -- Solve after cant and additive layers: full ADS keeps the sight on the
    -- optical axis. The world camera owns the actual aim and recoil.
    local sight=V.rotate(vector(model.sight),r[1],r[2],r[3])
    local aimed={-sight.x,-sight.y,-d.eyeRelief-sight.z}
    for i=1,3 do p[i]=V.lerp(p[i],aimed[i],ads)+clip.pos[i] end
    local sample={position=p,rotation=r,parts={},ads=ads,world_fov=math.rad(70)*V.lerp(1,d.adsFov,ads),
        view_fov=math.rad(60)*V.lerp(1,d.viewFov,ads),arms={},joints={}}
    for _,name in ipairs(geometry.part_names) do sample.parts[name]={position={0,0,0},rotation={0,0,0},visible=true} end
    sample.parts.magazine.position=clip.mag_position
    sample.parts.magazine.visible=clip.mag_visible
    local s=w.inventory[w.equipped]
    local since=w.since_shot
    if w.previous_since_shot and since>=w.previous_since_shot then since=V.lerp(w.previous_since_shot,since,alpha) end
    local cycle=math.max(0,1-since/.085)
    local bolt=math.max(cycle,clip.bolt,not s.chambered and 1 or 0)
    sample.parts.bolt.position[3]=bolt*(d.id=="pistol" and .035 or .055)
    sample.parts.charge.position[3]=clip.charge*.065
    pivot(sample.parts.trigger,model.trigger,-.34*motion("trigger"))
    pivot(sample.parts.selector,model.selector,d.id=="pistol" and -.3*motion("trigger") or -.65*((s.mode or 1)-1))
    for i=1,3 do sample.parts.flash.position[i]=model.muzzle[i] end
    sample.parts.flash.position[3]=sample.parts.flash.position[3]-.035
    sample.parts.flash.visible=w.flash>0
    sample.parts.reticle.visible=ads>.8 and not w.clip
    local root=transform(p,r)
    -- Collimated dot: project the camera's optical axis onto the lens plane,
    -- then express that point in weapon space. It must not follow the tube's
    -- animated centre and imply a different shot direction during turn lag.
    if sample.parts.reticle.visible and math.abs(root[11])>.1 then
        local lens=T.point(root,vector(model.reticle))
        local z=(root[3]*lens.x+root[7]*lens.y+root[11]*lens.z)/root[11]
        local local_dot=T.point(T.inverse(root),{x=0,y=0,z=z})
        sample.parts.reticle.position={local_dot.x-model.reticle[1],local_dot.y-model.reticle[2],local_dot.z-model.reticle[3]}
    else sample.parts.reticle.visible=false end
    if d.id=="pistol" then
        sample.parts.reticle.position[3]=sample.parts.reticle.position[3]+sample.parts.bolt.position[3]
        sample.parts.reticle.visible=sample.parts.reticle.visible and bolt<.05
    end
    sample.arms.left,sample.joints.left=arms.palette(root,clip.left,-1,0)
    sample.arms.right,sample.joints.right=arms.palette(root,{position=model.right,finger=model.right_finger,
        back=model.right_back,pose="grip"},1,motion("trigger"))
    return sample
end
function M.capture(model,ads,equipped)
    equipped=equipped or "rifle"
    local recoil,previous={},{}
    for _,name in ipairs({"pitch","roll","up","back"}) do recoil[name]={x=0};previous[name]=0 end
    return M.pose({time={alpha=0,elapsed=0},player={motion={velocity={x=0,z=0},grounded=true}},
        weapons={equipped=equipped,ads=ads and 1 or 0,previous_ads=ads and 1 or 0,
            recoil=recoil,previous_recoil=previous,inventory={[equipped]={chambered=true,mode=1}},since_shot=1,flash=0}},model)
end
return M
