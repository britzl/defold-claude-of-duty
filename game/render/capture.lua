-- Versioned camera contract; no simulation, clocks or random numbers.
local M = { version = 11, width = 1280, height = 720, settle_frames = 40,
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
        reference="sunset", requested_hour=19.2, lighting="sunset", purpose="Spectral sunset colour, low sun and distance contrast." },
    { id="night", position={0,1.66,10}, target={0,1.66,-8}, fov=75,
        reference="night", requested_hour=1.5, lighting="night", purpose="Moon phase, cool night fill and warm local light." },
    { id="laboratory", position={6.8,4.2,9.5}, target={0,1.3,-1}, fov=65,
        laboratory=true, reference=false, purpose="Fifteen surface recipes, dielectric/metal roughness rows and furniture contact." },
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
for _,entry in ipairs({{"metal_brushed",3.6},{"fabric",6}}) do
    shots[#shots+1]={id="material_"..entry[1],position={entry[2],2,-2.4},target={entry[2],2,-5.3},fov=45,
        laboratory=true,reference=false,purpose="Reference recipe close-up: sheen, grain and filtering."}
end
shots[#shots+1]={id="shadow_cutout",position={5,3.8,7},target={2,1.1,3},fov=58,
    laboratory=true,reference=false,purpose="Matching perforated panel and shadow silhouette; near-cascade contact/softness."}
shots[#shots+1]={id="shadow_distance",position={0,3,27},target={0,1.5,-30},fov=65,
    reference=false,purpose="All four cascades, near/distant coverage and blended boundaries in motion."}
shots[#shots+1]={id="shadow_remote",position={164,4,7},target={160,.5,0},fov=65,
    laboratory=true,reference=false,purpose="Camera-following shadows at a fixture 160 m outside the old fixed map."}
shots[#shots+1]={id="contact_furniture",position={7.5,1.7,5.3},target={4.8,.4,2.1},fov=60,
    laboratory=true,reference=false,purpose="Table legs, near-ground contacts and silhouette rejection."}
shots[#shots+1]={id="contact_corner",position={-4.1,1.8,.2},target={-6.7,.5,-3.6},fov=65,
    laboratory=true,reference=false,purpose="Stacked boxes and floor/wall contact without black halos."}
shots[#shots+1]={id="reflections",position={42,1.35,5.5},target={42,.4,-2},fov=65,
    laboratory=true,reference=false,purpose="Smooth metal reflects the visible box, with edge fade and roughness fallback."}
shots[#shots+1]={id="glass",position={43.5,1.8,5.5},target={42,1.2,-2},fov=55,
    laboratory=true,reference=false,purpose="Two overlapping thin panes, opaque occlusion and sorted linear transparency."}
shots[#shots+1]={id="local_lights",position={56,3,4},target={54,.3,-1.5},fov=65,
    laboratory=true,reference=false,purpose="Two bounded point-light shadow cubemaps and occluder contact."}
local extra=require("game.render.laboratory").extra_materials
for i,name in ipairs(extra) do
    local x=8.4+i*2.4
    shots[#shots+1]={id="material_"..name,position={x,2,-2.4},target={x,2,-5.3},fov=45,
        laboratory=true,reference=false,purpose="Reference "..name.." recipe: physical scale, relief, roughness and filtering."}
end
for _,shot in ipairs({
    {id="materials_extended",position={20,4.6,7},target={20,2,-5.3},fov=80},
    {id="materials_far",position={20,5,22},target={20,2,-5.3},fov=65},
    {id="laboratory_far",position={0,5,20},target={0,2,-5.3},fov=65},
    {id="weathering_facade",position={-20,2.1,2},target={-20,2.1,-5.3},fov=75},
    {id="weathering_close",position={-24.8,2.8,-3.9},target={-25.9,3.7,-5.3},fov=50},
    {id="weathering_far",position={-20,3,15},target={-20,2,-5.3},fov=65},
    {id="micro_detail",position={-5.8,2,-4.75},target={-6,2,-5.3},fov=50},
    {id="parallax_tile",position={16.25,2,-4.8},target={15.2,2,-5.3},fov=55},
}) do
    shot.laboratory=true;shot.reference=false
    shot.purpose="Near/mid/far filtering, anchored weathering and bounded relief."
    shots[#shots+1]=shot
end

shots[#shots+1]={id="window_shafts",position={82,1.7,2.5},target={79.8,1.4,-3.8},fov=65,
    laboratory=true,reference=false,lighting="sunset",clouds=false,purpose="Real window aperture, mullion and shadowed room air."}
shots[#shots+1]={id="sky_daylight",position={0,12,10},target={0,28,-30},fov=65,reference=false,
    purpose="Atmospheric sky and two procedural cloud decks."}
shots[#shots+1]={id="sky_sunset",position={0,12,10},target={0,16,-30},fov=65,reference=false,lighting="sunset",
    purpose="Low solar disc, warm cumulus and thin high cloud."}
shots[#shots+1]={id="sky_night",position={0,12,10},target={-6,28,-30},fov=65,reference=false,lighting="night",
    purpose="Phased lunar disc, stars and cloud occlusion."}
shots[#shots+1]={id="moon",position={0,12,10},target={-7.6,28,-30},fov=20,reference=false,lighting="night",clouds=false,
    purpose="Clear-sky lunar terminator and stable stars at fixed exposure."}
for _,weapon in ipairs({"rifle","smg","pistol"}) do
    for _,pose in ipairs({"hip","ads"}) do
        shots[#shots+1]={id=weapon.."_"..pose,position={0,1.66,10},target={0,1.66,-8},fov=pose=="ads" and 58 or 80,
            weapon=pose,weapon_id=weapon,reference=false,purpose="Generated weapon surfaces and readable sights."}
    end
end
shots[#shots+1]={id="weapon_indoor",position={-14.5,1.805,-3.2},target={-6.5,1.805,0},fov=80,
    weapon="hip",reference=false,purpose="Weapon indirect light follows the camera into a dark interior."}
shots[#shots+1]={id="weapon_fire",position={0,1.66,10},target={0,1.66,-8},fov=80,
    weapon="hip",firing=true,reference=false,purpose="Emissive feathered flash and isolated viewmodel coverage."}
shots[#shots+1]={id="combat_effects",position={0,1.1,8.2},target={.1,.1,6.3},fov=60,
    combat_fixture=true,reference=false,purpose="Soft smoke intersection, surface decals and world flash."}
shots[#shots+1]={id="combat_glass",position={43.5,1.8,5.5},target={42,1.2,-2},fov=55,
    laboratory=true,combat_fixture="glass",reference=false,purpose="Glass and smoke share depth sorting in front of, between and behind panes."}
local function copy(t)
    if type(t)~="table" then return t end
    local result={};for k,v in pairs(t) do result[k]=copy(v) end;return result
end
function M.catalog()
    return {version=M.version, width=M.width, height=M.height, settle_frames=M.settle_frames,
        sweep_frames=M.sweep_frames, sweep_fps=M.sweep_fps, shots=copy(shots),
        world_clip={near=.1,far=500},
        lighting={mode="fixed_presets",sun_direction=copy(require("game.render.daylight").sun_direction),rig=require("game.render.daylight").snapshot(),exposure=1,
            presets={"daylight","sunset","night"},reference_daylight_hour=16.5,north_rotation_degrees=61,matched_time_of_day=false},
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
