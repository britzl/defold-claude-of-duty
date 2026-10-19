-- Shared procedural arms. Seventeen rigid joints per arm, two draw calls.
-- Reference dimensions/poses: src/weapons/hands.js and viewmodel.js.
local G=require "game.weapons.geometry"
local T=require "game.ai.transform"
local V=require "game.weapons.math"
local M={bone_count=17}
local lengths={{.045,.028,.022},{.049,.031,.023},{.046,.029,.022},{.038,.024,.020}}
local xs={.0298,.0102,-.0104,-.0298}
local poses={
    grip={{.55,.72,.34},{1.15,1.2,.62},{1.2,1.25,.65},{1.22,1.28,.66},{.5,.34},{.15,-1.02,-.62}},
    wrap={{1.18,1.05,.45},{1.26,1.12,.5},{1.3,1.16,.55},{1.34,1.2,.6},{.42,.3},{.1,-1.15,-.35}},
    clamp={{.612,1.059,.797},{.731,1.286,.863},{.73,1.268,.808},{.601,1.105,.684},{.3,.24},{.04,.76,-.05}},
    cup={{1.05,.95,.4},{1.12,1,.44},{1.16,1.04,.48},{1.2,1.08,.52},{.28,.2},{0,-1.25,-.2}},
    open={{.35,.28,.14},{.32,.26,.12},{.34,.28,.14},{.4,.32,.16},{.12,.1},{.1,-.8,-.35}},
    pinch={{.95,.85,.55},{1,.9,.6},{.7,.6,.35},{.6,.5,.3},{.62,.55},{.25,-.75,-.7}},
}
local function vec(p) return {x=p[1],y=p[2],z=p[3]} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b) return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
local function perpendicular(z,up)
    local y=V.point(up,z,-dot(up,z))
    if V.length(y)<1e-7 then
        up=math.abs(z.y)<.9 and {x=0,y=1,z=0} or {x=1,y=0,z=0}
        y=V.point(up,z,-dot(up,z))
    end
    return V.normalize(y)
end
-- Right-handed basis: fingers and bones extend along local -Z.
function M.basis(position,finger,back)
    local z=V.normalize({x=-finger.x,y=-finger.y,z=-finger.z})
    local y=perpendicular(z,back);local x=cross(y,z)
    return {x.x,y.x,z.x,position.x,x.y,y.y,z.y,position.y,x.z,y.z,z.z,position.z}
end
local function translate(m,p) m[4],m[8],m[12]=p.x,p.y,p.z;return m end
local function scale_bone(m,z)
    m[3],m[7],m[11]=m[3]*z,m[7]*z,m[11]*z;return m
end

function M.geometry(side)
    local b=G.batch();b.joints={}
    local scale=side<0 and .97 or 1
    local function joint(index,build)
        local first=b.vertex_count;build()
        for _=first+1,b.vertex_count do b.joints[#b.joints+1]=index-1 end
    end
    for index,len in ipairs({.33,.30}) do
        joint(index,function()
            local rings={};local count=index==1 and 10 or 14
            for i=0,count do
                local u=i/count
                local radius=V.lerp(index==1 and .044 or .034,index==1 and .036 or .024,u)*scale
                radius=radius*(i>0 and i<count and (i%2==0 and .93 or 1.04) or 1)
                rings[#rings+1]={len*u,radius,radius*.87}
            end
            G.profile(b,rings,"tan",12)
            if index==1 then G.bevel(b,0,.031,-.29,.046,.012,.057,.004,"dark")
            else
                G.profile(b,{{.276,.026*scale,.023*scale},{.297,.026*scale,.023*scale},{.300,.023*scale,.020*scale}},"glove",12)
                G.bevel(b,0,.021,-.287,.028,.006,.018,.002,"dark")
            end
        end)
    end
    joint(3,function()
        G.profile(b,{{0,.023*scale,.017*scale},{.025,.031*scale,.019*scale},
            {.065,.040*scale,.019*scale},{.094,.039*scale,.014*scale},{.099,.032*scale,.012*scale}},"glove",12)
        G.bevel(b,0,.019,-.055,.058,.007,.046,.003,"dark")
        for i=1,4 do G.bevel(b,xs[i]*scale,.014,-.087,.015,.009,.018,.003,"polymer") end
    end)
    for f=1,4 do for j=1,3 do
        joint(3+(f-1)*3+j,function()
            local r=(.0105-(j-1)*.0015)*(f==4 and .9 or 1)*scale
            local len=lengths[f][j]*scale
            G.profile(b,{{-.001,r*.87,r*.8},{.003,r,r*.92},{len-.003,r*.85,r*.8},{len,r*.65,r*.65}},"glove",8)
            G.bevel(b,0,r*.82,-len*.43,r*1.4,.003,len*.5,.001,"dark")
        end)
    end end
    for j,len in ipairs({.050,.032}) do
        joint(15+j,function()
            local r=(j==1 and .0115 or .0102)*scale
            G.profile(b,{{0,r,r*.9},{len*scale*.7,r*.88,r*.8},{len*scale,r*.68,r*.65}},"glove",8)
        end)
    end
    -- Authored left hand; mirror local geometry for the right hand and reverse
    -- winding. Palettes stay proper rotations (no reflected normal matrices).
    if side>0 then
        for i=1,#b.positions,3 do b.positions[i]=-b.positions[i];b.normals[i]=-b.normals[i] end
        for i=1,b.vertex_count,3 do
            for _,stream in ipairs({b.positions,b.normals,b.colors}) do
                local stride=stream==b.colors and 4 or 3
                for c=1,stride do
                    local a=(i)*stride+c;local z=(i+1)*stride+c
                    stream[a],stream[z]=stream[z],stream[a]
                end
            end
        end
    end
    -- Skinning can move far outside the bone-local mesh bounds.
    b.bounds={-1,-1,-1,1,1,1}
    return b
end

-- Exact endpoint IK with bounded visual length correction for extreme clip
-- poses. No disconnected wrist when a reload reaches outside the rest chain.
function M.solve(shoulder,wrist,back,side)
    local delta=sub(wrist,shoulder);local distance=V.length(delta)
    local dir=distance>1e-7 and V.point({x=0,y=0,z=0},delta,1/distance) or {x=0,y=0,z=-1}
    local scale=side<0 and .97 or 1
    local stretch=math.max(1,distance/(.63*scale*.995))
    local l1,l2=.33*scale*stretch,.30*scale*stretch
    if distance<math.abs(l1-l2)+1e-5 then l1,l2=(l1+l2)/2,(l1+l2)/2 end
    local a=distance>1e-7 and (l1*l1-l2*l2+distance*distance)/(2*distance) or 0
    local pole=perpendicular(dir,{x=side*.46,y=-.86,z=.22})
    local elbow=V.point(V.point(shoulder,dir,a),pole,math.sqrt(math.max(0,l1*l1-a*a)))
    return scale_bone(M.basis(shoulder,sub(elbow,shoulder),pole),l1/.33),
        scale_bone(M.basis(elbow,sub(wrist,elbow),back),l2/.30),elbow,stretch
end

function M.palette(root,target,side,trigger)
    local position=T.point(root,vec(target.position))
    local frame=T.mul(root,M.basis(vec(target.position),vec(target.finger),vec(target.back)))
    local back={x=frame[2],y=frame[6],z=frame[10]}
    local shoulder=side<0 and {x=-.2,y=-.22,z=.02} or {x=.205,y=-.2,z=.06}
    local upper,fore,elbow,stretch=M.solve(shoulder,position,back,side)
    local palette={upper,fore,frame}
    local scale=side<0 and .97 or 1;local mirror=side<0 and 1 or -1
    local from=poses[target.pose or "grip"];local to=poses[target.next_pose or target.pose or "grip"]
    local function angle(i,j) return V.lerp(from[i][j],to[i][j],target.blend or 0) end
    for f=1,4 do
        local parent=frame
        for j=1,3 do
            local curl=angle(f,j)
            if side>0 and f==1 then curl=({.55,.72,.34})[j]+(trigger or 0)*({.30,.42,.30})[j] end
            local local_frame=T.rotation(-curl,j==1 and -xs[f]*2.2*mirror or 0,0)
            translate(local_frame,j==1 and {x=xs[f]*scale*mirror,y=-.006*scale,z=-.096*scale}
                or {x=0,y=0,z=-lengths[f][j-1]*scale})
            parent=T.mul(parent,local_frame);palette[#palette+1]=parent
        end
    end
    local thumb=T.rotation(angle(6,1),angle(6,2)*mirror,angle(6,3)*mirror)
    translate(thumb,{x=.037*scale*mirror,y=-.009*scale,z=-.04*scale})
    local base=T.mul(frame,thumb)
    for j=1,2 do
        local local_frame=T.rotation(-angle(5,j),0,0)
        if j==2 then local_frame[12]=-.05*scale end
        base=T.mul(base,local_frame);palette[#palette+1]=base
    end
    return palette,{shoulder=shoulder,elbow=elbow,wrist=position,stretch=stretch}
end
return M
