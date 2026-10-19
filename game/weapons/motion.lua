-- Fixed-tick presentation state. Rendering only reads/interpolates this layer.
local V=require "game.weapons.math"
local T=require "game.player.tuning"
local M={}
local axes={"x","y","z","pitch","yaw","roll"}
local function values()
    return {x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sprint=0,low=0,trigger=0}
end
function M.new()
    local s={previous=values(),current=values(),phase=0,time=0,weight=0,av_yaw=0,av_pitch=0,lag={}}
    for _,key in ipairs(axes) do s.lag[key]=V.spring() end
    return s
end
local function damp(a,b,rate,dt) return a+(b-a)*(1-math.exp(-rate*dt)) end
local function wrap(a) return (a+math.pi)%(2*math.pi)-math.pi end
local function spring(s,target,dt,freq,damping)
    s.x=s.x-target;V.step(s,dt,freq,damping);s.x=s.x+target;return s.x
end
function M.update(ctx,dt,def)
    local s=ctx.weapons.motion;local m=ctx.player.motion;local w=ctx.weapons
    local out=s.current
    for k,v in pairs(out) do s.previous[k]=v end
    if not ctx.world.ready or not ctx.player.enabled or not ctx.player.actor.alive then
        s.has_previous=false
        return
    end
    local yaw=m.yaw+ctx.player.camera.current.yaw
    local pitch=m.pitch+ctx.player.camera.current.pitch
    local dy,dp=0,0
    if s.has_previous then dy=wrap(yaw-s.yaw)/dt;dp=wrap(pitch-s.pitch)/dt end
    s.yaw,s.pitch,s.has_previous=yaw,pitch,true
    s.av_yaw=damp(s.av_yaw,V.clamp(dy,-9,9),18,dt)
    s.av_pitch=damp(s.av_pitch,V.clamp(dp,-9,9),18,dt)
    s.time=s.time+dt
    out.sprint=damp(out.sprint,m.sprinting and not w.clip and 1 or 0,9,dt)
    out.low=damp(out.low,m.mantle and 1 or 0,8,dt)
    out.trigger=damp(out.trigger,w.intent.fire and not w.clip and not m.sprinting and not m.mantle and 1 or 0,26,dt)
    local moving=m.grounded and not m.sliding and not m.mantle and not m.mantle_completed
    -- Distance actually travelled, shared with player footsteps. Pushing into
    -- cover, airborne movement and rooted traversals cannot advance the stride.
    local travel=moving and (m.travel or 0) or 0
    s.phase=s.phase+travel/T.stances[m.stance or "stand"].stride*math.pi
    local speed=travel/dt
    s.weight=damp(s.weight,math.min(1,speed/4.2),12,dt)
    local ads=V.smooth(w.ads)
    local sway=def.swayScale*V.lerp(1,.22,ads)*V.lerp(1,1.5,out.sprint)
    local bob=def.bobScale*s.weight*V.lerp(1,.28,ads)*(m.stance=="prone" and .35 or 1)
    local t,bp=s.time,s.phase
    local nx=math.sin(t*.817)*.55+math.sin(t*1.613)*.30+math.sin(t*2.371)*.15
    local ny=math.sin(t*1.193)*.55+math.sin(t*2.507)*.30+math.sin(t*.523)*.15
    local nz=math.sin(t*1.703)*.6+math.sin(t*.719)*.4
    local breath=math.sin(t*1.38)*.5+math.sin(t*.61)*.25
    local lagscale=V.lerp(1,.42,ads)
    local targets={x=V.clamp(-s.av_yaw*.019,-.05,.05),y=V.clamp(s.av_pitch*.014,-.04,.04),
        z=V.clamp(-math.abs(s.av_yaw)*.006,-.03,.03),pitch=V.clamp(-s.av_pitch*.075,-.24,.24),
        yaw=V.clamp(s.av_yaw*.085,-.3,.3),roll=V.clamp(-s.av_yaw*.055,-.2,.2)}
    for i,key in ipairs(axes) do
        out[key]=spring(s.lag[key],targets[key]*lagscale,dt,i<=3 and 5.4 or 6.2,i<=3 and .46 or .42)
    end
    out.x=out.x+nx*.0075*sway+math.sin(bp)*.0165*bob
    out.y=out.y+(ny*.006+breath*.0022)*sway+(math.abs(math.cos(bp))-.6)*.0125*bob
    out.z=out.z+nz*.004*sway+math.sin(bp*2)*.0055*bob
    out.pitch=out.pitch+(ny*.021+breath*.006)*sway+math.cos(bp*2)*.014*bob
    out.yaw=out.yaw+nx*.028*sway+math.sin(bp+.6)*.019*bob
    out.roll=out.roll+nz*.017*sway+math.sin(bp)*.031*bob
    -- Landing/footfall springs already have authoritative event timing.
    out.y=out.y+ctx.player.camera.dip.x*.35+ctx.player.camera.step.x*.4
end
return M
