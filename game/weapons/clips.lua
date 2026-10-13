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
function M.sample(name,t)
    local out={pos={0,0,0},rot={0,0,0},mag=0,mag_visible=true,bolt=0,hand=0,charge=0}
    local track=tracks[name]
    if not track then return out end
    t=V.clamp(t,0,1)
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
