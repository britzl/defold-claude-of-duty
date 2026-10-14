local events = require "game.events"
local M = {}

function M.init(ctx)
    ctx.fx = { hitmarker = 0, damage_flash = 0, flashes = {} }
    events.on(ctx.events,events.WEAPON_FIRE,ctx.fx,function(state,shot)
        local origin=shot.position or shot.origin
        if not origin then return end
        local direction=shot.direction or shot.dir or {x=0,y=0,z=-1}
        local source=shot.source or "player"
        for i=#state.flashes,1,-1 do if state.flashes[i].source==source then table.remove(state.flashes,i) end end
        local offset=shot.position and 0 or .35
        table.insert(state.flashes,1,{source=source,life=.06,
            position={x=origin.x+direction.x*offset,y=origin.y+direction.y*offset,z=origin.z+direction.z*offset}})
        while #state.flashes>2 do table.remove(state.flashes) end
    end)
    events.on(ctx.events, events.DAMAGE_DEALT, ctx.fx, function(state, hit)
        if hit.source == "player" and hit.target ~= "player" then
            state.hitmarker = 0.12
        end
    end)
    events.on(ctx.events, events.DAMAGE_TAKEN, ctx.fx, function(state)
        state.damage_flash = 0.2
    end)
end

function M.update(ctx, dt)
    for i=#ctx.fx.flashes,1,-1 do
        local flash=ctx.fx.flashes[i];flash.life=flash.life-dt
        if flash.life<=0 then table.remove(ctx.fx.flashes,i) end
    end
    ctx.fx.hitmarker = math.max(0, ctx.fx.hitmarker - dt)
    ctx.fx.damage_flash = math.max(0, ctx.fx.damage_flash - dt)
end

function M.final(ctx)
    events.off_owner(ctx.events, ctx.fx)
    ctx.fx = nil
end

return M
