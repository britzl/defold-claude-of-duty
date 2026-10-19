-- Fixed-tick magazines and source-derived cyclic rates; RNG is per actor.
local animation=require "game.ai.animation"
local events=require "game.events"
local V=require "game.weapons.math"
local M={}
M.profiles={
    vanguard={id="enemy_carbine",rate=10.5,magazine=30,reload=2.35,spread=.032,damage=10},
    irregular={id="enemy_ak",rate=8.2,magazine=30,reload=2.9,spread=.040,damage=12},
    breacher={id="enemy_carbine",rate=10.5,magazine=30,reload=2.35,spread=.028,damage=10},
}
function M.profile(e) return M.profiles[e.variant] or M.profiles.vanguard end
function M.init(e)
    e.ammo=M.profile(e).magazine;e.burst_left=0;e.burst_cooldown=.4+(e.index%3)*.3
    e.reload_left=0;e.reloads=0;e.reload_beats=0;e.suppressive_shots=0
end
local function emit(ctx,e,phase,position)
    events.emit(ctx.events,events.WEAPON_RELOAD,{source=e.id,weapon=M.profile(e).id,phase=phase,position=V.copy(position or e.position)})
end
function M.cancel(ctx,e)
    if e.reload_left>0 then emit(ctx,e,"cancel") end
    e.reload_left=0;e.burst_left=0;e.animation.reload_time=-1
end
function M.tick(ctx,e,dt,position)
    e.burst_cooldown=math.max(0,e.burst_cooldown-dt)
    if e.reload_left>0 then
        if e.animation.vault_time>=0 then M.cancel(ctx,e);return end
        local p=M.profile(e);local previous=e.reload_left
        e.reload_left=math.max(0,e.reload_left-dt)
        for _,beat in ipairs({{.72,"magdrop"},{.28,"magin"},{.1,"bolt"}}) do
            if previous>p.reload*beat[1] and e.reload_left<=p.reload*beat[1] then
                emit(ctx,e,beat[2],position);e.reload_beats=e.reload_beats+1
            end
        end
        if e.reload_left==0 then
            e.ammo=p.magazine;e.reloads=e.reloads+1;e.burst_cooldown=.3;emit(ctx,e,"end",position)
        end
    elseif e.ammo==0 and animation.reload(e,M.profile(e).reload) then
        e.reload_left=M.profile(e).reload;e.burst_left=0;emit(ctx,e,"start",position)
    end
end
function M.ready(e)
    return e.ammo>0 and e.reload_left==0 and e.cooldown<=0 and (e.burst_left>0 or e.burst_cooldown==0)
end
function M.consume(e,suppressive)
    local p=M.profile(e)
    if e.burst_left==0 then e.burst_left=3+math.floor(e.random()*5) end
    e.burst_left=e.burst_left-1;e.ammo=e.ammo-1;e.cooldown=1/p.rate
    if e.burst_left==0 then e.burst_cooldown=.45+e.random()*.9+e.suppression*.5 end
    if suppressive then e.suppressive_shots=e.suppressive_shots+1 end
end
function M.direction(e,origin,target,suppressive)
    local forward=V.normalize({x=target.x-origin.x,y=target.y-origin.y,z=target.z-origin.z})
    local right=V.normalize({x=-forward.z,y=0,z=forward.x})
    local up={x=-forward.y*right.z,y=forward.z*right.x-forward.x*right.z,z=forward.y*right.x}
    local spread=M.profile(e).spread*(1+e.suppression*1.5)*(suppressive and 1.8 or 1)
    local azimuth=e.random()*2*math.pi;local radius=math.sqrt(e.random())*spread
    return V.normalize(V.point(V.point(forward,right,math.cos(azimuth)*radius),up,math.sin(azimuth)*radius*.8))
end
function M.round(e)
    local p=M.profile(e)
    return {id=p.id,muzzleVelocity=e.variant=="irregular" and 430 or 500,damage=p.damage,
        penetration=e.variant=="irregular" and .55 or .45,dropoff=.6,maxRange=60,dragK=.01}
end
return M
