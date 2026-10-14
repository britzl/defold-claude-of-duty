-- Versioned camera contract; no simulation, clocks or random numbers.
local M = { version = 3, width = 1280, height = 720, settle_frames = 32,
    sweep_frames = 121, sweep_fps = 30 }
local shots = {
    { id="street", position={0,1.66,10}, target={0,1.66,-8}, fov=75,
        reference="hero", purpose="Overall colour, lighting, material scale and shadow depth." },
    { id="interior", position={-14.5,1.805,-3.2}, target={-6.5,1.805,0}, fov=70,
        reference="interior", purpose="Interior fill, contact depth and bright doorway." },
    { id="detail", position={-5.1,1.45,2.4}, target={-6.5,1.4,1.9}, fov=45,
        reference="detail", purpose="Plaster/trim relief, tiling, weathering and filtering." },
    { id="courtyard", position={-7.8,1.66,7.4}, target={-22,1.5,7.4}, fov=70,
        reference=false, purpose="Ground, shade and contact under the west courtyard walls." },
    { id="weapon", position={0,1.66,10}, target={0,1.66,-8}, fov=80,
        reference="weapon", weapon="hip", purpose="World/viewmodel light balance and weapon materials." },
    { id="ads", position={0,1.66,10}, target={0,1.66,-8}, fov=58,
        reference="ads", weapon="ads", purpose="Sight readability, edge stability and weapon exposure." },
    { id="sunset", position={0,1.66,10}, target={0,1.66,-8}, fov=65,
        reference="sunset", requested_hour=19.2, unsupported="Time-of-day lighting is not implemented (rendering step 10)." },
    { id="night", position={0,1.66,10}, target={0,1.66,-8}, fov=75,
        reference="night", requested_hour=1.5, unsupported="Time-of-day lighting is not implemented (rendering step 10)." },
    { id="laboratory", position={6.8,4.2,9.5}, target={0,1.3,-1}, fov=65,
        laboratory=true, reference=false, purpose="Six current surface recipes, dielectric/metal roughness rows and furniture contact." },
    { id="material_plaster", position={-6,2,-2.4}, target={-6,2,-5.3}, fov=45,
        laboratory=true, reference=false, purpose="Plaster trowel relief, pinholes and coating variation at close range." },
    { id="material_concrete", position={-3.6,2,-2.4}, target={-3.6,2,-5.3}, fov=45,
        laboratory=true, reference=false, purpose="Concrete aggregate, pores, formwork and tie holes." },
    { id="material_asphalt", position={-1.2,2,-2.4}, target={-1.2,2,-5.3}, fov=45,
        laboratory=true, reference=false, purpose="Asphalt binder, aggregate, patches and roughness." },
    { id="material_wood", position={1.2,2,-2.4}, target={1.2,2,-5.3}, fov=45,
        laboratory=true, reference=false, purpose="Wood planks, grain, knots, joints and nails." },
    { id="material_grazing", position={0,.3,4}, target={0,.1,-8}, fov=70,
        reference=false, purpose="Road minification and grazing-angle filtering." },
}
local function copy(t)
    if type(t)~="table" then return t end
    local result={};for k,v in pairs(t) do result[k]=copy(v) end;return result
end
function M.catalog()
    return {version=M.version, width=M.width, height=M.height, settle_frames=M.settle_frames,
        sweep_frames=M.sweep_frames, sweep_fps=M.sweep_fps, shots=copy(shots),
        world_clip={near=.1,far=500},
        lighting={mode="fixed_daylight",sun_direction={-.6,.85,.4},exposure=1,
            reference_daylight_hour=16.5, matched_time_of_day=false},
        comparison="Adapted framing in the unrotated partial map; not cross-engine pixel equality."}
end
function M.select(id)
    for _,shot in ipairs(shots) do
        if shot.id==id then assert(not shot.unsupported,shot.unsupported);return copy(shot) end
    end
    error("Unknown capture shot: "..tostring(id))
end
function M.camera(shot,frame)
    frame=frame or 0
    assert(type(frame)=="number" and frame==math.floor(frame) and frame>=0 and frame<M.sweep_frames,"Invalid sweep frame")
    local p=copy(shot.position)
    -- A four-second, 1.2 m lateral track; frame addressing is independent of FPS.
    p[1]=p[1]+1.2*frame/(M.sweep_frames-1)
    local dx,dy,dz=shot.target[1]-p[1],shot.target[2]-p[2],shot.target[3]-p[3]
    local horizontal=math.sqrt(dx*dx+dz*dz)
    local atan2=math.atan2 or math.atan
    return {position={x=p[1],y=p[2],z=p[3]},yaw=atan2(-dx,-dz),
        pitch=atan2(dy,horizontal),fov=math.rad(shot.fov)}
end
return M
