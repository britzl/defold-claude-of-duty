-- Source: src/ai/soldier.js VARIANTS; common 1.8 m anatomy and carry rig.
local V=require "game.weapons.math"
local M={order={"vanguard","irregular","breacher"}}
M.vanguard={id="vanguard",scale=1,bulk=1,weapon="carbine",helmet=true,helmet_cover=true,
    goggles=true,goggles_down=true,face_wrap=true,knee_pads=true,carrier=true,
    cloth={.48,.43,.29,6},gear={.34,.29,.20,3},skin={.54,.34,.22,4},shell={.35,.34,.29,6}}
M.irregular={id="irregular",scale=.985,bulk=.94,weapon="ak",head_wrap=true,shades=true,
    face_wrap=true,beard=true,cloth={.30,.35,.23,6},gear={.27,.29,.19,3},
    skin={.46,.29,.18,4},shell={.28,.31,.22,3}}
M.breacher={id="breacher",scale=1.025,bulk=1.06,weapon="carbine",helmet=true,
    goggles=true,face_wrap=true,hard_mask=true,beard=true,knee_pads=true,carrier=true,
    cloth={.39,.41,.43,6},gear={.25,.27,.29,3},skin={.57,.35,.23,4},shell={.35,.37,.40,2}}
function M.get(name) return M[name or "vanguard"] or M.vanguard end
M.bore=V.normalize({x=-.115,y=-.10,z=-1})
function M.along(t,drop)
    local p=V.point({x=.148,y=1.398,z=.078},M.bore,t)
    p.y=p.y-(drop or 0);return p
end
function M.muzzle(name) return M.along(M.get(name).weapon=="ak" and .865 or .80) end
function M.support(name) return M.along(M.get(name).weapon=="ak" and .47 or .45,.05) end
M.magazine=M.along(.32,.16)
return M
