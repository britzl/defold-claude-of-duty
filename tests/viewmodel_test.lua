-- Articulated first-person presentation and fixed-tick lifecycle contracts.
package.path='./?.lua;'..package.path
local runtime=require 'game.runtime'
local input=require 'game.input'
local weapons=require 'game.systems.weapons'
local player=require 'game.systems.player'
local geometry=require 'game.weapons.geometry'
local view=require 'game.weapons.viewmodel'
local arms=require 'game.weapons.arms'
local clips=require 'game.weapons.clips'
local defs=require 'game.weapons.defs'
local T=require 'game.ai.transform'
local V=require 'game.weapons.math'
local h,count=1/120,0
local function test(name,fn) fn();count=count+1;print('PASS '..name) end
local function near(a,b,e) assert(math.abs(a-b)<(e or 1e-8),tostring(a)..' != '..tostring(b)) end
local function ticks(ctx,n) for _=1,n do runtime.fixed_update(ctx,h) end;ctx.time.alpha=1 end
local function button(ctx,key,on) input.button(ctx.input,key,on and {pressed=true} or {released=true}) end
local models={};for id in pairs(defs) do models[id]=geometry.weapon(id) end
local function new(id)
    local ctx=runtime.new();ctx.world.ready=true;ctx.player.motion.grounded=true;ticks(ctx,80)
    if id and id~='rifle' then weapons.select(ctx,id);ticks(ctx,150) end
    return ctx
end
local function pose(ctx) return view.pose(ctx,models[ctx.weapons.equipped]) end
local function root(sample)
    local m=T.rotation(table.unpack(sample.rotation));m[4],m[8],m[12]=table.unpack(sample.position);return m
end
local function vector(p) return {x=p[1],y=p[2],z=p[3]} end
local function allnear(a,b)
    for k,v in pairs(a) do if type(v)=='table' then allnear(v,b[k]) elseif type(v)=='number' then near(v,b[k]) else assert(v==b[k],k) end end
end

test('shared arms have finite outward geometry, complete palettes and bounded allocation',function()
    local total=0
    for _,side in ipairs({-1,1}) do
        local b=arms.geometry(side);total=total+b.vertex_count
        assert(#b.joints==b.vertex_count and #b.positions==b.vertex_count*3)
        local seen={}
        for _,joint in ipairs(b.joints) do assert(joint>=0 and joint<17);seen[joint]=true end
        for j=0,16 do assert(seen[j]) end
        for i=1,#b.positions,9 do
            local p,n=b.positions,b.normals
            local u={x=p[i+3]-p[i],y=p[i+4]-p[i+1],z=p[i+5]-p[i+2]}
            local v={x=p[i+6]-p[i],y=p[i+7]-p[i+1],z=p[i+8]-p[i+2]}
            local area=(u.y*v.z-u.z*v.y)*n[i]+(u.z*v.x-u.x*v.z)*n[i+1]+(u.x*v.y-u.y*v.x)*n[i+2]
            assert(area>0,'inverted or degenerate arm triangle')
        end
    end
    assert(total<16000);print('ARMS vertices',total,'bytes',total*44)
end)

test('ADS sights align after cant, idle sway, lag and recoil on every weapon',function()
    for id,model in pairs(models) do
        local ctx=new(id);button(ctx,'aim',true);ticks(ctx,100)
        for i=1,50 do
            ctx.player.motion.yaw=ctx.player.motion.yaw+.004
            ticks(ctx,1)
            if i==20 then button(ctx,'fire',true) end
            local s=pose(ctx);local sight=T.point(root(s),vector(model.sight))
            near(sight.x,0);near(sight.y,0);near(sight.z,-defs[id].eyeRelief)
        end
        runtime.final(ctx)
    end
end)

test('IK keeps shoulders body-fixed and wrists welded throughout all clip poses',function()
    local maxstretch=0
    for id,model in pairs(models) do
        local ctx=new(id);local w=ctx.weapons
        for _,clip in ipairs({'idle','reloadTac','reloadEmpty','inspect','draw','holster'}) do
            for i=0,100 do
                w.clip=clip~='idle' and clip or nil;w.previous_clip=nil;w.clip_time=i/100;w.clip_duration=1
                local s=pose(ctx);local r=root(s)
                for _,side in ipairs({'left','right'}) do
                    local p=s.arms[side];local j=s.joints[side]
                    assert(#p==17)
                    local shoulder=T.point(p[1],{x=0,y=0,z=0})
                    local elbow=T.point(p[1],{x=0,y=0,z=-.33})
                    local wrist=T.point(p[2],{x=0,y=0,z=-.30})
                    for _,axis in ipairs({'x','y','z'}) do
                        near(shoulder[axis],j.shoulder[axis]);near(elbow[axis],j.elbow[axis]);near(wrist[axis],j.wrist[axis])
                    end
                    maxstretch=math.max(maxstretch,j.stretch)
                    for _,m in ipairs(p) do for _,v in ipairs(m) do assert(v==v and math.abs(v)<5) end end
                end
                local expected=T.point(r,vector(model.right))
                for _,axis in ipairs({'x','y','z'}) do near(expected[axis],s.joints.right.wrist[axis]) end
            end
        end
        runtime.final(ctx)
    end
    assert(maxstretch<1.20,maxstretch);print('IK maximum length correction',maxstretch)
end)

test('IK remains finite at coincident, fully extended and pole-aligned targets',function()
    for _,side in ipairs({-1,1}) do for _,point in ipairs({{x=0,y=0,z=0},{x=0,y=0,z=-2},
        {x=side*.46,y=-.86,z=.22},{x=0,y=.00001,z=0}}) do
        local a,b,elbow=arms.solve({x=0,y=0,z=0},point,{x=0,y=1,z=0},side)
        for _,m in ipairs({a,b}) do for _,v in ipairs(m) do assert(v==v and math.abs(v)<10) end end
        local wrist=T.point(b,{x=0,y=0,z=-.30})
        for _,axis in ipairs({'x','y','z'}) do near(wrist[axis],point[axis]) end
    end end
end)

test('collimated dots stay on the shot axis while optics lag; empty slides hide their dot',function()
    for id,model in pairs(models) do
        local ctx=new(id);button(ctx,'aim',true);ticks(ctx,90)
        for _=1,60 do
            ctx.player.motion.yaw=ctx.player.motion.yaw+.03;ticks(ctx,1)
            local p=pose(ctx);local local_dot={}
            for i=1,3 do local_dot[i]=model.reticle[i]+p.parts.reticle.position[i] end
            local dot=T.point(root(p),vector(local_dot));near(dot.x,0);near(dot.y,0)
            assert(dot.z<0 and p.parts.reticle.visible)
        end
        if id=='pistol' then ctx.weapons.inventory.pistol.chambered=false;assert(not pose(ctx).parts.reticle.visible) end
        runtime.final(ctx)
    end
end)

test('magazine follows the grasp, seats at transfer and charging hand follows the handle',function()
    for id,model in pairs(models) do for _,clip in ipairs({'reloadTac','reloadEmpty'}) do
        local d=defs[id];local pull=clip=='reloadTac' and .20 or .16;local seat=clip=='reloadTac' and .81 or .71
        local initial=clips.sample(clip,pull,model,d)
        for i=0,30 do
            local t=pull+(seat-pull)*i/30;local p=clips.sample(clip,t,model,d)
            for j=1,3 do near(p.left.position[j]-p.mag_position[j],initial.left.position[j]) end
        end
        local seated=clips.sample(clip,seat,model,d)
        for j=1,3 do near(seated.mag_position[j],0) end
        assert(seated.mag_visible)
        if clip=='reloadEmpty' then
            local pullhand=clips.sample(clip,.90,model,d)
            near(pullhand.left.position[3],model.charge[3]+(id=='pistol' and .035 or .065))
            near(pullhand.charge,1)
        end
    end end
end)

test('stationary and blocked movement do not advance bob; actual travel does',function()
    local ctx=new();local s=ctx.weapons.motion;local phase=s.phase
    ctx.player.motion.velocity.z=-4;ticks(ctx,60);near(s.phase,phase)
    ctx.player.motion.travel=.02;ticks(ctx,100);assert(s.phase>phase+1)
    local now=s.phase;ctx.player.motion.grounded=false;ticks(ctx,20);near(s.phase,now)
    ctx.player.motion.grounded=true;ctx.player.motion.sliding=true;ticks(ctx,20);near(s.phase,now)
    runtime.final(ctx)
end)

test('lag is bounded, settles, and teleport resets the follow history',function()
    local ctx=new();local s=ctx.weapons.motion
    for _=1,80 do ctx.player.motion.yaw=ctx.player.motion.yaw+.07;ticks(ctx,1) end
    assert(s.lag.x.x<-.01 and s.lag.yaw.x>.05)
    for _,spring in pairs(s.lag) do assert(math.abs(spring.x)<.5) end
    ticks(ctx,400);assert(math.abs(s.lag.x.x)<.001)
    player.reset(ctx,{x=0,y=0,z=0},2.8);near(ctx.weapons.motion.lag.x.x,0)
    ticks(ctx,1);near(ctx.weapons.motion.av_yaw,0)
    runtime.final(ctx)
end)

test('pause freezes all matrices and reload ammo; inspection/death stop the motion clock',function()
    local ctx=new();ctx.weapons.inventory.rifle.mag=1
    button(ctx,'reload',true);ticks(ctx,90);button(ctx,'reload',false)
    local before=pose(ctx);local time=ctx.weapons.clip_time
    runtime.set_paused(ctx,true)
    for _=1,30 do runtime.fixed_update(ctx,h);runtime.update(ctx,.1) end
    allnear(before,pose(ctx));near(ctx.weapons.clip_time,time);assert(ctx.weapons.inventory.rifle.mag==1)
    runtime.set_paused(ctx,false);ticks(ctx,300);assert(ctx.weapons.inventory.rifle.mag==30)
    ctx.player.enabled=false;local clock=ctx.weapons.motion.time;ticks(ctx,50);near(ctx.weapons.motion.time,clock)
    ctx.player.enabled=true;ctx.player.actor.alive=false;ticks(ctx,50);near(ctx.weapons.motion.time,clock)
    runtime.final(ctx)
end)

test('firing interrupts inspection smoothly without delaying the shot or changing rounds',function()
    local ctx=new();button(ctx,'inspect',true);ticks(ctx,90);button(ctx,'inspect',false)
    local before=pose(ctx);button(ctx,'fire',true);ticks(ctx,1)
    assert(ctx.weapons.clip==nil and ctx.weapons.sim.fired==1 and ctx.weapons.clip_transition)
    local after=pose(ctx)
    for i=1,3 do assert(math.abs(after.position[i]-before.position[i])<.005) end
    button(ctx,'fire',false);ticks(ctx,30);assert(not ctx.weapons.clip_transition)
    runtime.final(ctx)
end)

test('interpolated arm and weapon transforms agree at 30, 60 and 144 presentation FPS',function()
    local reference
    for _,fps in ipairs({30,60,144}) do
        local ctx=new('smg');local acc=0
        for _=1,fps*2 do
            acc=acc+1/fps
            while acc+1e-10>=h do
                ctx.player.motion.yaw=ctx.player.motion.yaw+.002
                ctx.player.motion.travel=.015
                runtime.fixed_update(ctx,h);acc=acc-h
            end
            runtime.update(ctx,1/fps);pose(ctx)
        end
        ctx.time.alpha=.37;local result=pose(ctx)
        if reference then allnear(reference,result) else reference=result end
        runtime.final(ctx)
    end
end)
print(count..' viewmodel tests passed')
