package.path='./?.lua;'..package.path
local positions,shapes,queries=0,0,0
local contacts,hits={},{}
vmath={vector3=function() return {x=0,y=0,z=0} end,quat=function() return {} end}
bullet3d={shape={SHAPE_TYPE_CAPSULE=1,SHAPE_TYPE_SPHERE=2,set_shape=function() shapes=shapes+1 end,set_local_transform=function() end},
    get_collision_object=function(url) return url end,get_world=function() return 1 end,get_gameobject_id=function(object) return object end,
    collision_object={get_shape=function() return 1 end,get_collision_filter_group=function() return 1 end,get_collision_filter_mask=function() return 2 end,
        set_position=function() positions=positions+1 end},
    world={contact_test=function() queries=queries+1;return contacts end,
        cast_ray_closest=function() end,cast_shape_closest=function() end,cast_shape=function() return hits end,overlap_shape=function() return {} end}}
local adapter=require 'game.player.bullet'
local q=adapter.new('a',{wall={surface='wood'}})
local feet={x=1,y=2,z=3}
q:sync(feet,1.78);q:sync(feet,1.78);assert(positions==1 and shapes==1)
q:ray({x=20,y=30,z=40},1,0,0);q:sweep(feet,1.78,1,0,0);q:camera_fraction({x=50,y=60,z=70},1,0,0,.1)
q:sync(feet,1.78);assert(positions==1,'Query origins must not invalidate or replace cached body position')
feet.x=4;q:sync(feet,1.78);assert(positions==2)
q:sync(feet,1.12);assert(positions==3 and shapes==2)
adapter.new('b',{}):sync(feet,1.12);assert(positions==4,'Each mover owns its position cache')
q:begin_step();q:sync(feet,1.12);q:sync(feet,1.12);assert(positions==5,'The next fixed step must resynchronize the body')
print('PASS duplicate mover sync is skipped independently of query scratch, teleports, height changes and other movers')
contacts={{distance=0,normal_on_b={x=0,y=1,z=0}},{distance=-.2,normal_on_b={x=1,y=0,z=0}}}
local result=q:contacts(feet,1.12);local first,second=result[1],result[2]
assert(not q:fits(feet,1.12));assert(result[2]==second and second.distance==-.2)
contacts={};assert(q:fits(feet,1.12),'Clearance must query again even at the same position')
assert(#q:contacts(feet,1.12)==0)
contacts={{distance=-.0001,normal_on_b={x=0,y=1,z=0}}}
assert(q:fits(feet,1.12),'Harmless touching must fit')
assert(q:contacts(feet,1.12)[1]==first and #result==1 and result[2]==nil)
assert(queries==6)
hits={{fraction=0,normal={x=0,y=1,z=0},object='floor'},{fraction=.5,normal={x=-1,y=0,z=0},object='wall'}}
local hit=q:sweep(feet,1.12,1,0,0);assert(hit.fraction==.5 and hit.surface=='wood')
print('PASS fresh Bullet contacts, touching tolerance, bounded contact reuse and tangent-floor filtering')
