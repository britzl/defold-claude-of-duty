-- One generated mesh with four float indices/weights per vertex. No imported
-- models or animation resources. Joint indices become zero-based at this boundary.
local rig = require "game.ai.rig"
local primitive = require "game.weapons.geometry"
local V = require "game.weapons.math"
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
function M.build()
    local b=primitive.batch();b.joints={};b.weights={}
    ellipsoid(b,"Hips",{x=0,y=1.00,z=0},{x=.19,y=.145,z=.14},cloth,"Spine")
    ellipsoid(b,"Spine",{x=0,y=1.22,z=0},{x=.225,y=.255,z=.14},cloth,"Spine2")
    ellipsoid(b,"Neck",{x=0,y=1.50,z=0},{x=.064,y=.065,z=.067},skin)
    ellipsoid(b,"Head",{x=0,y=1.655,z=0},{x=.104,y=.138,z=.108},skin)
    ellipsoid(b,"Head",{x=0,y=1.745,z=.012},{x=.126,y=.096,z=.135},cloth,"HeadTop")
    box(b,"Head",0,1.705,-.106,.265,.035,.115,gear)
    box(b,"Head",0,1.668,-.108,.197,.043,.038,dark)
    box(b,"Head",0,1.60,-.10,.165,.076,.042,gear)
    box(b,"Spine2",0,1.30,-.14,.32,.31,.062,gear)
    box(b,"Spine2",0,1.30,.137,.32,.31,.06,gear)
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
        box(b,"Leg"..side,sign*.098,.51,-.073,.114,.15,.042,gear)
        ellipsoid(b,"Foot"..side,{x=sign*.103,y=.075,z=-.06},{x=.076,y=.083,z=.155},dark,"Toe"..side)
        box(b,"Foot"..side,sign*.103,.023,-.06,.147,.038,.28,dark)
    end
    -- Simplified carried carbine, rigidly skinned to the firing hand.
    local x=.115
    box(b,"HandR",x,1.357,-.26,.062,.08,.30,primitive.colors.metal,-.10)
    box(b,"HandR",x,1.37,-.465,.061,.065,.23,primitive.colors.polymer,-.10)
    box(b,"HandR",x,1.337,-.622,.021,.021,.18,primitive.colors.steel,-.10)
    box(b,"HandR",x,1.384,.006,.066,.10,.22,dark,-.10)
    box(b,"HandR",x,1.255,-.25,.041,.16,.07,dark,-.16)
    box(b,"HandR",x,1.431,-.24,.041,.045,.058,dark)
    b.bytes=b.vertex_count*18*4
    -- A fixed conservative bound includes every supported pose and the collapse.
    -- Bind-pose bounds alone would incorrectly cull animated limbs.
    b.bind_bounds=b.bounds;b.bounds={-2,-.3,-2,2,2.5,2}
    return b
end
return M
