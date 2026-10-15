-- Engine-independent export of the production camera and fixture geometry.
local function json(value)
    local kind=type(value)
    if kind=="string" then
        return '"'..value:gsub('[%z\1-\31\\"]',function(c)
            if c=='"' or c=='\\' then return '\\'..c end
            return string.format('\\u%04x',string.byte(c))
        end)..'"'
    elseif kind=="number" then
        assert(value==value and math.abs(value)<math.huge,"Nonfinite export value")
        return string.format("%.17g",value)
    elseif kind=="boolean" then return tostring(value)
    elseif kind=="nil" then return "null" end
    assert(kind=="table","Unsupported export value: "..kind)
    local entries={}
    if #value>0 then
        for i=1,#value do entries[i]=json(value[i]) end
        return "["..table.concat(entries,",").."]"
    end
    local keys={};for k in pairs(value) do keys[#keys+1]=k end;table.sort(keys)
    for _,k in ipairs(keys) do entries[#entries+1]=json(k)..":"..json(value[k]) end
    return "{"..table.concat(entries,",").."}"
end
local mode=arg[1] or "catalog"
if mode=="catalog" then
    local catalog=require("game.render.capture").catalog()
    catalog.world_seed=require("game.world.layout").seed
    catalog.level_to_world={yaw_radians=0,translation={0,0,0}}
    print(json(catalog))
elseif mode=="laboratory" then
    local lab=require "game.render.laboratory"
    local batches={}
    for _,b in ipairs(lab.batches()) do
        batches[#batches+1]={key=b.key,material=b.material,positions=b.positions,normals=b.normals,
            surface=b.surface,glass=b.glass,colors=b.colors}
    end
    print(json({version=1,batches=batches,materials=require "game.world.materials",lights=lab.lights}))
else error("Expected catalog or laboratory") end
