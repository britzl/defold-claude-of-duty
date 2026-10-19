-- One generated mesh with four float indices/weights per vertex. No imported
-- models or animation resources. Joint indices become zero-based at this boundary.
local rig = require "game.ai.rig"
local primitive = require "game.weapons.geometry"
local V = require "game.weapons.math"
local variants=require "game.ai.variants"
local T=require "game.ai.transform"
local M = {}
local cloth={.48,.43,.29,6}
local gear={.29,.28,.19,3}
local dark={.075,.083,.078,5}
local skin={.54,.36,.24,4}
local function cross(a,b) return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
local function weights(b,first,last,a,c,w)
    for _=first,last do
        b.joints[#b.joints+1]=rig.index[a]-1
        b.joints[#b.joints+1]=rig.index[c or a]-1
        b.joints[#b.joints+1]=0;b.joints[#b.joints+1]=0
        b.weights[#b.weights+1]=1-(w or 0);b.weights[#b.weights+1]=w or 0
        b.weights[#b.weights+1]=0;b.weights[#b.weights+1]=0
    end
end
local function box(b,bone,x,y,z,w,h,d,color,rx)
    local first=b.vertex_count+1
    primitive.box(b,x,y,z,w,h,d,color,rx)
    weights(b,first,b.vertex_count,bone)
end
local function vertex(b,p,n,color,bone,other,weight)
    for _,axis in ipairs({"x","y","z"}) do
        local j=axis=="x" and 1 or axis=="y" and 2 or 3
        b.positions[#b.positions+1]=p[axis];b.normals[#b.normals+1]=n[axis]
        b.bounds[j]=math.min(b.bounds[j],p[axis]);b.bounds[j+3]=math.max(b.bounds[j+3],p[axis])
    end
    for i=1,4 do b.colors[#b.colors+1]=color[i] end
    b.vertex_count=b.vertex_count+1
    weights(b,1,1,bone,other,weight)
end
local function ellipsoid(b,bone,c,scale,color,other)
    local slices,rings=12,8
    local function sample(u,v)
        local a,t=u*math.pi*2,v*math.pi
        local x,y,z=math.sin(t)*math.cos(a),math.cos(t),math.sin(t)*math.sin(a)
        return {x=c.x+x*scale.x,y=c.y+y*scale.y,z=c.z+z*scale.z},
            V.normalize({x=x/scale.x,y=y/scale.y,z=z/scale.z})
    end
    local function emit(u,v)
        local p,n=sample(u,v)
        vertex(b,p,n,color,bone,other,other and math.max(0,.35-v)*.7 or 0)
    end
    for r=0,rings-1 do for s=0,slices-1 do
        local u,v=s/slices,r/rings
        local un,vn=(s+1)/slices,(r+1)/rings
        if r>0 then emit(u,v);emit(un,v);emit(u,vn) end
        if r<rings-1 then emit(un,v);emit(un,vn);emit(u,vn) end
    end end
end
local function limb(b,first,last,r1,r2,color)
    local a,c=rig.bones[rig.index[first]].bind,rig.bones[rig.index[last]].bind
    local axis=V.normalize({x=c.x-a.x,y=c.y-a.y,z=c.z-a.z})
    local side=V.normalize(cross(axis,{x=0,y=0,z=1}))
    local front=cross(axis,side)
    local slices,rings=10,4
    local function emit(s,r)
        local t=r/rings
        local radius=V.lerp(r1,r2,t)
        local theta=s/slices*math.pi*2
        local n={x=side.x*math.cos(theta)+front.x*math.sin(theta),
            y=side.y*math.cos(theta)+front.y*math.sin(theta),z=side.z*math.cos(theta)+front.z*math.sin(theta)}
        local p={x=V.lerp(a.x,c.x,t)+n.x*radius,y=V.lerp(a.y,c.y,t)+n.y*radius,z=V.lerp(a.z,c.z,t)+n.z*radius}
        vertex(b,p,n,color,first,last,math.max(0,(t-.72)/.28)*.5)
    end
    for r=0,rings-1 do for s=0,slices-1 do
        emit(s,r);emit(s+1,r);emit(s,r+1)
        emit(s+1,r);emit(s+1,r+1);emit(s,r+1)
    end end
end
function M.build(name)
    local variant=variants.get(name)
    local cloth,gear,skin=variant.cloth,variant.gear,variant.skin
    local b=primitive.batch();b.joints={};b.weights={}
    ellipsoid(b,"Hips",{x=0,y=1.00,z=0},{x=.19,y=.145,z=.14},cloth,"Spine")
    ellipsoid(b,"Spine",{x=0,y=1.22,z=0},{x=.225,y=.255,z=.14},cloth,"Spine2")
    ellipsoid(b,"Neck",{x=0,y=1.50,z=0},{x=.064,y=.065,z=.067},skin)
    ellipsoid(b,"Head",{x=0,y=1.655,z=0},{x=.104,y=.138,z=.108},skin)
    if variant.helmet then
    ellipsoid(b,"Head",{x=0,y=1.745,z=.012},{x=.126,y=.096,z=.135},variant.shell,"HeadTop")
    box(b,"Head",0,1.705,-.106,.265,.035,.115,gear)
    else
        ellipsoid(b,"Head",{x=0,y=1.743,z=.006},{x=.112,y=.079,z=.12},variant.shell)
        for i=0,3 do box(b,"Head",0,1.725+i*.013,-.098,.20,.009,.026,gear) end
        box(b,"Neck",-.095,1.51,.05,.055,.18,.032,gear,-.12)
    end
    if variant.goggles or variant.shades then
        local y=variant.goggles and not variant.goggles_down and 1.76 or 1.668
        box(b,"Head",0,y,-.112,.205,.043,.038,dark)
        for _,x in ipairs({-.052,.052}) do box(b,"Head",x,y,-.135,.078,.027,.009,{.15,.19,.18,1}) end
        box(b,"Head",0,y,.08,.22,.018,.10,dark)
    end
    if variant.beard then ellipsoid(b,"Head",{x=0,y=1.573,z=-.036},{x=.075,y=.048,z=.07},dark) end
    box(b,"Head",0,1.652,-.108,.032,.043,.036,skin)
    for _,x in ipairs({-.105,.105}) do
        ellipsoid(b,"Head",{x=x,y=1.64,z=.006},{x=.025,y=.039,z=.022},skin)
    end
    box(b,"Head",0,1.60,-.10,.165,.076,.042,variant.hard_mask and dark or gear)
    if variant.hard_mask then
        for i=-2,2 do box(b,"Head",i*.026,1.596,-.124,.010,.035,.006,primitive.colors.metal) end
    end
    if variant.carrier then
        box(b,"Spine2",0,1.30,-.14,.32,.31,.062,gear)
        box(b,"Spine2",0,1.30,.137,.32,.31,.06,gear)
        box(b,"Spine2",.06,1.28,.19,.20,.24,.065,gear)
    else
        box(b,"Spine1",0,1.21,-.14,.31,.16,.04,gear)
    end
    for _,x in ipairs({-.13,.13}) do
        box(b,"Spine2",x,1.36,-.12,.043,.22,.04,gear)
        box(b,"Spine2",x,1.415,0,.043,.025,.26,gear)
    end
    for y=1.20,1.40,.04 do box(b,"Spine2",0,y,-.175,.28,.009,.008,dark) end
    box(b,"Spine2",.18,1.29,-.06,.055,.11,.07,gear)
    box(b,"Spine2",.19,1.40,-.05,.007,.15,.007,dark)
    box(b,"Hips",-.19,1.0,.04,.075,.12,.09,gear)
    for i=-1,1 do box(b,"Spine2",i*.101,1.21,-.187,.086,.14,.054,{.36,.32,.21,3}) end
    box(b,"Hips",0,1.018,0,.38,.055,.30,dark)
    for _,side in ipairs({"R","L"}) do
        limb(b,"UpperArm"..side,"Forearm"..side,.075,.06,cloth)
        limb(b,"Forearm"..side,"Hand"..side,.059,.039,cloth)
        local hand=rig.bones[rig.index["Hand"..side]].bind
        ellipsoid(b,"Hand"..side,hand,{x=.044,y=.039,z=.065},dark,"Fingers"..side)
        limb(b,"UpLeg"..side,"Leg"..side,.096,.071,cloth)
        limb(b,"Leg"..side,"Foot"..side,.073,.053,cloth)
        local sign=side=="R" and 1 or -1
        if variant.knee_pads then box(b,"Leg"..side,sign*.098,.51,-.073,.114,.15,.042,gear) end
        box(b,"UpLeg"..side,sign*.17,.76,.01,.035,.15,.12,gear)
        box(b,"UpperArm"..side,sign*.23,1.34,0,.035,.08,.065,gear)
        ellipsoid(b,"Foot"..side,{x=sign*.103,y=.075,z=-.06},{x=.076,y=.083,z=.155},dark,"Toe"..side)
        box(b,"Foot"..side,sign*.103,.023,-.06,.147,.038,.28,dark)
    end
    -- Carbine and long-stroke rifle share authored sockets and an exact bore.
    local gun=primitive.batch();local long=variant.weapon=="ak"
    local function part(t,y,w,h,d,color,rx)
        primitive.box(gun,0,y,-t,w,h,d,color,rx)
    end
    part(.265,-.016,.065,.084,.26,primitive.colors.metal)
    part(.45,-.008,.065,.067,.24,long and {.29,.17,.09,2} or primitive.colors.polymer)
    part(.70,0,.019,.019,long and .30 or .20,primitive.colors.steel)
    part(long and .845 or .78,0,.030,.030,.040,dark)
    part(.055,-.025,.067,.10,.20,long and primitive.colors.metal or dark)
    part(.26,-.095,.037,.10,.05,dark,-.30)
    for i=0,5 do part(.33+i*i*(long and .0015 or .0006),-.075-i*.025,.035,.031,.065,dark,-i*.05) end
    part(.25,-.068,.043,.009,.078,primitive.colors.metal)
    part(.30,-.045,.008,.026,.008,dark,-.15)
    if long then
        part(.62,.025,.012,.055,.018,primitive.colors.metal)
        part(.30,.04,.032,.018,.035,dark)
        part(.08,.022,.055,.013,.15,primitive.colors.metal)
    else
        part(.31,.055,.043,.05,.064,dark)
        part(.31,.084,.05,.009,.067,primitive.colors.metal)
        for i=0,9 do part(.18+i*.027,.042,.06,.009,.010,primitive.colors.metal) end
        for i=0,4 do part(.40+i*.025,.018,.069,.008,.013,dark) end
    end
    local z={x=-variants.bore.x,y=-variants.bore.y,z=-variants.bore.z}
    local x=V.normalize(T.cross({x=0,y=1,z=0},z));local y=T.cross(z,x)
    local origin=variants.along(0)
    local frame={x.x,y.x,z.x,origin.x,x.y,y.y,z.y,origin.y,x.z,y.z,z.z,origin.z}
    for i=1,#gun.positions,3 do
        local p=T.point(frame,{x=gun.positions[i],y=gun.positions[i+1],z=gun.positions[i+2]})
        local n=T.direction(frame,{x=gun.normals[i],y=gun.normals[i+1],z=gun.normals[i+2]})
        local c=(i-1)/3*4+1
        vertex(b,p,n,{gun.colors[c],gun.colors[c+1],gun.colors[c+2],gun.colors[c+3]},"HandR")
    end
    -- Bulk changes soft-tissue/equipment radii about their joint, not lengths.
    -- The uniform height scale applies equally to mesh, skeleton and volumes.
    for i=1,b.vertex_count do
        local at=(i-1)*3;local joint=b.joints[(i-1)*4+1]+1
        local bone=rig.bones[joint]
        local bulk=(bone.name:find("Hand") or bone.name:find("Head") or bone.name=="Neck" or bone.name:find("Foot")) and 1 or variant.bulk
        b.positions[at+1]=(bone.bind.x+(b.positions[at+1]-bone.bind.x)*bulk)*variant.scale
        b.positions[at+2]=b.positions[at+2]*variant.scale
        b.positions[at+3]=(bone.bind.z+(b.positions[at+3]-bone.bind.z)*bulk)*variant.scale
        local normal=V.normalize({x=b.normals[at+1]/bulk,y=b.normals[at+2],z=b.normals[at+3]/bulk})
        b.normals[at+1],b.normals[at+2],b.normals[at+3]=normal.x,normal.y,normal.z
    end
    b.variant=variant.id
    b.bytes=b.vertex_count*18*4
    -- A fixed conservative bound includes every supported pose and the collapse.
    -- Bind-pose bounds alone would incorrectly cull animated limbs.
    b.bind_bounds=b.bounds;b.bounds={-2,-.3,-2,2,2.5,2}
    return b
end
return M
