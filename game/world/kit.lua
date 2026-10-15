-- Bounded procedural building/prop kit. Collision uses authored, axis-aligned
-- envelopes; small visual parts never manufacture physics or navigation nodes.
local M={}
function M.box(id,material,x,y,z,w,h,d,surface,cover,extra)
    assert(w>0 and h>0 and d>0,"Invalid shape: "..id)
    local s={id=id,material=material,x=x,y=y,z=z,w=w,h=h,d=d,surface=surface,cover=cover}
    for k,v in pairs(extra or {}) do s[k]=v end
    assert(not surface or not (s.rotation_x or s.rotation_y or s.rotation_z),"Rotate decoration, not collision envelopes")
    coroutine.yield(s)
end
function M.solid(kind,id,material,x,y,z,w,h,d,surface,cover,extra)
    local s={kind=kind}
    for k,v in pairs(extra or {}) do s[k]=v end
    M.box(id,material,x,y,z,w,h,d,surface,cover,s)
end
function M.beam(id,material,a,b,width)
    local dx,dy,dz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
    local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    M.box(id,material,(a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2,width,length,width,nil,nil,
        {rotation_x=math.acos(dy/length),rotation_y=math.atan2(dx,dz)})
end
function M.prism(id,material,points,z,depth,surface)
    local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
    for _,p in ipairs(points) do x0=math.min(x0,p[1]);y0=math.min(y0,p[2]);x1=math.max(x1,p[1]);y1=math.max(y1,p[2]) end
    local x,y=(x0+x1)/2,(y0+y1)/2
    local local_points={}
    for i,p in ipairs(points) do local_points[i]={p[1]-x,p[2]-y} end
    M.solid("prism",id,material,x,y,z,x1-x0,y1-y0,depth,surface,nil,{profile=local_points})
end
function M.cable(id,a,b,sag)
    local previous=a
    for i=1,12 do
        local t=i/12
        local point={a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t-4*sag*t*(1-t),a[3]+(b[3]-a[3])*t}
        M.beam(id.."/"..i,"dark",previous,point,.025);previous=point
    end
end
function M.bags(id,x,y,z,length,courses,collision)
    local count=math.ceil(length/.75)
    if collision then
        -- One solid course forms the cover envelope; staggered rounded bags
        -- above and around it give the wall its silhouette.
        M.box(id.."/core","burlap",x,y+courses*.13,z,length-.12,courses*.26,.52,"fabric",
            type(collision)=="table" and collision or {normal_x=0,normal_z=1})
    end
    for row=1,courses do for i=1,count do
        local offset=(row%2==0 and .08 or -.08)
        M.solid("bevel",id.."/"..row.."/"..i,"burlap",x-length/2+(i-.5)*length/count+offset,
            y+(row-.5)*.27,z+(row%2)*.035,length/count+.015,.28,.64,nil,nil,{bevel=.1})
    end end
end
function M.rug(id,x,y,z,w,d)
    M.box(id,"awning_red",x,y+.012,z,w,.024,d)
    for _,s in ipairs({-1,1}) do
        M.box(id.."/border/x/"..s,"awning_cream",x+s*(w/2-.12),y+.027,z,.1,.008,d-.14)
        M.box(id.."/border/z/"..s,"awning_cream",x,y+.027,z+s*(d/2-.12),w-.14,.008,.1)
    end
    for i=-2,2 do M.box(id.."/motif/"..i,"awning_cream",x+i*w/6,y+.028,z,w/12,.009,d/4,nil,nil,{rotation_y=.785}) end
end
return M
