-- Presentation-only effects. Reserved pools prevent ambience or fragment storms
-- from evicting every combat puff. Random streams never touch the simulation.
local V=require "game.weapons.math"
local rng=require "game.rng"
local M={particle_limit=128,fragment_limit=48,ambient_limit=32,decal_limit=48,haze_limit=12,emitter_limit=8,step=1/60}
M.kind={smoke=0,flash=1,mark=2,spark=3,chip=4,splinter=5,glass=6,blood=7,fire=8,ring=9,mote=10,splash=11,leaf=12,fibre=13,scorch=14,stain=15,haze=16}
local K=M.kind
local UP={x=0,y=1,z=0}
local function pool(n) local p={};for i=1,n do p[i]={life=0} end;return p end
function M.new(seed)
    seed=seed or 1337
    return {particles=pool(M.particle_limit),ambient=pool(M.ambient_limit),decals=pool(M.decal_limit),haze=pool(M.haze_limit),
        emitters={},random=rng.new(seed,"combat/effects"),ambient_random=rng.new(seed,"ambient/effects"),
        density=1,decal_count=M.decal_limit,heat_enabled=true,
        serial=0,emitted=0,impacts=0,shots=0,explosions=0,steps=0,deaths=0,recycled=0,collisions=0,rays=0,
        time=0,remainder=0,mote_acc=0,heat_acc=0,by_kind={},peak=0}
end
function M.configure(s,options)
    s.density=options.effect_density or 1
    s.decal_count=options.impact_decals==false and 1 or options.decal_limit or M.decal_limit
    s.heat_enabled=options.heat_distortion~=false
    s.decals_enabled=options.impact_decals~=false
    for name,items in pairs({particles=s.particles,ambient=s.ambient,decals=s.decals,haze=s.haze}) do
        for i,e in ipairs(items) do
            local keep
            if name=="particles" then
                local base=M.particle_limit-M.fragment_limit
                keep=i<=math.ceil(base*s.density) or i>base and i<=base+math.ceil(M.fragment_limit*s.density)
            else keep=i<=math.ceil(#items*s.density) end
            if name=="decals" then keep=s.decals_enabled and i<=s.decal_count end
            if name=="haze" and not s.heat_enabled then keep=false end
            if not keep then e.life=0 end
        end
    end
end
local function spawn(s,items,kind,p,n,size,life,colour,fragment)
    s.serial=s.serial+1
    local first,last=1,math.max(1,math.ceil(#items*s.density))
    if items==s.decals then last=s.decal_count end
    if items==s.particles then
        if fragment then
            first=M.particle_limit-M.fragment_limit+1;last=first+math.ceil(M.fragment_limit*s.density)-1
        else last=math.ceil((M.particle_limit-M.fragment_limit)*s.density) end
    end
    local slot=first
    for i=first,last do
        if items[i].life<=0 then slot=i;break end
        if items[i].serial<items[slot].serial then slot=i end
    end
    if items[slot].life>0 then s.recycled=s.recycled+1 end
    local random=items==s.ambient and s.ambient_random or s.random
    local e={kind=kind,position=V.copy(p),normal=V.copy(n or UP),size=size,life=life,duration=life,
        colour=colour,serial=s.serial,seed=random(),velocity={x=0,y=0,z=0},gravity=0,drag=0,spin=0,
        opacity=1,growth=0,fragment=fragment,bounces=0}
    items[slot]=e;s.emitted=s.emitted+1;s.by_kind[kind]=(s.by_kind[kind] or 0)+1
    return e
end
local function puff(s,p,n,size,life,colour,items)
    local e=spawn(s,items or s.particles,K.smoke,p,n,size,life,colour)
    e.velocity=V.point({x=0,y=.18,z=0},n,.45);e.drag=.8;e.growth=2.5;e.opacity=.52;e.spin=(e.seed-.5)*.6
    return e
end
local function cone(random,n,speed)
    local v={x=random()*2-1,y=random()*2-1,z=random()*2-1}
    local d=v.x*n.x+v.y*n.y+v.z*n.z
    v=V.point(v,n,math.abs(d)-d+.65)
    return V.point({x=0,y=0,z=0},V.normalize(v),speed)
end
local function fleck(s,kind,p,n,size,life,colour,speed)
    local e=spawn(s,s.particles,kind,p,n,size,life,colour,true)
    e.velocity=cone(s.random,n,speed);e.gravity=-14;e.drag=1.5;e.spin=(e.seed-.5)*24
    e.bounces=kind==K.spark and 2 or 1
    return e
end
local no_marks={flesh=true,glass=true,water=true,fabric=true,foliage=true}
local function decal(s,kind,p,n,size,life,colour,surface)
    if s.decals_enabled==false or no_marks[surface] then return end
    local e=spawn(s,s.decals,kind,V.point(p,n,.003),n,size,life,colour)
    e.decal=true;return e
end
local function ray(s,query,p,d,length)
    if not query then return end
    s.rays=s.rays+1
    local h=query:ray(p,d.x*length,d.y*length,d.z*length)
    if h then return {x=h.x,y=h.y,z=h.z},{x=h.nx,y=h.ny,z=h.nz},h.surface end
end
local recipes={
    concrete={K.chip,5,{.56,.52,.44},.045,7},plaster={K.chip,4,{.76,.70,.58},.04,5},
    metal={K.spark,8,{1,.65,.22},.026,11},wood={K.splinter,6,{.46,.29,.13},.085,7},
    glass={K.glass,7,{.63,.86,.90},.065,8},flesh={K.blood,6,{.38,.025,.018},.09,4},
    dirt={K.chip,4,{.28,.21,.13},.055,4},sand={K.chip,4,{.64,.49,.30},.04,4},
    rubber={K.chip,4,{.08,.075,.07},.045,5},water={K.splash,6,{.62,.77,.80},.08,4},
    foliage={K.leaf,4,{.22,.31,.10},.08,3},fabric={K.fibre,4,{.52,.43,.31},.07,3},
}
function M.impact(s,hit,query)
    s.impacts=s.impacts+1
    local surface=hit.surface or "concrete"
    local n=hit.normal or UP;local p=V.point(hit.point,n,.015)
    local r=recipes[surface] or recipes.concrete
    if surface~="glass" and surface~="water" then
        local e=puff(s,p,n,surface=="flesh" and .18 or .22,.75,r[3])
        if surface=="flesh" then e.kind=K.blood;e.growth=2;e.opacity=.3 end
    end
    for _=1,math.ceil(r[2]*(hit.exit and .6 or 1)*s.density) do
        local e=fleck(s,r[1],p,n,r[4]*(.65+s.random()*.65),.4+s.random()*.9,r[3],r[5]*(.55+s.random()*.65))
        if surface=="foliage" or surface=="fabric" then e.gravity=-2;e.drag=3 end
    end
    if not hit.dynamic then
        local mark=decal(s,K.mark,hit.point,n,hit.exit and .18 or .12,24,
            surface=="metal" and {.16,.14,.12} or {.16,.12,.08},surface)
        if mark then mark.variant=surface=="wood" and 1 or surface=="metal" and 2 or 0 end
    end
    if surface=="flesh" and hit.incident and not hit.exit then
        local point,normal,receiver=ray(s,query,V.point(hit.point,hit.incident,.03),hit.incident,2.6)
        if point then decal(s,K.stain,point,normal,.35+s.random()*.25,35,{.27,.018,.012},receiver) end
    end
end
function M.fire(s,p,d,world_flash)
    s.shots=s.shots+1;puff(s,p,d,.10,.55,{.36,.37,.38})
    if world_flash then spawn(s,s.particles,K.flash,p,d,.22,.055,{1,.55,.12}) end
end
function M.haze(s,p,size,life,strength,ring)
    if not s.heat_enabled then return end
    local e=spawn(s,s.haze,ring and K.ring or K.haze,p,UP,size,life,{1,1,1})
    e.opacity=strength;e.growth=ring and 7 or 1.6
    return e
end
function M.column(s,p,persistent)
    local list=s.emitters
    if #list>=M.emitter_limit then
        local index
        for i,e in ipairs(list) do if not e.persistent then index=i;break end end
        if not index then return end
        table.remove(list,index)
    end
    list[#list+1]={position=V.copy(p),life=persistent and math.huge or 1.5,persistent=persistent,acc=0}
end
function M.explosion(s,blast,query)
    s.explosions=s.explosions+1
    local p=blast.position
    spawn(s,s.particles,K.flash,p,UP,2.6,.085,{1,.6,.15})
    for i=1,math.ceil(7*s.density) do
        local e=spawn(s,s.particles,K.fire,V.point(p,UP,.12),UP,.7+s.random()*.5,.3+s.random()*.32,{1,.4,.05})
        e.velocity=cone(s.random,UP,1.5+s.random()*3);e.gravity=1.2;e.drag=3;e.growth=2.4
    end
    for i=1,math.ceil(8*s.density) do
        local angle=i*math.pi/4;local d={x=math.cos(angle),y=.2,z=math.sin(angle)}
        local e=puff(s,V.point(p,d,.25),UP,.55,1.8+s.random(),{.22,.20,.17})
        e.velocity=V.point({x=0,y=.5,z=0},d,2.5);e.drag=1.8;e.growth=3.5
    end
    for i=1,math.ceil(14*s.density) do fleck(s,i%3==0 and K.spark or K.chip,V.point(p,UP,.08),UP,.03+s.random()*.035,.7+s.random(),{.4,.31,.20},5+s.random()*8) end
    local ring=spawn(s,s.particles,K.ring,p,UP,1.4,.26,{1,.72,.4});ring.growth=7;ring.opacity=.08
    M.haze(s,p,1.6,.4,1.4,true);M.haze(s,V.point(p,UP,.4),2.1,1.4,.35)
    M.column(s,V.point(p,UP,.2),false)
    local point,n,surface=ray(s,query,V.point(p,UP,.15),{x=0,y=-1,z=0},2.5)
    if point then decal(s,K.scorch,point,n,3.2,45,{.075,.065,.05},surface) end
end
function M.footstep(s,step,query,landing)
    if not step.position then return end
    local surface=step.surface or "concrete"
    if surface=="metal" or surface=="glass" or surface=="water" then return end
    local p,n=ray(s,query,V.point(step.position,UP,.2),{x=0,y=-1,z=0},.6)
    if not p then return end
    local strength=landing and math.min(2,(step.velocity or 3)/5) or step.running and .8 or .4
    if strength<=.05 then return end
    s.steps=s.steps+1
    local colour=recipes[surface] and recipes[surface][3] or recipes.concrete[3]
    for i=1,landing and 4 or 1 do
        local e=puff(s,V.point(p,n,.025),n,.16*strength,.7,colour)
        e.velocity={x=math.cos(i*2.4)*strength,y=.12,z=math.sin(i*2.4)*strength};e.opacity=.24*strength
    end
end
function M.death(s,position,query)
    s.deaths=s.deaths+1
    M.footstep(s,{position=position,surface="dirt",velocity=5},query,true)
end
function M.ambient_sources(s,layout)
    for _,p in ipairs((layout.dressing or {}).wrecks or {}) do
        local base=math.abs(p[1])>=layout.street.half_width and layout.street.walk_height or 0
        M.column(s,{x=p[1],y=base+1.05,z=p[2]+1.3},true)
    end
end
local function ambience(s,dt,env,query)
    if not env then return end
    local random=s.ambient_random
    s.mote_acc=s.mote_acc+dt*4*s.density
    while s.mote_acc>=1 do
        s.mote_acc=s.mote_acc-1
        local p=env.position
        local e=spawn(s,s.ambient,K.mote,{x=p.x+(random()-.5)*14,y=p.y+(random()-.35)*5,z=p.z+(random()-.5)*14},UP,.012+random()*.012,6+random()*2,{.8,.75,.64})
        e.velocity={x=.06,y=.025,z=.025};e.opacity=.25*(env.sun or 1)
    end
    s.heat_acc=s.heat_acc+dt
    if s.heat_enabled and s.heat_acc>=.55 then
        s.heat_acc=0
        if (env.sun or 1)>.35 then
            local d=env.forward or {x=0,y=0,z=-1}
            local p=V.point(env.position,d,4+random()*8);p.x=p.x+(random()-.5)*4
            local ground,n=ray(s,query,p,{x=0,y=-1,z=0},5)
            if ground and n.y>.7 then M.haze(s,V.point(ground,UP,.35),1.5,1.7,.12*(env.sun or 1)) end
        end
    end
end
local function tick(s,dt,query,env)
    s.time=s.time+dt
    local active=0
    for _,items in ipairs({s.particles,s.ambient,s.decals,s.haze}) do for _,e in ipairs(items) do
        if e.life>0 then
            e.life=math.max(0,e.life-dt)
            if not e.decal and e.life>0 then
                local v=e.velocity;local drag=math.exp(-e.drag*dt)
                v.x,v.y,v.z=v.x*drag,(v.y+e.gravity*dt)*drag,v.z*drag
                local next_position=V.point(e.position,v,dt)
                local hit,n
                if e.fragment and query and V.length(v)>.05 then
                    hit,n=ray(s,query,e.position,v,dt)
                end
                if hit then
                    s.collisions=s.collisions+1;e.position=V.point(hit,n,.012)
                    if e.bounces>0 then
                        local dot=v.x*n.x+v.y*n.y+v.z*n.z
                        e.velocity=V.point(v,n,-1.45*dot);e.velocity=V.point({x=0,y=0,z=0},e.velocity,.6)
                        e.bounces=e.bounces-1
                    else e.life=0 end
                else e.position=next_position end
            end
            if e.life>0 then active=active+1 end
        end
    end end
    s.peak=math.max(s.peak,active)
    for i=#s.emitters,1,-1 do
        local e=s.emitters[i];e.life=e.life-dt
        if e.life<=0 then table.remove(s.emitters,i)
        else
            e.acc=e.acc+dt*(e.persistent and 2 or 8)*s.density
            while e.acc>=1 do
                e.acc=e.acc-1
                if not e.persistent or env and V.length({x=e.position.x-env.position.x,y=0,z=e.position.z-env.position.z})<55 then
                    local p=puff(s,e.position,UP,e.persistent and .5 or .8,3.4,{.18,.175,.16},e.persistent and s.ambient or nil)
                    p.velocity={x=.18,y=1.1,z=.08};p.growth=3.4;p.opacity=.5
                    if not e.persistent or s.ambient_random()<.25 then M.haze(s,V.point(e.position,UP,.3),1,1.6,.18) end
                end
            end
        end
    end
    ambience(s,dt,env,query)
end
function M.update(s,dt,query,env)
    if dt<=0 then return end
    s.remainder=s.remainder+dt
    -- Bound catch-up without a burst of stale emitters after backgrounding.
    local steps=math.min(8,math.floor((s.remainder+1e-9)/M.step))
    s.remainder=math.max(0,s.remainder-steps*M.step)
    if steps==8 then s.remainder=math.min(s.remainder,M.step) end
    for _=1,steps do tick(s,M.step,query,env) end
end
function M.appearance(e)
    local age=1-e.life/e.duration
    if e.decal then return e.size,math.min(1,e.life/2)*e.opacity end
    if e.kind==K.flash then return e.size*(.75+age*.4),1-age end
    if e.kind==K.spark then return e.size*(1-age*.6),(1-age)^.5 end
    if e.kind==K.fire or e.kind==K.ring then return e.size*(1+math.sqrt(age)*e.growth),(1-age)*e.opacity end
    if e.fragment then return e.size,math.min(1,e.life/.25)*e.opacity end
    return e.size*(1+age*e.growth),math.min(1,age*12+.15)*(1-age)^2*e.opacity
end
function M.snapshot(s)
    local out={effect_density=s.density,active_decal_limit=s.decal_count,particle_limit=M.particle_limit,ambient_limit=M.ambient_limit,decal_limit=M.decal_limit,haze_limit=M.haze_limit,
        emitter_limit=M.emitter_limit,emitters=#s.emitters,emitted=s.emitted,impacts=s.impacts,shots=s.shots,explosions=s.explosions,
        steps=s.steps,deaths=s.deaths,recycled=s.recycled,collisions=s.collisions,rays=s.rays,peak=s.peak,time=s.time,by_kind=s.by_kind}
    for _,name in ipairs({"particles","ambient","decals","haze"}) do
        local count=0;for _,e in ipairs(s[name]) do if e.life>0 then count=count+1 end end;out[name]=count
    end
    return out
end
return M
