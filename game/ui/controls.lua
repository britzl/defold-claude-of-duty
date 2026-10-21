-- Settings and physical keyboard holds are independent of simulation buttons.
local input = require "game.input"
local M = {}
local defaults={sensitivity=1,touch_sensitivity=1,gamepad_sensitivity=1,fov=70,invert_look=false}
function M.defaults(state)
    for key,value in pairs(defaults) do state[key]=value end
end
function M.new()
    local state={held={},blocked={},stance="stand"}
    M.defaults(state)
    return state
end
function M.observe(state,name,action)
    if not name then return end
    if action.pressed then state.held[name]=true end
    if action.released then state.held[name],state.blocked[name]=nil,nil end
end
function M.quarantine(state)
    for name in pairs(state.held) do state.blocked[name]=true end
    state.stance="stand"
end
function M.allowed(state,name) return not state.blocked[name] end
function M.configure(state,value,key)
    key=key or "sensitivity"
    assert(defaults[key]~=nil,"Unknown input setting")
    if key=="invert_look" then assert(type(value)=="boolean","Invert look must be boolean")
    else
        local min,max=key=="fov" and 55 or .25,key=="fov" and 100 or 3
        assert(type(value)=="number" and value==value and value>=min and value<=max,"Input setting out of range")
    end
    state[key]=value
end
function M.button(state,buffer,name,action,source)
    source=source or "desktop"
    if name=="crouch" or name=="prone" then
        if action.pressed then
            state.stance=name=="crouch" and (state.stance=="crouch" and "stand" or "crouch")
                or (state.stance=="prone" and "crouch" or "prone")
            for _,stance in ipairs({"crouch","prone"}) do
                input.button(buffer,stance,{pressed=state.stance==stance,released=state.stance~=stance},source)
            end
        end
        return true
    end
    if action.pressed and (name=="jump" or name=="sprint") then
        state.stance="stand"
        input.button(buffer,"crouch",{released=true},source)
        input.button(buffer,"prone",{released=true},source)
    end
    return input.button(buffer,name,action,source)
end
return M
