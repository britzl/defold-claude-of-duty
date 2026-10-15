-- Subtract buried box faces before upload. This also clips a kerb at road
-- height and trim undersides at the facade, giving adjoining surfaces shared
-- edges instead of intersecting polygons with almost identical depth.
local M = {}
local epsilon = 1e-7
local axes = {{1,2,3},{1,2,3},{2,1,3},{2,1,3},{3,1,2},{3,1,2}}
function M.bounds(s)
    -- Curved/rotated decoration cannot occlude its entire bounding box: doing
    -- so cuts holes in walls behind a tyre, cable or transparent palm frond.
    -- Small attached fittings can also opt out to avoid subdividing whole
    -- facades around their tiny contact areas. Depth testing hides their backs.
    return {s.x-s.w/2,s.y-s.h/2,s.z-s.d/2,s.x+s.w/2,s.y+s.h/2,s.z+s.d/2,
        unclipped=s.unclipped==true or s.kind~=nil or s.rotation_x~=nil or s.rotation_y~=nil or s.rotation_z~=nil}
end
local function subtract(rects, cut)
    local result = {}
    local function add(a,b,c,d)
        if c-a>epsilon and d-b>epsilon then result[#result+1]={a,b,c,d} end
    end
    for _,r in ipairs(rects) do
        local a,b,c,d=math.max(r[1],cut[1]),math.max(r[2],cut[2]),math.min(r[3],cut[3]),math.min(r[4],cut[4])
        if c-a<=epsilon or d-b<=epsilon then result[#result+1]=r
        else
            add(r[1],r[2],a,r[4]);add(c,r[2],r[3],r[4])
            add(a,r[2],c,b);add(a,d,c,r[4])
        end
    end
    return result
end
function M.for_box(index, bounds)
    local a=bounds[index]
    if a.unclipped then return nil end
    local neighbours={}
    for j,b in ipairs(bounds) do
        if j~=index and not b.unclipped and b[1]<=a[4]+epsilon and b[4]>=a[1]-epsilon
            and b[2]<=a[5]+epsilon and b[5]>=a[2]-epsilon
            and b[3]<=a[6]+epsilon and b[6]>=a[3]-epsilon then
            neighbours[#neighbours+1]=j
        end
    end
    local faces={}
    for face,axis in ipairs(axes) do
        local k,u,v=axis[1],axis[2],axis[3]
        local positive=face%2==1
        local plane=a[k+(positive and 3 or 0)]
        local rects={{a[u],a[v],a[u+3],a[v+3]}}
        for _,j in ipairs(neighbours) do
            local b=bounds[j]
            -- Equal outward faces have one owner, chosen by recipe order.
            local covered=positive and b[k]<=plane+epsilon and
                (b[k+3]>plane+epsilon or j<index and b[k+3]>=plane-epsilon)
                or not positive and b[k+3]>=plane-epsilon and
                (b[k]<plane-epsilon or j<index and b[k]<=plane+epsilon)
            if covered then rects=subtract(rects,{b[u],b[v],b[u+3],b[v+3]}) end
            if #rects==0 then break end
        end
        faces[face]=rects
    end
    return faces
end
-- Index the endpoints of all visible, collinear edges, including edges created
-- by clipping windows/trim. Merely consulting the original box bounds misses
-- those new T-junctions. Keys tolerate the same arithmetic noise as face clipping.
local function edge_key(a,b)
    local axis=a[1]~=b[1] and 1 or a[2]~=b[2] and 2 or 3
    local u,v=axis%3+1,(axis+1)%3+1
    return axis,string.format("%d/%.7f/%.7f",axis,a[u],a[v])
end
function M.register_edges(registry,bounds,faces)
    for face,rects in ipairs(faces) do
        local pair=axes[face];local k,u,v=pair[1],pair[2],pair[3]
        local plane=bounds[k+(face%2==1 and 3 or 0)]
        for _,r in ipairs(rects) do
            local points={}
            for i,uv in ipairs({{r[1],r[2]},{r[3],r[2]},{r[3],r[4]},{r[1],r[4]}}) do
                local p={};p[k]=plane;p[u]=uv[1];p[v]=uv[2];points[i]=p
            end
            for i,a in ipairs(points) do
                local b=points[i%4+1];local axis,key=edge_key(a,b)
                local line=registry[key] or {};registry[key]=line
                line[#line+1]=a[axis];line[#line+1]=b[axis]
            end
        end
    end
end
function M.edge_vertices(registry,a,b)
    local axis,key=edge_key(a,b)
    local line=registry[key]
    if not line then return {} end
    if not line.sorted then table.sort(line);line.sorted=true end
    local lo,hi=math.min(a[axis],b[axis]),math.max(a[axis],b[axis])
    local result,last={},-math.huge
    for _,value in ipairs(line) do
        if value>lo+epsilon and value<hi-epsilon and value>last+epsilon then
            local p={a[1],a[2],a[3]};p[axis]=value;result[#result+1]=p;last=value
        end
    end
    if a[axis]>b[axis] then
        for i=1,math.floor(#result/2) do result[i],result[#result-i+1]=result[#result-i+1],result[i] end
    end
    return result
end

return M
