-- A bounded automation input recording, replayed through ordinary buffered
-- buttons before the fixed tick. Results freeze at the final requested tick.
local input = require "game.input"
local weapons = require "game.systems.weapons"
local M = {}
local allowed={fire=true,aim=true,reload=true,inspect=true,fire_mode=true,next_weapon=true,
    weapon_rifle=true,weapon_smg=true,weapon_pistol=true,sprint=true,forward=true,crouch=true}
function M.new(segments)
    assert(type(segments)=="table" and #segments>0 and #segments<=64,"Expected 1-64 segments")
    local total=0
    local copy={}
    for _,s in ipairs(segments) do
        assert(type(s.ticks)=="number" and s.ticks>=1 and s.ticks==math.floor(s.ticks),"Invalid ticks")
        total=total+s.ticks
        local item={ticks=s.ticks}
        for key,value in pairs(s) do
            if key~="ticks" then
                assert(allowed[key] and type(value)=="boolean","Unknown or invalid input "..key)
                item[key]=value
            end
        end
        copy[#copy+1]=item
    end
    assert(total<=2400,"Weapon drive is limited to 2400 ticks")
    return {segments=copy,index=1,tick=0,complete=false}
end
function M.before(ctx,drive)
    if drive.complete then return end
    local s=drive.segments[drive.index]
    for key in pairs(allowed) do
        local held=ctx.input.buttons[key].held
        if s[key] and not held then input.button(ctx.input,key,{pressed=true}) end
        if not s[key] and held then input.button(ctx.input,key,{released=true}) end
    end
end
function M.after(ctx,drive)
    if drive.complete then return end
    drive.tick=drive.tick+1
    if drive.tick==drive.segments[drive.index].ticks then
        drive.tick=0;drive.index=drive.index+1
        if drive.index>#drive.segments then
            drive.complete=true;drive.result=weapons.snapshot(ctx);input.reset(ctx.input)
        end
    end
end
return M
