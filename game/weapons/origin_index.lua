-- Static world boxes only. Dynamic hitboxes keep their live registry scan.
-- Each cell contains the original ID/shape pairs, so the existing analytic
-- containment and thickness tests remain authoritative.
local M = { cell_size = 4 }
local EMPTY = {}

function M.new()
    return { cells = {} }
end

function M.add(index, id, shape)
    assert(not shape.transform, "Moving/transformed hitboxes must not use the static origin index")
    local angle = shape.rotation_x or 0
    local half_x = shape.w / 2
    local half_z = (math.abs(math.sin(angle)) * shape.h + math.abs(math.cos(angle)) * shape.d) / 2
    -- trace.box accepts entries up to 1e-7 ahead of the origin. Expand both
    -- sides of cell boundaries, including the rotated containment tolerance.
    local padding = 2e-7 + 1e-9
    local size = M.cell_size
    for x = math.floor((shape.x-half_x-padding)/size), math.floor((shape.x+half_x+padding)/size) do
        local column = index.cells[x]
        if not column then column = {}; index.cells[x] = column end
        for z = math.floor((shape.z-half_z-padding)/size), math.floor((shape.z+half_z+padding)/size) do
            local cell = column[z]
            if not cell then cell = {}; column[z] = cell end
            cell[id] = shape
        end
    end
end

function M.candidates(index, origin, direction)
    -- Ballistics supplies unit directions. Preserve the unindexed query's
    -- behaviour for other callers whose entry tolerance spans further.
    if math.abs(direction.x)>1 or math.abs(direction.y)>1 or math.abs(direction.z)>1 then return nil end
    local column = index.cells[math.floor(origin.x/M.cell_size)]
    return column and column[math.floor(origin.z/M.cell_size)] or EMPTY
end

function M.clear(index)
    index.cells = {}
end

return M
