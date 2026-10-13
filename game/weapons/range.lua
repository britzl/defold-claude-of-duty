-- Optional native fixtures: bare target, thin wood, thick concrete. Real
-- Bullet colliders, normal projectile damage, no soldier/AI dependency.
local world = require "game.world.defold"
local mesh = require "game.world.mesh"
local combat = require "game.combat"
local M = {}
function M.new(ctx)
    local range={adapter=world.new("#world_mesh","#world_collision"),actors={}}
    local shapes={
        {id="range/floor",x=0,y=-.2,z=35,w=18,h=.4,d=25,surface="concrete",material="concrete"},
        {id="range/backstop",x=0,y=2,z=23,w=18,h=4,d=.8,surface="concrete",material="concrete"},
        {id="range/wood",x=0,y=1.5,z=31,w=2,h=3,d=.10,surface="wood",material="wood"},
        {id="range/concrete",x=5,y=1.5,z=31,w=2,h=3,d=.30,surface="concrete",material="concrete"},
    }
    for i,x in ipairs({-5,0,5}) do
        local actor="range_target_"..i
        combat.register(ctx.combat,actor,1000);range.actors[#range.actors+1]=actor
        shapes[#shapes+1]={id=actor,x=x,y=1.5,z=28,w=1.4,h=2.4,d=.12,
            actor=actor,surface="flesh",material="awning_red"}
    end
    local batches={}
    for _,s in ipairs(shapes) do
        local b=batches[s.material]
        if not b then b=mesh.new(s.material,s.material,0,0);batches[s.material]=b end
        mesh.box(b,s,1);world.add_collision(range.adapter,s)
    end
    for _,b in pairs(batches) do world.add_batch(range.adapter,b) end
    return range
end
function M.snapshot(ctx,range)
    local result={}
    for _,id in ipairs(range.actors) do result[id]=ctx.combat.actors[id].health end
    return result
end
function M.final(ctx,range)
    for _,id in ipairs(range.actors) do combat.remove(ctx.combat,id) end
    world.final(range.adapter)
end
return M
