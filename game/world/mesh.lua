local materials = require "game.world.materials"
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

function M.box(batch, box, shade)
    local p, n, c, bounds = batch.positions, batch.normals, batch.colors, batch.bounds
    local color = materials[box.material].color
    local center, half = { box.x, box.y, box.z }, { box.w / 2, box.h / 2, box.d / 2 }
    local cosine, sine = math.cos(box.rotation_x or 0), math.sin(box.rotation_x or 0)
    for _, face in ipairs(faces) do
        for _, index in ipairs(indices) do
            local corner = face[index]
            local y, z = corner[2]*half[2], corner[3]*half[3]
            local vertex = { center[1]+corner[1]*half[1], center[2]+y*cosine-z*sine, center[3]+y*sine+z*cosine }
            local normal = { face.n[1], face.n[2]*cosine-face.n[3]*sine, face.n[2]*sine+face.n[3]*cosine }
            for axis = 1, 3 do
                p[#p + 1] = vertex[axis]
                n[#n + 1] = normal[axis]
                c[#c + 1] = color[axis] * shade
                bounds[axis] = math.min(bounds[axis], vertex[axis])
                bounds[axis+3] = math.max(bounds[axis+3], vertex[axis])
            end
            c[#c + 1] = 1
        end
    end
    batch.vertex_count = batch.vertex_count + 36
    batch.boxes = batch.boxes + 1
end

return M
