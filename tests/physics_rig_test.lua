package.path='./?.lua;'..package.path
local rig=require 'game.ai.rig'
local R=require 'game.physics.rig'
local T=require 'game.ai.transform'
local variants=require 'game.ai.variants'
local checks=0
local function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a)..' != '..tostring(b)) end
for _,variant in ipairs(variants.order) do
    for _,pose in ipairs({{}, {walk=1,run=1,phase=1.3,aim=1}, {crouch=1,aim=1,pitch=.3},
        {vault=.4,vault_weight=1}, {hit=1,hit_region='arm',hit_side=-1}}) do
        pose.variant=variant
        local palette,worlds=rig.pose(pose)
        local spec=R.build(worlds,{x=71,y=.7,z=-4},1.3,variant)
        assert(#spec.bodies==18 and #spec.bindings==25)
        local bodies={};local mass=0
        for i,b in ipairs(spec.bodies) do
            bodies[i]=b.world;mass=mass+b.mass
            assert(b.dimensions.x>0 and b.dimensions.y>0 and b.dimensions.z>0)
            if b.parent then
                assert(b.parent<i)
                local a=T.mul(spec.bodies[b.parent].world,b.frame_a)
                local c=T.mul(b.world,b.frame_b)
                for j=1,12 do near(a[j],c[j]) end
            end
        end
        near(mass,78.9)
        local result=R.palette(spec,bodies)
        for i=1,25 do for j=1,12 do near(result[i][j],palette[i][j]) end end
        local moved={}
        for i,b in ipairs(bodies) do
            moved[i]={};for j=1,12 do moved[i][j]=b[j] end
            moved[i][4]=moved[i][4]+8;moved[i][8]=moved[i][8]+3;moved[i][12]=moved[i][12]-6
        end
        local root=T.root({x=79,y=3.7,z=-10},1.3)
        local rebased=R.palette(spec,moved,nil,root)
        for i=1,25 do for j=1,12 do near(rebased[i][j],palette[i][j]) end end
        checks=checks+1
        for _,box in ipairs(rig.hitboxes) do
            local index=R.hit_body(spec,box.name,box.region)
            assert(spec.bodies[index].bone==rig.index[box.bone])
        end
        checks=checks+1
    end
end
print(checks..' physics rig checks passed')
