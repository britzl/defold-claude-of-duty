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

function M.new(key, material, chunk_x, chunk_z)
    return { key = key, material = material, chunk_x = chunk_x, chunk_z = chunk_z,
        positions = {}, normals = {}, colors = {}, vertex_count = 0, boxes = 0,
        bounds = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge } }
end

function M.box(batch, box, shade, visible, edge_points)
    local p, n, c, bounds = batch.positions, batch.normals, batch.colors, batch.bounds
    local color = materials[box.material].color
    local center, half = { box.x, box.y, box.z }, { box.w / 2, box.h / 2, box.d / 2 }
    local cosine, sine = math.cos(box.rotation_x or 0), math.sin(box.rotation_x or 0)
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
                local y,z=local_vertex[2],local_vertex[3]
                corners[index]={center[1]+local_vertex[1],center[2]+y*cosine-z*sine,center[3]+y*sine+z*cosine}
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
                local normal = { face.n[1], face.n[2]*cosine-face.n[3]*sine, face.n[2]*sine+face.n[3]*cosine }
                for axis = 1, 3 do
                    p[#p + 1] = vertex[axis]
                    n[#n + 1] = normal[axis]
                    c[#c + 1] = color[axis] * shade
                    bounds[axis] = math.min(bounds[axis], vertex[axis])
                    bounds[axis+3] = math.max(bounds[axis+3], vertex[axis])
                end
                c[#c + 1] = 1
                vertices=vertices+1
            end
        end
    end
    batch.vertex_count = batch.vertex_count + vertices
    batch.boxes = batch.boxes + 1
end

return M
