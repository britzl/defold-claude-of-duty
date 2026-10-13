local M = {}

function M.init(ctx)
    -- Runtime sound resources and voice ownership live here in step 7.
    ctx.audio = { resources = {}, voices = {} }
end

function M.final(ctx)
    ctx.audio = nil
end

return M
