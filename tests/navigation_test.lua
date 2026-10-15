package.path="./?.lua;"..package.path
local nav=require "game.ai.navigation"
local planner=require "game.ai.planner"
local count=0
local function test(name,run) run();count=count+1;print("PASS "..name) end
local function fixture()
    local graph={nodes={{id="a",x=0,y=0,z=0},{id="b",x=0,y=0,z=-2}},edges={{from="a",to="b"}}}
    local from,to={x=2,y=0,z=0},{x=2,y=0,z=-2}
    local q={calls=0}
    function q:walkable(a,b)
        self.calls=self.calls+1
        return (a.x==0 and b.x==0) or a.z==b.z
    end
    return graph,from,to,q
end

test("endpoint probes stay local even with hundreds of distant nodes",function()
    local graph,from,to,q=fixture()
    for i=1,300 do graph.nodes[#graph.nodes+1]={id="far"..i,x=100+i,y=0,z=100} end
    local original=q.walkable
    function q:walkable(a,b) assert(a.x<100 and b.x<100);return original(self,a,b) end
    assert(nav.route(graph,from,to,q));assert(q.calls<10,q.calls)
end)

test("only identical endpoints reuse clearance and graph replacement invalidates it",function()
    local graph,from,to,q=fixture()
    local cache={}
    assert(nav.route(graph,from,to,q,cache));local first=q.calls
    q.calls=0;assert(nav.route(graph,from,to,q,cache));assert(q.calls==1 and first>1)
    from.z=.01;q.calls=0
    assert(not nav.route(graph,from,to,q,cache));assert(q.calls>1)
    from.z=0
    graph={nodes=graph.nodes,edges={}}
    assert(not nav.route(graph,from,to,q,cache))
end)

test("endpoint cache storage remains bounded during long movement",function()
    local graph,from,to,q=fixture()
    local cache={}
    for i=1,100 do from.x=2+i*.001;assert(nav.route(graph,from,to,q,cache)) end
    local entries=0;for _ in pairs(cache.endpoints) do entries=entries+1 end
    assert(entries<=64 and #cache.order<=64)
end)

test("wider fallback reaches sparse alley nodes and never accepts unsupported links",function()
    local graph,from,to,q=fixture()
    from.x=15;to.x=15
    assert(nav.route(graph,from,to,q))
    function q:walkable() return false end
    assert(not nav.route(graph,from,to,q))
end)

test("queued searches match synchronous routes and recheck a moving start",function()
    local graph,from,to,q=fixture()
    local expected=assert(nav.route(graph,from,to,q))
    local result
    local co=coroutine.create(function()
        result=nav.route(graph,from,to,q,{}, {checkpoint=planner.checkpoint})
    end)
    local resumes=0
    repeat local ok,err=coroutine.resume(co);assert(ok,err);resumes=resumes+1 until coroutine.status(co)=="dead"
    assert(resumes>2 and #result==#expected)
    for i,p in ipairs(result) do assert(p.x==expected[i].x and p.z==expected[i].z) end
    co=coroutine.create(function()
        result=nav.route(graph,from,to,q,{}, {checkpoint=planner.checkpoint})
    end)
    assert(coroutine.resume(co));assert(coroutine.resume(co))
    -- Initial direct probe has failed and endpoint work is suspended. The
    -- soldier moves along its old route to a position with no supported link.
    from.z=.01
    repeat local ok,err=coroutine.resume(co);assert(ok,err) until coroutine.status(co)=="dead"
    assert(not result,"Cannot install a route from the stale starting position")
end)

test("one frame budget spans fixed ticks, serves jobs fairly, and resumes next frame",function()
    local p=planner.new(1,3,function() return 0 end)
    local work={0,0,0}
    for i=1,3 do planner.add(p,i,function()
        for _=1,3 do work[i]=work[i]+1;planner.checkpoint() end
    end) end
    local valid=function() return true end
    planner.step(p,1,valid)
    assert(work[1]==1 and work[2]==1 and work[3]==1)
    planner.step(p,1,valid);assert(work[1]==1 and p.steps==3)
    for frame=2,4 do planner.step(p,frame,valid) end
    assert(#p.jobs==0 and work[1]==3 and work[2]==3 and work[3]==3)
end)

test("time budget stops new probes and invalidated actors never resume",function()
    local time=0
    local p=planner.new(.002,32,function() return time end)
    local ran=0
    local job=planner.add(p,{},function()
        for _=1,10 do ran=ran+1;time=time+.0011;planner.checkpoint() end
    end)
    planner.step(p,1,function() return true end);assert(ran==2)
    planner.step(p,1,function() return true end);assert(ran==2)
    job.cancelled=true
    planner.step(p,2,function(j) return not j.cancelled end)
    assert(#p.jobs==0 and ran==2)
end)

test("cover ownership is rechecked after competing searches yield",function()
    local tactics=require "game.ai.tactics"
    local cover={id="safe",x=0,y=0,z=-5,height=1,normal_x=-1,normal_z=0}
    local ctx={ai={cover_claims={},nav_cache={}},world={cover={cover},navigation={nodes={},edges={}}}}
    local a={id="a",age=0,position={x=0,y=0,z=-4},last_seen={x=4,y=0,z=-3}}
    local b={id="b",age=0,position=a.position,last_seen=a.last_seen}
    local q={walkable=function() return true end,visible=function(_,p) return p.y>1 end}
    local function job(e) return coroutine.create(function()
        tactics.cover(ctx,e,q,{checkpoint=planner.checkpoint})
    end) end
    local first,second=job(a),job(b)
    assert(coroutine.resume(first));assert(coroutine.resume(second))
    assert(coroutine.resume(first));assert(coroutine.resume(second))
    assert(a.cover==cover and not b.cover and ctx.ai.cover_claims.safe=="a")
end)
print(count.." navigation tests passed")
