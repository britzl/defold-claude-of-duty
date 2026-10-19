-- Rigid, row-major 3x4 transforms. Pure Lua so skinning and hit volumes share
-- exactly the same tested math on every engine backend.
local M = {}
function M.identity(x,y,z) return {1,0,0,x or 0, 0,1,0,y or 0, 0,0,1,z or 0} end
function M.rotation(x,y,z,out)
    local a,b,c,d,e,f=math.cos(x or 0),math.sin(x or 0),math.cos(y or 0),math.sin(y or 0),math.cos(z or 0),math.sin(z or 0)
    if not out then return {c*e+d*b*f,-c*f+d*b*e,d*a,0, a*f,a*e,-b,0, -d*e+c*b*f,d*f+c*b*e,c*a,0} end
    out[1],out[2],out[3],out[4]=c*e+d*b*f,-c*f+d*b*e,d*a,0
    out[5],out[6],out[7],out[8]=a*f,a*e,-b,0
    out[9],out[10],out[11],out[12]=-d*e+c*b*f,d*f+c*b*e,c*a,0
    return out
end
-- A reusable destination must be distinct from both inputs.
function M.mul(a,b,out)
    out=out or {}
    for r=0,2 do
        local i=r*4
        for c=1,3 do out[i+c]=a[i+1]*b[c]+a[i+2]*b[4+c]+a[i+3]*b[8+c] end
        out[i+4]=a[i+1]*b[4]+a[i+2]*b[8]+a[i+3]*b[12]+a[i+4]
    end
    return out
end
function M.point(m,p)
    return {x=m[1]*p.x+m[2]*p.y+m[3]*p.z+m[4],
        y=m[5]*p.x+m[6]*p.y+m[7]*p.z+m[8], z=m[9]*p.x+m[10]*p.y+m[11]*p.z+m[12]}
end
function M.direction(m,p)
    return {x=m[1]*p.x+m[2]*p.y+m[3]*p.z,
        y=m[5]*p.x+m[6]*p.y+m[7]*p.z, z=m[9]*p.x+m[10]*p.y+m[11]*p.z}
end
function M.inverse(m)
    return {m[1],m[5],m[9],-(m[1]*m[4]+m[5]*m[8]+m[9]*m[12]),
        m[2],m[6],m[10],-(m[2]*m[4]+m[6]*m[8]+m[10]*m[12]),
        m[3],m[7],m[11],-(m[3]*m[4]+m[7]*m[8]+m[11]*m[12])}
end
function M.root(position,yaw)
    local m=M.rotation(0,yaw,0)
    m[4],m[8],m[12]=position.x,position.y,position.z
    return m
end
function M.origin(m) return {x=m[4],y=m[8],z=m[12]} end
function M.cross(a,b) return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
function M.dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
-- Shortest arc, including antiparallel and zero-length input directions.
function M.between(a,b)
    local function unit(v)
        local n=math.sqrt(M.dot(v,v));if n<1e-9 then return end
        return {x=v.x/n,y=v.y/n,z=v.z/n}
    end
    a,b=unit(a),unit(b)
    if not a or not b then return M.identity() end
    local c=math.max(-1,math.min(1,M.dot(a,b)))
    if c>1-1e-12 then return M.identity() end
    local axis=M.cross(a,b)
    if c< -1+1e-9 then axis=M.cross(a,math.abs(a.y)<.9 and {x=0,y=1,z=0} or {x=1,y=0,z=0}) end
    axis=unit(axis)
    local x,y,z=axis.x,axis.y,axis.z
    local s=math.sqrt(math.max(0,1-c*c));local d=1-c
    return {c+x*x*d,x*y*d-z*s,x*z*d+y*s,0,
        y*x*d+z*s,c+y*y*d,y*z*d-x*s,0,z*x*d-y*s,z*y*d+x*s,c+z*z*d,0}
end
return M
