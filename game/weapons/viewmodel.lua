local V = require "game.weapons.math"
local clips = require "game.weapons.clips"
local defs = require "game.weapons.defs"
local M = {}
function M.pose(ctx,model)
    local w=ctx.weapons
    local d=defs[w.equipped]
    local alpha=ctx.time.alpha
    local ads=V.smooth(V.lerp(w.previous_ads,w.ads,alpha))
    local recoil={}
    for k,s in pairs(w.recoil) do recoil[k]=V.lerp(w.previous_recoil[k],s.x,alpha) end
    local clip=clips.sample(w.clip,w.clip and w.clip_time/w.clip_duration or 0)
    local p,r={},{}
    local motion=ctx.player.motion
    for i=1,3 do
        local aimed=-model.sight[i]
        if i==3 then aimed=aimed-d.eyeRelief end
        p[i]=V.lerp(d.hipPos[i],aimed,ads)+clip.pos[i]
        r[i]=V.lerp(d.hipRot[i],d.adsCant[i],ads)+clip.rot[i]
        if motion.sprinting or motion.mantle then
            p[i]=p[i]+(motion.mantle and d.lowReadyPos[i] or d.sprintPos[i])-d.hipPos[i]
            r[i]=r[i]+(motion.mantle and d.lowReadyRot[i] or d.sprintRot[i])-d.hipRot[i]
        end
    end
    local speed=math.sqrt(motion.velocity.x^2+motion.velocity.z^2)
    local bob=math.min(1,speed/4)*(1-ads*.9)*(motion.grounded and 1 or 0)
    p[1]=p[1]+math.sin(ctx.time.elapsed*10)*.004*bob
    p[2]=p[2]+math.cos(ctx.time.elapsed*20)*.003*bob+recoil.up
    p[3]=p[3]+recoil.back
    r[1]=r[1]+recoil.pitch*.8
    r[3]=r[3]+recoil.roll
    local sample={position=p,rotation=r,parts={},ads=ads,world_fov=math.rad(70)*V.lerp(1,d.adsFov,ads),
        view_fov=math.rad(60)*V.lerp(1,d.viewFov,ads)}
    for _,name in ipairs({"body","magazine","bolt","charge","left_hand","right_hand","reticle","flash"}) do
        sample.parts[name]={position={0,0,0},visible=true}
    end
    sample.parts.magazine.position={0,-clip.mag*d.magLen*1.7,clip.mag*.065}
    sample.parts.magazine.visible=clip.mag_visible
    local s=w.inventory[w.equipped]
    local cycle=math.max(0,1-w.since_shot/.085)
    local bolt=math.max(cycle,clip.bolt,not s.chambered and 1 or 0)
    sample.parts.bolt.position[3]=bolt*(d.id=="pistol" and .035 or .055)
    sample.parts.charge.position[3]=clip.charge*.065
    for i=1,3 do
        local hand=model.magazine[i]+(i==2 and -clip.mag*d.magLen*1.7 or i==3 and clip.mag*.065 or 0)
        sample.parts.left_hand.position[i]=V.lerp(model.left[i],hand,clip.hand)
        sample.parts.right_hand.position[i]=model.right[i]
        sample.parts.flash.position[i]=model.muzzle[i]
    end
    sample.parts.flash.position[3]=sample.parts.flash.position[3]-.035
    sample.parts.flash.visible=w.flash>0
    sample.parts.reticle.visible=ads>.8 and not w.clip
    return sample
end
function M.capture(model,ads)
    local recoil,previous={},{}
    for _,name in ipairs({"pitch","roll","up","back"}) do recoil[name]={x=0};previous[name]=0 end
    return M.pose({time={alpha=0,elapsed=0},player={motion={velocity={x=0,z=0},grounded=true}},
        weapons={equipped="rifle",ads=ads and 1 or 0,previous_ads=ads and 1 or 0,
            recoil=recoil,previous_recoil=previous,inventory={rifle={chambered=true}},since_shot=1,flash=0}},model)
end
return M
