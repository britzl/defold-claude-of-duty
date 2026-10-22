-- Whole-game presentation policy. Never changes simulation, AI or physics.
local M={names={"low","medium","high","ultra"},target_fps=60}
local presets={
    low={render_scale=.6,shadow_resolution=256,material_lod=2,effect_density=.35,decal_limit=12,
        photographic_quality="low",ambient_occlusion=false,contact_shadows=false,reflections=false,
        local_shadows=false,volumetric_fog=false,fog_shadows=false,heat_distortion=false,
        micro_detail=false,parallax=false,motion_blur=0,ads_dof=0},
    medium={render_scale=.8,shadow_resolution=512,material_lod=1,effect_density=.65,decal_limit=24,
        photographic_quality="medium",ambient_occlusion=true,contact_shadows=false,reflections=false,
        local_shadows=false,volumetric_fog=true,fog_shadows=false,heat_distortion=false,
        micro_detail=true,parallax=false,motion_blur=0,ads_dof=1},
    high={render_scale=1,shadow_resolution=1024,material_lod=0,effect_density=1,decal_limit=48,
        photographic_quality="high",ambient_occlusion=true,contact_shadows=true,reflections=true,
        local_shadows=true,volumetric_fog=true,fog_shadows=true,heat_distortion=true,
        micro_detail=true,parallax=true,motion_blur=.15,ads_dof=1},
    ultra={render_scale=1,shadow_resolution=2048,material_lod=0,effect_density=1,decal_limit=48,
        photographic_quality="high",ambient_occlusion=true,contact_shadows=true,reflections=true,
        local_shadows=true,volumetric_fog=true,fog_shadows=true,heat_distortion=true,
        micro_detail=true,parallax=true,motion_blur=.15,ads_dof=1},
}
local common={shadow_cache=true,local_shadow_cache=true,interior_lighting=true,environment_filter=true,shadows=true,normal_maps=true,local_lights=true,fog=true,bloom=true,glass=true,
    muzzle_lights=true,temporal_aa=true,weapon_aa=true,combat_materials=true,combat_effects=true,
    soft_particles=true,impact_decals=true,weathering=true,auto_exposure=true,clouds=true,cloud_shadows=true}
function M.preset(name)
    local p=assert(presets[name],"Unknown quality preset")
    local result={};for k,v in pairs(common) do result[k]=v end
    for k,v in pairs(p) do result[k]=v end
    return result
end
function M.owns(key) return common[key]~=nil or presets.high[key]~=nil end
local function reset(s,settle)
    s.elapsed,s.frames,s.slow,s.bad,s.good=0,0,0,0,0
    s.settle=settle or 3
end
function M.new(mode,target)
    target=target or M.target_fps
    assert(target>=30 and target<=240 and target==target,"Invalid frame target")
    local s={mode="auto",active="high",target_fps=target,changes=0,time=0,upgrade_after=0,backoff=120,reason="startup"}
    M.select(s,mode or "auto")
    return s
end
function M.select(s,mode)
    assert(mode=="auto" or mode=="custom" or presets[mode],"Unknown quality mode")
    s.mode=mode
    if mode~="custom" then s.active=mode=="auto" and "high" or mode end
    s.reason="manual";s.upgrade_after=0;s.backoff=120;s.probe=false
    reset(s,5)
    return mode~="custom" and M.preset(s.active) or nil
end
function M.snapshot(s)
    return {mode=s.mode,active=s.active,target_fps=s.target_fps,changes=s.changes,
        frame_ms=s.frame_ms or 0,reason=s.reason}
end
-- Supply wall-clock intervals, not engine dt (which may be capped).
-- Two bad windows lower one tier. Twenty good seconds probe one tier upward.
-- Failed probes back off; menus/loading/captures cannot bias the next window.
function M.sample(s,dt,active)
    if not active or not dt or dt~=dt or dt<=0 or dt>1 then reset(s);return end
    s.time=s.time+dt
    if s.mode~="auto" then return end
    if s.settle>0 then s.settle=s.settle-dt;return end
    s.elapsed=s.elapsed+dt;s.frames=s.frames+1
    local budget=1/s.target_fps
    if dt>budget*1.15 then s.slow=s.slow+1 end
    if s.elapsed<2 then return end
    local mean=s.elapsed/s.frames;local slow=s.slow/s.frames
    s.frame_ms=mean*1000
    s.bad=(mean>budget*1.12 or slow>.15) and s.bad+1 or 0
    s.good=(mean<=budget*1.035 and slow<.02) and s.good+1 or 0
    s.elapsed,s.frames,s.slow=0,0,0
    local index;for i,name in ipairs(M.names) do if name==s.active then index=i end end
    local next_index
    if s.bad>=2 and index>1 then
        next_index=index-1;s.reason="over_budget"
        if s.probe then s.backoff=math.min(960,s.backoff*2) end
        s.upgrade_after=s.time+s.backoff;s.probe=false
    elseif s.good>=10 and index<#M.names and s.time>=s.upgrade_after then
        next_index=index+1;s.reason="headroom_probe";s.probe=true
    end
    if not next_index then return end
    s.active=M.names[next_index];s.changes=s.changes+1;reset(s,3)
    return M.preset(s.active)
end
return M
