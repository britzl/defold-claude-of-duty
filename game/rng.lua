-- Park-Miller streams: exact arithmetic in Lua's double precision numbers.
local M = {}
local MODULUS = 2147483647

function M.new(seed, name)
    local state = math.floor(seed) % (MODULUS - 1) + 1
    for i = 1, #(name or "") do state = (state * 31 + name:byte(i)) % MODULUS end
    if state == 0 then state = 1 end
    return function()
        state = (state * 16807) % MODULUS
        return (state - 1) / (MODULUS - 1)
    end
end

return M
