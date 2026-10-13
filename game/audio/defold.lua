-- All Defold sound/resource ownership is kept outside the pure Lua mixer.
local M = {}
local mt={__index=M}
function M.new(voice_factory,loop_factory)
    local a=setmetatable({voices={},sequence=0},mt)
    for i=1,24 do
        local id=factory.create(i>22 and loop_factory or voice_factory)
        a.voices[i]={id=id,url=msg.url(nil,id,"sound")}
    end
    a.silence=go.get(a.voices[1].url,"sound")
    return a
end
function M:load(key,wav)
    self.sequence=self.sequence+1
    return resource.create_sound_data("/generated/audio/"..self.sequence..".wavc",{data=wav})
end
function M:play(slot,handle,gain,pan,speed,done)
    local v=self.voices[slot]
    go.set(v.url,"sound",handle)
    go.set(v.url,"gain",gain);go.set(v.url,"pan",pan);go.set(v.url,"speed",speed)
    v.play_id=sound.play(v.url,nil,function(_,_,message)
        if v.play_id==message.play_id then v.play_id=nil end
        done()
    end)
end
function M:mix(slot,gain,pan)
    local v=self.voices[slot]
    go.set(v.url,"gain",gain);go.set(v.url,"pan",pan)
end
function M:stop(slot)
    local v=self.voices[slot]
    if v.play_id then sound.stop(v.url,{play_id=v.play_id}) end
end
function M:occluded(from,to)
    local dx,dy,dz=to.x-from.x,to.y-from.y,to.z-from.z
    local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    if length<.1 then return false end
    -- Stop short of an impact's own surface so it does not occlude itself.
    local t=1-.06/length
    return physics.raycast(vmath.vector3(from.x,from.y,from.z),
        vmath.vector3(from.x+dx*t,from.y+dy*t,from.z+dz*t),{hash("world")})~=nil
end
function M:meter()
    local left,right=sound.get_peak("game_audio",.1)
    return {left=left,right=right}
end
function M:final(resources)
    for i,v in ipairs(self.voices) do
        self:stop(i)
        go.set(v.url,"sound",self.silence)
        go.delete(v.id)
    end
    for _,sample in pairs(resources) do resource.release(sample.handle) end
    self.voices={}
end
return M
