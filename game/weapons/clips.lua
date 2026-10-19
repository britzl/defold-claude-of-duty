-- Normalized source reload/inspection beats. Ammunition and presentation
-- share this clock. Final keys are normalized (the JS source mixes units).
local V = require "game.weapons.math"
local M = {}
local tracks={
    reloadTac={
        {0,0,0,0,0,0,0},{.12,.014,-.026,.030,-.14,.30,.42},
        {.50,.016,-.030,.026,-.10,.34,.50},{.72,.012,-.022,.022,-.12,.26,.44},
        {.81,.008,-.008,.014,-.05,.18,.30},{1,0,0,0,0,0,0}},
    reloadEmpty={
        {0,0,0,0,0,0,0},{.10,.016,-.030,.032,-.16,.34,.46},
        {.44,.018,-.034,.028,-.12,.38,.54},{.70,.014,-.026,.024,-.14,.30,.48},
        {.86,.006,-.012,.016,-.02,.42,.22},{.92,.004,-.006,.022,.02,.44,.18},{1,0,0,0,0,0,0}},
    inspect={
        {0,0,0,0,0,0,0},{.16,-.03,-.012,.075,.10,-.62,-.34},
        {.34,-.026,-.006,.085,-.05,-.78,-.50},{.52,.01,-.02,.07,.22,.50,.90},
        {.70,.012,-.024,.055,.30,.62,1.15},{.86,-.006,-.01,.03,.06,-.18,.20},{1,0,0,0,0,0,0}},
    draw={{0,.05,-.30,.14,-.85,.50,.55},{.55,.01,-.03,.02,-.10,.06,.06},
        {.78,-.004,.008,-.006,.04,-.02,-.02},{1,0,0,0,0,0,0}},
    holster={{0,0,0,0,0,0,0},{.25,.004,.014,-.01,.08,-.04,-.05},{1,.05,-.32,.15,-.90,.55,.60}},
}
M.beats={
    reloadTac={{.02,"start"},{.20,"magout"},{.34,"magdrop"},{.81,"magin"},{.88,"slap"},{.995,"end"}},
    reloadEmpty={{.02,"start"},{.16,"magout"},{.30,"magdrop"},{.71,"magin"},{.90,"charge"},{.917,"boltrelease"},{.995,"end"}},
}
function M.duration(name,def)
    return def[name] or (name=="inspect" and def.inspectTime) or (name=="draw" and def.drawTime)
        or (name=="holster" and def.holsterTime) or 0
end
local function hand_keys(name,model,def)
    local grip=model.left
    local at={model.magazine[1]+.012,model.magazine[2],model.magazine[3]+.012}
    local low={at[1]+.038,at[2]-def.magLen*.88,at[3]+.078}
    local off={at[1]+.098,at[2]-def.magLen*1.10,at[3]+.148}
    local high={at[1]-.006,at[2]-def.magLen*.16,at[3]-.004}
    local wrap={model.left_finger,model.left_back,model.grip}
    local pinch={{.1,.72,-.68},{-.86,.34,-.38},"pinch"}
    local open={pinch[1],pinch[2],"open"}
    local function key(t,p,pose) return {t,p,pose[1],pose[2],pose[3]} end
    if name=="reloadTac" or name=="reloadEmpty" then
        local empty=name=="reloadEmpty"
        local keys={key(0,grip,wrap),key(empty and .08 or .10,at,pinch),key(empty and .16 or .20,at,pinch),
            key(empty and .26 or .30,low,pinch),key(empty and .36 or .42,off,open),
            key(empty and .48 or .56,off,pinch),key(empty and .58 or .68,low,pinch),
            key(empty and .66 or .76,high,pinch),key(empty and .71 or .81,at,pinch)}
        if empty then
            keys[#keys+1]=key(.75,at,open)
            local charge={model.charge[1],model.charge[2],model.charge[3]}
            local pulled={charge[1],charge[2],charge[3]+(def.id=="pistol" and .035 or .065)}
            local hold={{.55,.2,.81},{-.2,.94,-.27},"pinch"}
            keys[#keys+1]=key(.86,charge,hold);keys[#keys+1]=key(.90,pulled,hold)
            keys[#keys+1]=key(.917,charge,hold)
        else keys[#keys+1]=key(.88,at,open) end
        keys[#keys+1]=key(1,grip,wrap)
        return keys,at
    elseif name=="inspect" then
        return {key(0,grip,wrap),key(.30,{grip[1]-.01,grip[2]-.01,grip[3]+.03},wrap),
            key(.55,{grip[1]+.01,grip[2]-.02,grip[3]-.02},wrap),key(1,grip,wrap)}
    elseif name=="draw" or name=="holster" then
        local released={grip[1]-.02,grip[2]-.09,grip[3]+.06}
        local loose={wrap[1],wrap[2],"open"}
        return name=="draw" and {key(0,released,loose),key(.6,grip,wrap),key(1,grip,wrap)}
            or {key(0,grip,wrap),key(1,released,loose)}
    end
    return {key(0,grip,wrap),key(1,grip,wrap)}
end
function M.sample(name,t,model,def)
    local out={pos={0,0,0},rot={0,0,0},mag=0,mag_visible=true,bolt=0,hand=0,charge=0}
    local track=tracks[name]
    t=V.clamp(t,0,1)
    if model then
        -- Cache immutable reference tracks with the generated model.
        model.clips=model.clips or {}
        local key=name or "idle"
        if not model.clips[key] then
            local keys,at=hand_keys(name,model,def);model.clips[key]={keys=keys,at=at}
        end
        local data=model.clips[key];local keys=data.keys
        local a,b=keys[1],keys[#keys]
        for i=1,#keys-1 do if t<=keys[i+1][1] then a,b=keys[i],keys[i+1];break end end
        local f=V.smooth((t-a[1])/(b[1]-a[1]))
        local hand={position={},finger={},back={},pose=a[5],next_pose=b[5],blend=f}
        for j,field in ipairs({"position","finger","back"}) do
            for i=1,3 do hand[field][i]=V.lerp(a[j+1][i],b[j+1][i],f) end
        end
        out.left=hand
        out.mag_position={0,0,0}
        if data.at then
            local empty=name=="reloadEmpty"
            local pull,seat=empty and .16 or .20,empty and .71 or .81
            if t>=pull and t<=seat then
                for i=1,3 do out.mag_position[i]=hand.position[i]-data.at[i] end
            end
        end
    end
    if not track then return out end
    local a,b=track[1],track[#track]
    for i=1,#track-1 do if t<=track[i+1][1] then a,b=track[i],track[i+1];break end end
    local w=V.smooth((t-a[1])/(b[1]-a[1]))
    for i=1,3 do out.pos[i]=V.lerp(a[i+1],b[i+1],w);out.rot[i]=V.lerp(a[i+4],b[i+4],w) end
    if name=="reloadTac" or name=="reloadEmpty" then
        local empty=name=="reloadEmpty"
        local pull,drop,show,seat=empty and .16 or .20,empty and .30 or .34,empty and .58 or .68,empty and .71 or .81
        out.mag=V.smooth((t-(pull-.04))/.04)*(1-V.smooth((t-(seat-.02))/.02))
        out.mag_visible=t<drop or t>=show
        out.hand=V.smooth(t/.10)*(1-V.smooth((t-.93)/.07))
        out.bolt=empty and (1-V.smooth((t-.90)/.017)) or 0
        out.charge=empty and V.smooth((t-.86)/.04)*(1-V.smooth((t-.90)/.017)) or 0
    end
    return out
end
return M
