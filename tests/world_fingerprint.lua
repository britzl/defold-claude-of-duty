-- Canonical complete generated-world export for before/after regression checks.
-- Lua 5.4: lua tests/world_fingerprint.lua output.bin [seed] [detail=false]
local generator=require "game.world.generator"
local world=generator.new(require "game.world.layout",{seed=tonumber(arg[2]) or 1337,detail=arg[3]~="false"})
while world.phase=="geometry" do generator.step(world,4096) end
local file=assert(io.open(assert(arg[1],"output path required"),"wb"))
local pending={}
local function write(value)
    pending[#pending+1]=value
    if #pending==4096 then file:write(table.concat(pending));pending={} end
end
local function serialize(value)
    local kind=type(value)
    if kind=="number" then write("n"..string.pack("<d",value==0 and 0 or value))
    elseif kind=="string" then write("s"..string.pack("<I4",#value)..value)
    elseif kind=="boolean" then write(value and "t" or "f")
    elseif kind=="table" then
        write("{")
        local keys={}
        for key in pairs(value) do keys[#keys+1]=key end
        table.sort(keys,function(a,b) if type(a)~=type(b) then return type(a)<type(b) end return a<b end)
        for _,key in ipairs(keys) do serialize(key);serialize(value[key]) end
        write("}")
    else error("Unexpected generated value: "..kind) end
end
for _,name in ipairs({"batches","shapes","colliders","navigation","cover","minimap","lights","lighting_volumes",
    "spawn","spawn_points","spawn_anchors","views","stats","seed"}) do
    serialize(name);serialize(world[name])
end
file:write(table.concat(pending));file:close()
print("Exported",world.stats.boxes,"shapes",world.stats.vertices,"vertices",world.stats.colliders,"colliders")
