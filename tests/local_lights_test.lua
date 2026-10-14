local lights=require "game.render.local_lights"
local events=require "game.events"
local fx=require "game.systems.fx"
local tests=0
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local function light(id,x)
    return {id=id,kind="room",x=x,y=2,z=0,radius=6,minimum={x=x-1,y=0,z=-1},maximum={x=x+1,y=3,z=1}}
end
local list={light("a",0),light("b",4),light("c",8),light("d",12),light("e",16),light("f",20)}
test("room selection is bounded, deterministic and resists boundary jitter",function()
    local state=lights.update(nil,list,{x=0,y=1,z=0},0,true)
    assert(#state.slots==4 and state.slots[1].light.id=="a")
    local chosen={};for _,s in ipairs(state.slots) do chosen[s.light.id]=true end
    for i=1,100 do
        state=lights.update(state,list,{x=(i%2)*.001,y=1,z=0},1/60)
        assert(#state.slots<=4)
        for _,s in ipairs(state.slots) do assert(chosen[s.light.id] and s.gain==1) end
    end
end)
test("replacement lights pass through zero energy before changing identities",function()
    local state=lights.update(nil,list,{x=0,y=1,z=0},0,true)
    local previous={}
    for _,s in ipairs(state.slots) do previous[#previous+1]={id=s.light.id,gain=s.gain} end
    for frame=1,50 do
        state=lights.update(state,list,{x=20,y=1,z=0},1/60)
        local seen={}
        for i,s in ipairs(state.slots) do
            assert(s.gain>=0 and s.gain<=1)
            if s.light then
                assert(not seen[s.light.id]);seen[s.light.id]=true
                if previous[i].id~=s.light.id then assert(s.gain==0) end
                previous[i]={id=s.light.id,gain=s.gain}
            end
        end
    end
    local wanted={c=true,d=true,e=true,f=true}
    for _,s in ipairs(state.slots) do assert(wanted[s.light.id] and s.gain==1) end
end)
test("shadow priority is independent of stable room slots and stays within two cubes",function()
    local state=lights.update(nil,list,{x=0,y=1,z=0},0,true,2)
    assert(#state.slots==2 and state.slots[1].light.id=="a")
    for i=1,50 do state=lights.update(state,list,{x=20,y=1,z=0},1/60,false,2) end
    local ids={};for _,s in ipairs(state.slots) do ids[s.light.id]=true;assert(s.gain==1) end
    assert(ids.e and ids.f and #state.slots==2)
    state=lights.update(state,{}, {x=0,y=0,z=0},0,true,2);assert(#state.slots==0)
end)
test("capture resets produce exact lighting immediately, including after room transitions",function()
    local state=lights.update(nil,list,{x=0,y=1,z=0},0,true)
    for i=1,50 do state=lights.update(state,list,{x=20,y=1,z=0},1/60) end
    local camera={x=8,y=1,z=0}
    local expected=lights.rank(list,camera)
    state=lights.update(state,list,camera,0,true)
    for i,s in ipairs(state.slots) do assert(s.light==expected[i] and s.gain==1) end
end)
test("player and enemy firing lights expire, deduplicate by source and stay bounded",function()
    local ctx={events=events.new()};fx.init(ctx)
    for _,source in ipairs({"player","enemy_1","enemy_1","enemy_2"}) do
        events.emit(ctx.events,events.WEAPON_FIRE,{source=source,position={x=1,y=2,z=3},direction={x=0,y=0,z=-1}})
    end
    assert(#ctx.fx.flashes==2 and ctx.fx.flashes[1].source=="enemy_2" and ctx.fx.flashes[2].source=="enemy_1")
    fx.update(ctx,.03);assert(#ctx.fx.flashes==2)
    fx.update(ctx,.031);assert(#ctx.fx.flashes==0)
    fx.final(ctx)
    events.emit(ctx.events,events.WEAPON_FIRE,{position={x=1,y=2,z=3}})
    assert(ctx.fx==nil)
end)
print(tests.." local lighting tests passed")
