-- Shared native-extension parity suite for host Lua, Defold and WebAssembly.
local rig=require "game.ai.rig"
local animation=require "game.ai.animation"
local T=require "game.ai.transform"
local variants=require "game.ai.variants"
local M={}
local function clone(t)
    if type(t)~="table" then return t end
    local out={};for k,v in pairs(t) do out[k]=clone(v) end;return out
end
function M.run()
    assert(soldierpose,"Native pose tests require the extension")
    local previous_backend=rig.backend();rig.set_backend("native")
    local report={poses=0,comparisons=0,max_error=0,tolerance=1e-7,ownership_checks=0}
    local function near(a,b,label)
        assert(type(a)=="number" and type(b)=="number",label.." missing value")
        local error=math.abs(a-b)
        assert(error<=report.tolerance,string.format("%s: native %.17g Lua %.17g (error %.9g)",label,a,b,error))
        report.max_error=math.max(report.max_error,error);report.comparisons=report.comparisons+1
    end
    local function compare(a,b,label)
        if type(b)=="number" then near(a,b,label)
        elseif type(b)=="table" then for k,v in pairs(b) do compare(a[k],v,label.."/"..k) end
        else assert(a==b,label.." differs") end
    end
    local function check(state,native,reference,consumers)
        local old_palette,old_worlds=native.palette,native.worlds
        local p,w=rig.pose(state,native);local ep,ew=rig.pose_lua(state,reference)
        if old_palette then assert(p==old_palette and w==old_worlds,"Outputs must reuse caller buffers") end
        compare(p,ep,"palette");compare(w,ew,"worlds")
        for _,key in ipairs({"support_error","reach_drop","support_target","weapon_frame"}) do compare(native[key],reference[key],key) end
        if consumers then
            local position={x=17,y=.3,z=-11};local yaw=.7
            compare(rig.volumes(p,position,yaw,"actor",state.variant),rig.volumes(ep,position,yaw,"actor",state.variant),"hit volumes")
            compare(rig.joint_frames(w),rig.joint_frames(ew),"ragdoll joints")
            compare(T.point(p[rig.index.HandR],variants.muzzle(state.variant)),T.point(ep[rig.index.HandR],variants.muzzle(state.variant)),"weapon socket")
        end
        report.poses=report.poses+1
    end
    local feet={R={target={x=.103,y=.088,z=.022},normal={x=.1,y=.99,z=.02},weight=1,stance=true},
        L={target={x=-.103,y=.18,z=-.1},normal={x=-.2,y=.97,z=.1},weight=.65,stance=false}}
    for _,variant in ipairs(variants.order) do
        for _,clip in ipairs({"idle","walk","run","crouch","reload","vault","throw","wounded","head","arm","leg","torso","death","feet"}) do
            local native,reference={},{}
            for i=0,40 do
                local t=i/40;local s={variant=variant,time=t*4,phase=t*math.pi*2,aim=1,
                    pitch=math.sin(t*6)*.6,aim_yaw=math.cos(t*6)*.75}
                if clip=="walk" or clip=="run" then s.walk=1;s.run=clip=="run" and 1 or 0 end
                if clip=="crouch" then s.walk=1;s.crouch=t end
                if clip=="reload" or clip=="vault" or clip=="throw" then s[clip]=t;s[clip.."_weight"]=1 end
                if clip=="wounded" then s.wounded=1 end
                if clip=="head" or clip=="arm" or clip=="leg" or clip=="torso" then s.hit_region=clip;s.hit=.6;s.hit_side=i%2==0 and 1 or -1 end
                if clip=="death" then s.death=t;s.walk=1;s.crouch=.4 end
                if clip=="feet" then s.feet=clone(feet);s.feet.R.weight=t;s.walk=.5;s.crouch=.3;s.pelvis=-.1 end
                check(s,native,reference,i%10==0)
            end
        end
    end
    -- Deterministic mixed layers exercise transitions and nontrivial support,
    -- including in-place mutations rather than fresh state-table identities.
    local seed=19
    local function random() seed=(seed*16807)%2147483647;return seed/2147483647 end
    local s={feet=clone(feet)};local native,reference={},{}
    for i=1,600 do
        s.variant=variants.order[i%3+1];s.time=i/60;s.phase=random()*20;s.walk=random();s.run=random();s.aim=random()
        s.crouch=random();s.wounded=random();s.death=i%5==0 and random() or 0
        s.pitch=(random()-.5)*2;s.aim_yaw=(random()-.5)*2;s.recoil=random();s.pelvis=-random()*.2
        s.hit=random();s.hit_side=i%2==0 and 1 or -1;s.hit_region=({"head","arm","leg","torso"})[i%4+1]
        for _,clip in ipairs({"reload","vault","throw","turn"}) do s[clip]=random();s[clip.."_weight"]=random() end
        s.turn_direction=s.hit_side
        s.vault_hand=i%2==0 and {x=-.2,y=1,z=-.3} or nil
        for _,side in ipairs({"R","L"}) do s.feet[side].target.y=random()*.3;s.feet[side].weight=random() end
        check(s,native,reference,i%30==0)
        if i%10==0 then
            local next_state=clone(s);next_state.reload_weight=0;next_state.vault_weight=0
            check(animation.interpolate(s,next_state,.37),native,reference,true)
        end
    end
    for _,state in ipairs({{}, {variant="unknown"},{feet={R={weight=0}}},
        {feet={R={target={x=.103,y=.088,z=.022},weight=1}}},
        {turn=1,turn_weight=1,turn_direction=-1},{death=1,throw=.5,throw_weight=1}}) do check(state,{}, {},true) end

    s={variant="irregular",time=.75,crouch=.5,aim=1,feet=clone(feet)};native={};reference={}
    check(s,native,reference,true)
    local p,w=native.palette,native.worlds;local held_p,held_w=clone(p),clone(w)
    local stats=soldierpose.stats(native.native_pose)
    for _=1,8 do check(s,native,reference,false) end
    local now=soldierpose.stats(native.native_pose)
    assert(now.evaluations==stats.evaluations and now.reuses==stats.reuses+8,"Unchanged poses must reuse the complete native result")
    report.context_bytes=now.bytes
    s.feet.R.target.x=s.feet.R.target.x+.001;check(s,native,reference,true)
    assert(soldierpose.stats(native.native_pose).evaluations==stats.evaluations+1,"In-place target edit was missed")
    local snapshot_p,snapshot_w=clone(p),clone(w)
    for i=1,16 do rig.pose({variant="breacher",time=i,death=i/16},{}) end
    compare(p,snapshot_p,"independent palette");compare(w,snapshot_w,"independent worlds")
    assert(p~=held_p and w~=held_w)
    -- Input validation, closed handles, failed calls and abandoned contexts.
    for _,bad in ipairs({{time=0/0},{phase=math.huge},{walk="bad"},{feet={R={weight=1}}},{vault_hand={x=0,y=0}}}) do
        assert(not pcall(rig.pose,bad,native),"Malformed state accepted")
    end
    check(s,native,reference,true)
    soldierpose.close(native.native_pose);soldierpose.close(native.native_pose)
    assert(not pcall(rig.pose,s,native),"Closed context accepted evaluation")
    compare(p,snapshot_p,"outputs survive close");compare(w,snapshot_w,"worlds survive close")
    for _=1,32 do rig.pose(s,{}) end
    collectgarbage("collect")
    report.ownership_checks=7
    rig.set_backend(previous_backend)
    local message="NATIVE_POSE_TEST PASS "..(json and json.encode(report) or string.format("%d poses, %d values, max error %.9g",report.poses,report.comparisons,report.max_error))
    if html5 then html5.run("console.log("..json.encode(message)..")") else print(message) end
    return report
end
return M
