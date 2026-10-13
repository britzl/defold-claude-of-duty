local M = {}
function M.clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
function M.lerp(a, b, t) return a+(b-a)*t end
function M.smooth(t) t=M.clamp(t,0,1); return t*t*t*(t*(t*6-15)+10) end
function M.copy(v) return { x=v.x, y=v.y, z=v.z } end
function M.length(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end
function M.normalize(v)
    local n=M.length(v)
    return {x=v.x/n,y=v.y/n,z=v.z/n}
end
function M.point(p,d,t) return {x=p.x+d.x*t,y=p.y+d.y*t,z=p.z+d.z*t} end
-- Same Y * X * Z rotation order as the camera; +Y up, forward -Z.
function M.rotate(v, pitch, yaw, roll)
    local cr,sr=math.cos(roll or 0),math.sin(roll or 0)
    local x,y=v.x*cr-v.y*sr,v.x*sr+v.y*cr
    local cx,sx=math.cos(pitch),math.sin(pitch)
    local z=v.z*cx+y*sx
    y=y*cx-v.z*sx
    local cy,sy=math.cos(yaw),math.sin(yaw)
    return {x=x*cy+z*sy,y=y,z=z*cy-x*sy}
end
function M.spring() return { x=0, v=0 } end
-- Exact solution of an underdamped spring, stable independently of timestep.
function M.step(s, dt, frequency, damping)
    local w=2*math.pi*frequency
    local a=w*damping
    local b=w*math.sqrt(1-damping*damping)
    local e,c,n=math.exp(-a*dt),math.cos(b*dt),math.sin(b*dt)
    local x,v=s.x,s.v
    s.x=e*(x*c+(v+a*x)/b*n)
    s.v=e*(v*c-(a*v+w*w*x)/b*n)
end
return M
