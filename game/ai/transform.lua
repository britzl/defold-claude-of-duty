-- Rigid, row-major 3x4 transforms. Pure Lua so skinning and hit volumes share
-- exactly the same tested math on every engine backend.
local M = {}
function M.identity(x,y,z) return {1,0,0,x or 0, 0,1,0,y or 0, 0,0,1,z or 0} end
function M.rotation(x,y,z)
    local a,b,c,d,e,f=math.cos(x or 0),math.sin(x or 0),math.cos(y or 0),math.sin(y or 0),math.cos(z or 0),math.sin(z or 0)
    return {c*e+d*b*f,-c*f+d*b*e,d*a,0, a*f,a*e,-b,0, -d*e+c*b*f,d*f+c*b*e,c*a,0}
end
function M.mul(a,b)
    local out={}
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
return M
