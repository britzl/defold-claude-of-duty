package.path='./?.lua;'..package.path
local animation=require 'game.ai.animation'
local IK=require 'game.ai.ik'
local T=require 'game.ai.transform'
local rig=require 'game.ai.rig'
local function copy(t)
    if type(t)~='table' then return t end
    local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
end
local function equal(a,b)
    if type(a)~='table' then assert(a==b,tostring(a)..' != '..tostring(b));return end
    for k,v in pairs(a) do equal(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil,'Unexpected key '..k) end
end
local count=0
local function test(name,f) f();count=count+1;print('PASS '..name) end
local function actor()
    local e={variant='vanguard',position={x=0,y=0,z=0},yaw=0,phase=0,run=0,
        actor={alive=true,health=100,max_health=100}}
    animation.init(e);return e
end
local function floor()
    local q={revision=0,calls=0,height=0,ny=1,hit={}}
    function q:clearance_revision() return self.revision end
    function q:ray(p)
        self.calls=self.calls+1
        if self.during_ray then self:during_ray() end
        if self.miss then return end
        local hit=self.hit
        hit.x,hit.y,hit.z=p.x,self.height,p.z
        hit.nx,hit.ny,hit.nz=0,self.ny,0
        return hit
    end
    return q
end
local function step(e,q) animation.step(e,1/120,q) end

test('planted contacts reuse copied hits and preserve targets while the body moves',function()
    local e,q=actor(),floor()
    step(e,q);assert(q.calls==2)
    local expected=animation.sample(e)
    q.hit.y=100 -- adapters may overwrite their last result outside this caller
    for _=1,12 do step(e,q) end
    assert(q.calls==2);equal(animation.sample(e),expected)
    e.position.z=.01;step(e,q)
    assert(q.calls==3,'Only the swinging left foot should cast again')
    assert(e.animation.targets.R.stance and not e.animation.targets.L.stance)
    assert(e.animation.feet.R.anchor.z==.022)
end)

test('ray, scale, query, revision and query-function changes invalidate planted hits',function()
    local changes={
        function(e,q) e.position.y=.01 end,
        function(e,q) e.animation.feet.R.anchor.x=.15;e.animation.feet.L.anchor.x=-.15 end,
        function(e,q) e.animation.feet.R.anchor.z=.15;e.animation.feet.L.anchor.z=.15 end,
        function(e,q) e.variant='irregular' end,
        function(e,q) q.revision=q.revision+1 end,
        function(e,q) q.revision=nil end,
        function(e,q) q.clearance_revision=function(self) return self.revision end end,
        function(e,q) local ray=q.ray;q.ray=function(self,p) return ray(self,p) end end,
        function(e,q) return floor() end,
        function(e,q) e.position.x=3 end, -- teleport discards all contact proofs
    }
    for _,change in ipairs(changes) do
        local e,q=actor(),floor();step(e,q);step(e,q);assert(q.calls==2)
        q=change(e,q) or q;local before=q.calls
        step(e,q);assert(q.calls==before+2)
    end
end)

test('vertical ray changes reuse only the previously clear span containing the hit',function()
    local e,q=actor(),floor();step(e,q)
    e.position.y=-.01;step(e,q);assert(q.calls==2)
    e.position.y=0;step(e,q);assert(q.calls==2,'The proof retains its original top')
    e.position.y=.01;step(e,q);assert(q.calls==4,'Newly exposed space needs a ray')
    e.position.y=.005;step(e,q);assert(q.calls==4)
    local f,r=actor(),floor();r.clearance_revision=nil
    for _,y in ipairs({0,-.01,0,.01,.005}) do f.position.y=y;step(f,r) end
    equal(animation.sample(e),animation.sample(f))
end)

test('misses, unsupported normals/heights, unversioned adapters and settling edits never cache',function()
    local changes={
        function(q) q.miss=true end,
        function(q) q.ny=.5 end,
        function(q) q.height=.5 end,
        function(q) q.revision=nil end,
        function(q) q.clearance_revision=nil end,
        function(q) q.during_ray=function(self) self.revision=self.revision+1 end end,
    }
    for _,change in ipairs(changes) do
        local e,q=actor(),floor();change(q)
        for _=1,4 do step(e,q) end
        assert(q.calls==8)
        assert(not e.animation.feet.R.ground and not e.animation.feet.L.ground)
    end
    local e,q=actor(),floor();step(e,q)
    q.revision=nil;step(e,q);q.revision=0;step(e,q)
    assert(q.calls==6,'Returning from a pending edit must establish a new proof')
end)

test('turns, touchdown, vaults and death cannot revive stale planted contacts',function()
    local e,q=actor(),floor();step(e,q)
    animation.turn(e,1);step(e,q);step(e,q);assert(q.calls==4)
    e.animation.turn_time=-1;step(e,q);assert(q.calls==5)
    animation.vault(e,.85);step(e,q);step(e,q);assert(q.calls==9)
    e.animation.vault_time=-1;step(e,q);assert(q.calls==11)
    e.actor.alive=false;step(e,q);assert(q.calls==11 and next(e.animation.feet)==nil)
    e.actor.alive=true;step(e,q);assert(q.calls==13)
end)

test('cached contacts exactly match fresh rays through movement and terrain changes',function()
    local e,f=actor(),actor();local q,r=floor(),floor();r.clearance_revision=nil
    for i=1,600 do
        for _,a in ipairs({e,f}) do
            if i<200 or i>400 then a.position.z=a.position.z-.006 end
            a.phase=a.phase+.04
            if i==220 then a.yaw=.4 end
            if i==250 then animation.turn(a,1) end
            if i==300 then a.position.x=3 end
            if i==350 then animation.vault(a,.2) end
            if i==450 then a.variant='breacher' end
        end
        if i==180 or i==240 then q.height=q.height-.02;r.height=q.height;q.revision=q.revision+1 end
        step(e,q);step(f,r)
        equal(animation.sample(e),animation.sample(f))
        for _,side in ipairs({'R','L'}) do
            for _,key in ipairs({'anchor','last','takeoff','yaw','swing'}) do
                equal(e.animation.feet[side][key],f.animation.feet[side][key])
            end
        end
    end
    assert(q.calls<r.calls*.7,q.calls..' / '..r.calls)
end)

local bones={{parent=0},{parent=1},{parent=2},{parent=3},{parent=0}}
local function chain()
    return {T.identity(0,2,0),T.identity(.2,1,0),T.identity(0,0,0),T.identity(0,-.2,0),T.identity(3,0,0)}
end
local function solution(worlds,rig_bones,lower,last,target,pole,scratch)
    local expected=copy(worlds)
    local error=IK.solve(expected,rig_bones,1,lower,last,target,pole)
    equal(IK.solve(worlds,rig_bones,1,lower,last,target,pole,scratch),error)
    equal(worlds,expected)
end
local saved_profiler=profiler
local reused=0
profiler={scope_begin=function(name)
    if name=='ik.solve_reuse' then reused=reused+1 end
    if saved_profiler then saved_profiler.scope_begin(name) end
end,scope_end=function() if saved_profiler then saved_profiler.scope_end() end end}

test('unchanged IK reuses deltas while preserving current orientations and descendants',function()
    local scratch={};local target,pole={x=.4,y=.4,z=.1},{x=0,y=0,z=1}
    solution(chain(),bones,2,3,target,pole,scratch)
    local before=reused
    for i=1,4 do
        local worlds=chain()
        local rotated=T.rotation(.1*i,.2,-.1)
        rotated[4],rotated[8],rotated[12]=worlds[2][4],worlds[2][8],worlds[2][12]
        worlds[2]=rotated;worlds[4][4]=i*.1
        solution(worlds,bones,2,3,target,pole,scratch)
    end
    assert(reused==before+4)
end)

test('every IK origin, target, pole, chain index and rig identity invalidates its solution',function()
    local changes={}
    for bone=1,3 do for _,offset in ipairs({4,8,12}) do
        changes[#changes+1]=function(w,t,p) w[bone][offset]=w[bone][offset]+.001 end
    end end
    for _,axis in ipairs({'x','y','z'}) do
        changes[#changes+1]=function(w,t,p) t[axis]=t[axis]+.001 end
        changes[#changes+1]=function(w,t,p) p[axis]=p[axis]+.001 end
    end
    changes[#changes+1]=function() return copy(bones),2,3 end
    changes[#changes+1]=function() return bones,2,4 end
    changes[#changes+1]=function() return bones,3,4 end
    for _,change in ipairs(changes) do
        local scratch={};local target,pole={x=.4,y=.4,z=.1},{x=0,y=0,z=1}
        solution(chain(),bones,2,3,target,pole,scratch)
        local before=reused;local worlds=chain()
        local changed,lower,last=change(worlds,target,pole)
        solution(worlds,changed or bones,lower or 2,last or 3,target,pole,scratch)
        assert(reused==before)
    end
end)

test('moving IK roots reacquire a solution only after the origin settles',function()
    local scratch={};local target,pole={x=.4,y=.4,z=.1},{x=0,y=0,z=1}
    solution(chain(),bones,2,3,target,pole,scratch)
    local before=reused
    for i=1,5 do
        local worlds=chain();worlds[1][8]=2+i*.01
        solution(worlds,bones,2,3,target,pole,scratch)
        assert(reused==before)
    end
    for i=1,3 do
        local worlds=chain();worlds[1][8]=2.05
        solution(worlds,bones,2,3,target,pole,scratch)
        assert(reused==before+math.max(0,i-1))
    end
end)

test('repeated full poses reuse all four solves without sharing simulation/presentation worlds',function()
    for _,variant in ipairs({'vanguard','irregular','breacher'}) do
        local state={variant=variant,time=.3,phase=.8,walk=.5,aim=1,crouch=.3,
            feet={R={target={x=.103,y=.088,z=.022},normal={x=0,y=1,z=0},weight=1},
                  L={target={x=-.103,y=.088,z=.022},normal={x=0,y=1,z=0},weight=1}}}
        local scratch,presentation={},{}
        local expected,expected_worlds=rig.pose(state)
        local palette,worlds=rig.pose(state,scratch)
        local before=reused
        for _=1,3 do
            rig.pose(state,scratch);equal(palette,expected);equal(worlds,expected_worlds)
        end
        assert(reused==before+12)
        rig.pose({death=1},presentation)
        equal(palette,expected);equal(worlds,expected_worlds)
        state.feet.R.target.y=.10 -- mutate the caller-owned input table in place
        palette,worlds=rig.pose(state,scratch)
        expected,expected_worlds=rig.pose(state)
        equal(palette,expected);equal(worlds,expected_worlds)
    end
end)

test('advancing pose clocks bypass cache bookkeeping and settled poses safely resume reuse',function()
    local scratch={};local state={time=1,crouch=.5,aim=1}
    rig.pose(state,scratch)
    for i=2,10 do
        state.time=i
        local palette,worlds=rig.pose(state,scratch)
        local expected,expected_worlds=rig.pose(state)
        equal(palette,expected);equal(worlds,expected_worlds)
        assert(not scratch.ik.solves and scratch.ik.reuse==false)
    end
    local before=reused
    for i=1,3 do
        local palette,worlds=rig.pose(state,scratch)
        local expected,expected_worlds=rig.pose(state)
        equal(palette,expected);equal(worlds,expected_worlds)
        assert(reused==before+math.max(0,i-1)*4)
    end
end)
profiler=saved_profiler
print(count..' animation reuse tests passed')
