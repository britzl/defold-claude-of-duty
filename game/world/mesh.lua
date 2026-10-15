local materials = require "game.world.materials"
local visible_faces=require "game.world.visible_faces"
local M = {}

-- CCW as seen from outside. Triangles use each face's four corners.
local faces = {
    { n = { 1, 0, 0 }, { 1,-1,-1 }, { 1,1,-1 }, { 1,1,1 }, { 1,-1,1 } },
    { n = {-1, 0, 0 }, {-1,-1,1 }, {-1,1,1 }, {-1,1,-1 }, {-1,-1,-1 } },
    { n = { 0, 1, 0 }, {-1,1,-1 }, {-1,1,1 }, { 1,1,1 }, { 1,1,-1 } },
    { n = { 0,-1, 0 }, {-1,-1,1 }, {-1,-1,-1 }, { 1,-1,-1 }, { 1,-1,1 } },
    { n = { 0, 0, 1 }, {-1,-1,1 }, { 1,-1,1 }, { 1,1,1 }, {-1,1,1 } },
    { n = { 0, 0,-1 }, { 1,-1,-1 }, {-1,-1,-1 }, {-1,1,-1 }, { 1,1,-1 } },
}
local indices = { 1, 2, 3, 1, 3, 4 }

local function rotate(v,s,inverse)
    local order=inverse and {"z","y","x"} or {"x","y","z"}
    local p={v[1],v[2],v[3]}
    for _,axis in ipairs(order) do
        local a=(s["rotation_"..axis] or 0)*(inverse and -1 or 1)
        local c,t=math.cos(a),math.sin(a)
        if axis=="x" then p[2],p[3]=p[2]*c-p[3]*t,p[2]*t+p[3]*c
        elseif axis=="y" then p[1],p[3]=p[1]*c+p[3]*t,-p[1]*t+p[3]*c
        else p[1],p[2]=p[1]*c-p[2]*t,p[1]*t+p[2]*c end
    end
    return p
end

function M.new(key, material, chunk_x, chunk_z)
    return { key = key, material = material, chunk_x = chunk_x, chunk_z = chunk_z,
        positions = {}, normals = {}, colors = {}, edges = {}, masks = {}, vertex_count = 0, boxes = 0,
        bounds = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge } }
end

function M.box(batch, box, shade, visible, edge_points)
    local p, n, c, bounds = batch.positions, batch.normals, batch.colors, batch.bounds
    local color = materials[box.material].color
    local center, half = { box.x, box.y, box.z }, { box.w / 2, box.h / 2, box.d / 2 }
    local axis_pairs={{2,3},{2,3},{1,3},{1,3},{1,2},{1,2}}
    local vertices=0
    for face_index, face in ipairs(faces) do
        local u,v=axis_pairs[face_index][1],axis_pairs[face_index][2]
        local rectangles=visible and visible[face_index] or {{center[u]-half[u],center[v]-half[v],center[u]+half[u],center[v]+half[v]}}
        for _,rectangle in ipairs(rectangles) do
            local corners={}
            for index=1,4 do
                local corner = face[index]
                local local_vertex={corner[1]*half[1],corner[2]*half[2],corner[3]*half[3]}
                local_vertex[u]=rectangle[corner[u]<0 and 1 or 3]-center[u]
                local_vertex[v]=rectangle[corner[v]<0 and 2 or 4]-center[v]
                local v=rotate(local_vertex,box)
                corners[index]={center[1]+v[1],center[2]+v[2],center[3]+v[3]}
            end
            local boundary={}
            for i,a in ipairs(corners) do
                boundary[#boundary+1]=a
                if edge_points then
                    for _,point in ipairs(visible_faces.edge_vertices(edge_points,a,corners[i%4+1])) do
                        boundary[#boundary+1]=point
                    end
                end
            end
            local triangles={}
            if #boundary==4 then
                for _,index in ipairs(indices) do triangles[#triangles+1]=corners[index] end
            else
                -- A centre fan retains every collinear perimeter point without
                -- degenerate triangles or propagating cuts to the opposite edge.
                local middle={}
                for axis=1,3 do middle[axis]=(corners[1][axis]+corners[3][axis])*.5 end
                for i,a in ipairs(boundary) do
                    triangles[#triangles+1]=middle;triangles[#triangles+1]=a
                    triangles[#triangles+1]=boundary[i%#boundary+1]
                end
            end
            for _,vertex in ipairs(triangles) do
                local normal = rotate(face.n,box)
                for axis = 1, 3 do
                    p[#p + 1] = vertex[axis]
                    n[#n + 1] = normal[axis]
                    c[#c + 1] = color[axis] * shade
                    bounds[axis] = math.min(bounds[axis], vertex[axis])
                    bounds[axis+3] = math.max(bounds[axis+3], vertex[axis])
                end
                c[#c + 1] = materials[box.material].coverage or 1
                local local_position=rotate({vertex[1]-center[1],vertex[2]-center[2],vertex[3]-center[3]},box,true)
                local horizontal,vertical=u,v
                if u==2 then horizontal,vertical=v,u end
                local e=batch.edges
                e[#e+1]=local_position[horizontal]+half[horizontal]
                e[#e+1]=half[horizontal]-local_position[horizontal]
                e[#e+1]=local_position[vertical]+half[vertical]
                e[#e+1]=half[vertical]-local_position[vertical]
                local mask=box.weather_masks or {1,.35,.18,1}
                -- Ground chunk boundaries are bookkeeping, not worn edges.
                local ground=box.id and (box.id:match("^road/") or box.id:match("^walk/") or box.id:match("^ground/"))
                for j=1,3 do batch.masks[#batch.masks+1]=ground and 0 or mask[j] end
                -- Visible rectangles under a sill/ledge carry its actual source
                -- height; original box edges still define wear. No stain quads.
                local top=u==2 and rectangle[3] or v==2 and rectangle[4] or center[2]+half[2]
                batch.masks[#batch.masks+1]=ground and 0 or (mask[4]>0 and top or -1000)
                vertices=vertices+1
            end
        end
    end
    batch.vertex_count = batch.vertex_count + vertices
    batch.boxes = batch.boxes + 1
end

-- Small reusable solids. Every primitive has a bounded tessellation and writes
-- the same five streams as clipped architecture; no per-prop render objects.
function M.primitive(batch,s,shade)
    local material=materials[s.material]
    local function triangle(a,b,c,back)
        local u,v={b[1]-a[1],b[2]-a[2],b[3]-a[3]},{c[1]-a[1],c[2]-a[2],c[3]-a[3]}
        local n={u[2]*v[3]-u[3]*v[2],u[3]*v[1]-u[1]*v[3],u[1]*v[2]-u[2]*v[1]}
        local length=math.sqrt(n[1]^2+n[2]^2+n[3]^2)
        if length<1e-10 then return end
        for k=1,3 do n[k]=n[k]/length end
        n=rotate(n,s)
        for _,p in ipairs({a,b,c}) do
            local r=rotate(p,s)
            for k,offset in ipairs({s.x,s.y,s.z}) do
                local value=r[k]+offset
                batch.positions[#batch.positions+1]=value
                batch.normals[#batch.normals+1]=n[k]
                batch.colors[#batch.colors+1]=material.color[k]*shade
                batch.bounds[k]=math.min(batch.bounds[k],value)
                batch.bounds[k+3]=math.max(batch.bounds[k+3],value)
            end
            batch.colors[#batch.colors+1]=s.kind=="frond" and 1 or material.coverage or 1
            for k=1,4 do
                batch.edges[#batch.edges+1]=1
                batch.masks[#batch.masks+1]=k==4 and -1000 or 0
            end
            batch.vertex_count=batch.vertex_count+1
        end
        if back then triangle(c,b,a,false) end
    end
    local function quad(a,b,c,d,back) triangle(a,b,c,back);triangle(a,c,d,back) end
    local w,h,d=s.w/2,s.h/2,s.d/2
    if s.kind=="prism" then
        -- Counterclockwise convex XY profile, extruded along Z. Used for arch
        -- voussoirs/spandrels, broken slabs and tapered barrier sections.
        local p=s.profile
        for i=2,#p-1 do
            triangle({p[1][1],p[1][2],d},{p[i][1],p[i][2],d},{p[i+1][1],p[i+1][2],d})
            triangle({p[1][1],p[1][2],-d},{p[i+1][1],p[i+1][2],-d},{p[i][1],p[i][2],-d})
        end
        for i,a in ipairs(p) do
            local b=p[i%#p+1]
            quad({a[1],a[2],-d},{b[1],b[2],-d},{b[1],b[2],d},{a[1],a[2],d})
        end
    elseif s.kind=="torus" then
        local function point(a,b)
            local radius=.72+.28*math.cos(b)
            return {w*radius*math.cos(a),h*math.sin(b),d*radius*math.sin(a)}
        end
        for i=0,11 do for j=0,5 do
            local a,b=i*math.pi/6,j*math.pi/3
            quad(point(a,b),point(a,b+math.pi/3),point(a+math.pi/6,b+math.pi/3),point(a+math.pi/6,b))
        end end
    elseif s.kind=="frond" then
        -- Palm leaflets own their silhouette. Applying the generic broadleaf
        -- card mask to a narrow frond discarded almost all distant foliage.
        -- Retain the foliage surface recipe, with opaque two-sided triangles.
        for i=0,11 do
            local a,b=i/12,(i+1)/12
            local ya,za=h*(1-2*a*a),-d+2*d*a
            local yb,zb=h*(1-2*b*b),-d+2*d*b
            local r=w*.04
            quad({-r,ya,za},{-r,yb,zb},{r,yb,zb},{r,ya,za},true)
        end
        for i=1,12 do
            local t=(i-.5)/12
            local y,z=h*(1-2*t*t),-d+2*d*t
            local length=w*(.25+.75*math.sin(math.pi*t))
            for _,side in ipairs({-1,1}) do
                quad({0,y,z},{side*length*.55,y-.025,z-.055},
                    {side*length,y-h*.17,z+d*.16},{side*length*.4,y-.04,z+.075},true)
            end
        end
    else
        local rings={}
        if s.kind=="bevel" then
            local r=math.min(s.bevel or .06,w*.45,h*.45,d*.45)
            for _,spec in ipairs({{-h,r},{-h+r,0},{h-r,0},{h,r}}) do
                local ring={}
                local x,z=w-spec[2],d-spec[2]
                for _,p in ipairs({{-x+r,-z},{x-r,-z},{x,-z+r},{x,z-r},
                    {x-r,z},{-x+r,z},{-x,z-r},{-x,-z+r}}) do
                    ring[#ring+1]={p[1],spec[1],p[2]}
                end
                rings[#rings+1]=ring
            end
        else
            for _,y in ipairs({-h,h}) do
                local ring={}
                local taper=y==h and (s.taper or 1) or 1
                for i=0,11 do
                    local a=-i*math.pi/6
                    ring[#ring+1]={w*math.cos(a)*taper,y,d*math.sin(a)*taper}
                end
                rings[#rings+1]=ring
            end
        end
        -- XZ octagon is clockwise from above; reverse it for consistent caps.
        if s.kind=="bevel" then
            for _,r in ipairs(rings) do for i=1,#r/2 do r[i],r[#r-i+1]=r[#r-i+1],r[i] end end
        end
        for j=1,#rings-1 do for i,a in ipairs(rings[j]) do
            local next=i%#rings[j]+1
            quad(a,rings[j][next],rings[j+1][next],rings[j+1][i])
        end end
        for i=2,#rings[1]-1 do
            triangle(rings[1][1],rings[1][i+1],rings[1][i])
            local r=rings[#rings];triangle(r[1],r[i],r[i+1])
        end
    end
    batch.boxes=batch.boxes+1
end

function M.shape(batch,s,shade,visible,edge_points)
    if s.kind=="card" then M.card(batch,s,shade)
    elseif s.kind then M.primitive(batch,s,shade)
    else M.box(batch,s,shade,visible,visible and edge_points or nil) end
end

-- A zero-thickness, two-sided card. The opposite winding supplies each side's
-- normal without changing global culling or inventing opaque edge faces.
function M.card(batch,shape,shade)
    local s={}
    for k,v in pairs(shape) do s[k]=v end
    s.d=0
    s.weather_masks=s.weather_masks or {0,0,0,0}
    local face={s.x-s.w/2,s.y-s.h/2,s.x+s.w/2,s.y+s.h/2}
    M.box(batch,s,shade or 1,{{},{},{},{},{face},{face}})
end

return M
