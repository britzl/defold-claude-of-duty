-- All Defold sound/resource ownership is kept outside the pure Lua mixer.
local M = {}
local mt={__index=M}
function M.new(voice_factory,loop_factory)
    local a=setmetatable({voices={},sequence=0},mt)
    for i=1,72 do
        local id=factory.create(i>66 and loop_factory or voice_factory)
        a.voices[i]={id=id,url=msg.url(nil,id,"sound")}
    end
    a.silence=go.get(a.voices[1].url,"sound")
    return a
end
function M:load(key,wav)
    self.sequence=self.sequence+1
    return resource.create_sound_data("/generated/audio/"..self.sequence..".wavc",{data=wav})
end
function M:play(slot,handles,gain,pan,speed,done)
    local remaining=3
    for layer=1,3 do
        local v=self.voices[(slot-1)*3+layer]
        go.set(v.url,"sound",handles[layer])
        go.set(v.url,"gain",0);go.set(v.url,"pan",pan);go.set(v.url,"speed",speed)
        v.play_id=sound.play(v.url,nil,function(_,_,message)
            if v.play_id==message.play_id then v.play_id=nil end
            remaining=remaining-1
            if remaining==0 then done() end
        end)
    end
end
function M:mix(slot,gain,pan,weights)
    for layer=1,3 do
        local v=self.voices[(slot-1)*3+layer]
        go.set(v.url,"gain",gain*weights[layer]);go.set(v.url,"pan",pan*(layer==3 and .35 or 1))
    end
end
function M:stop(slot)
    for layer=1,3 do
        local v=self.voices[(slot-1)*3+layer]
        if v.play_id then sound.stop(v.url,{play_id=v.play_id}) end
    end
end
function M:occluded(from,to)
    local dx,dy,dz=to.x-from.x,to.y-from.y,to.z-from.z
    local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    if length<.1 then return false end
    local blocked=0
    for i=0,1 do
        local lift=i*.55;local start=vmath.vector3(from.x,from.y+lift,from.z)
        local finish=vmath.vector3(to.x,to.y+lift*.5,to.z)
        local delta=finish-start;local n=vmath.length(delta)
        if n>.1 and physics.raycast(start,finish-delta*(.06/n),{hash("world")}) then blocked=blocked+.5 end
    end
    return blocked

end
function M:meter()
    local left,right=sound.get_peak("game_audio",.1)
    return {left=left,right=right}
end
function M:final(resources)
    for i,v in ipairs(self.voices) do
        if v.play_id then sound.stop(v.url,{play_id=v.play_id}) end
        go.set(v.url,"sound",self.silence)
        go.delete(v.id)
    end
    for _,sample in pairs(resources) do resource.release(sample.handle) end
    self.voices={}
end
return M
