package.path='./?.lua;'..package.path
local rig=require 'game.ai.rig'
local animation=require 'game.ai.animation'
local function copy(t)
    if type(t)~='table' then return t end
    local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
end
local function equal(a,b)
    if type(a)~='table' then assert(a==b,tostring(a)..' != '..tostring(b));return end
    for k,v in pairs(a) do equal(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil,'Unexpected key '..k) end
end
local simulation,presentation,volumes={},{},{}
for i=1,40 do
    local s={variant=i%2==0 and 'irregular' or 'breacher',time=i/10,phase=i*.7,walk=1,
        crouch=i%3==0 and 1 or 0,death=i%5==0 and .5 or 0,aim=1,reload=i/40,reload_weight=1}
    if i%2==0 then s.feet={R={target={x=.103,y=.15,z=.1},normal={x=.1,y=.99,z=0},weight=1},
        L={target={x=-.103,y=.088,z=-.2},normal={x=0,y=1,z=0},weight=1}} end
    local palette,worlds=rig.pose(s,simulation)
    local expected,expected_worlds=rig.pose(s)
    equal(palette,expected);equal(worlds,expected_worlds)
    rig.pose({death=1,phase=i},presentation)
    equal(palette,expected);equal(worlds,expected_worlds)
    local previous=volumes.volumes and volumes.volumes[1]
    local old_matrix=previous and previous.transform
    local position={x=i,y=.5,z=-i}
    local result=rig.volumes(palette,position,i*.1,'actor',s.variant,volumes)
    equal(result,rig.volumes(palette,position,i*.1,'actor',s.variant))
    if previous then assert(result[1]==previous and result[1].transform==old_matrix) end
end
print('PASS reused pose/hit-volume buffers match fresh evaluation across clips and remain separate from presentation')

local IK=require 'game.ai.ik'
local T=require 'game.ai.transform'
local workspace={}
for _,bones in ipairs({{{parent=0},{parent=1},{parent=2}},{{parent=0},{parent=0},{parent=2}}}) do
    for _,index in ipairs({1,2,3,1}) do
        local worlds={T.identity(1,2,3),T.rotation(.2,.4,-.7),T.identity(-1,3,2)}
        local expected=copy(worlds);local pivot=T.origin(worlds[index]);local rotation=T.rotation(.3,-.6,.2)
        local delta=T.mul(T.mul(T.identity(pivot.x,pivot.y,pivot.z),rotation),T.identity(-pivot.x,-pivot.y,-pivot.z))
        local affected={[index]=true}
        for i=index,#bones do if i==index or affected[bones[i].parent] then
            affected[i]=true;expected[i]=T.mul(delta,expected[i])
        end end
        IK.rotate(worlds,bones,index,rotation,workspace)
        equal(worlds,expected)
    end
end
print('PASS in-place IK products preserve unaffected bones and invalidate subtree caches when switching rigs')

local e={variant='vanguard',position={x=0,y=0,z=0},yaw=0,actor={alive=true,health=100,max_health=100}}
animation.init(e)
e.animation.targets={R={target={x=1,y=2,z=3},normal={x=0,y=1,z=0},weight=1}}
e.animation.vault_hand={x=1,y=2,z=3}
e.animation.reload_time=1
local previous=animation.sample(e)
local frozen=copy(previous)
e.animation.targets.R.target.x=4
local current=animation.sample(e)
local interpolated=animation.interpolate(previous,current,.5)
local foot,point=interpolated.feet.R,interpolated.feet.R.target
for i=1,4 do
    e.animation.targets.R.target.x=i+10
    animation.sample(e,current)
    animation.interpolate(previous,current,.5,interpolated)
    assert(interpolated.feet.R==foot and interpolated.feet.R.target==point)
    equal(interpolated,animation.interpolate(previous,current,.5))
    equal(previous,frozen)
end
e.animation.targets=nil;e.animation.vault_hand=nil;e.animation.reload_time=-1
animation.sample(e,current);animation.interpolate(previous,current,.5,interpolated)
assert(not current.feet and not current.vault_hand and not interpolated.feet and not interpolated.vault_hand)
assert(math.abs(interpolated.reload-(previous.reload+1)/2)<1e-15)
equal(previous,frozen)
print('PASS animation snapshots preserve history, reuse nested buffers, clear missing fields and finish one-shots forward')
