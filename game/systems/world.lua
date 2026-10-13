local M = {}

function M.init(ctx)
    -- Future generation writes all three representations from the same layout.
    ctx.world = {
        spawn = { x = 0, y = 0, z = 0 },
        batches = {}, colliders = {}, navigation = {}, lights = {},
    }
end

function M.final(ctx)
    -- Generated Defold resources will be released by their owning system here.
    ctx.world = nil
end

return M
