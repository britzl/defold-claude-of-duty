-- All generated adapters share the same Bullet world. Only world-group static
-- geometry participates; moving props, hitboxes and movers use other groups.
local M = {}
local generation, settling = 0, 0

function M.changed()
    generation = generation+1
    -- Factory creation and GO deletion are deferred. Disable clearance reuse
    -- through two controller update boundaries, including one complete frame.
    settling = 2
end

function M.advance_frame()
    if settling > 0 then settling = settling-1 end
end

function M.current()
    if settling == 0 then return generation end
end

return M
