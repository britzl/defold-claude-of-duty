-- Shortest paths over authored, layered nodes. Cached links are valid only for
-- this static world; moving endpoints are always checked at their new position.
local V = require "game.weapons.math"
local M = {}
local CELL,RADIUS,CANDIDATES,LINKS=12,12,12,4
function M.distance(a,b) return V.length({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z}) end
local function key(x,z) return x..":"..z end
local function same(a,b) return a and a.x==b.x and a.y==b.y and a.z==b.z end
local function prepare(graph,cache)
    if cache.graph==graph then return end
    cache.graph=graph;cache.edges={};cache.cells={};cache.adj={};cache.endpoints={};cache.order={}
    local names={}
    for i,n in ipairs(graph.nodes) do
        names[n.id]=i;cache.adj[i]={}
        local k=key(math.floor(n.x/CELL),math.floor(n.z/CELL))
        cache.cells[k]=cache.cells[k] or {};table.insert(cache.cells[k],i)
    end
    for index,e in ipairs(graph.edges) do
        local a,b=names[e.from],names[e.to]
        if a and b then
            table.insert(cache.adj[a],{node=b,index=index,cost=M.distance(graph.nodes[a],graph.nodes[b])})
            table.insert(cache.adj[b],{node=a,index=index,cost=M.distance(graph.nodes[a],graph.nodes[b])})
        end
    end
end
local function allowed(graph,p,n)
    local flight=n.stair and graph.stairs and graph.stairs[n.stair]
    -- Enter flights via landings; don't accept raised side shortcuts.
    if flight then return p.x>=flight.x0 and p.x<=flight.x1 and p.z>=flight.z0
        and p.z<=flight.z1 and p.y>=flight.bottom and p.y<=flight.top+.05 end
    return math.abs(p.y-n.y)<=.6
end
local function route(graph,from,to,query,cache,options)
    options=options or {}
    local function probe(a,b,scope)
        if options.checkpoint then options.checkpoint() end
        if profiler then profiler.scope_begin(scope) end
        local result=query:walkable(a,b)
        if profiler then profiler.scope_end() end
        return result
    end
    -- Copy the goal: perception can update last_seen while a job is queued.
    to=V.copy(to)
    if probe(from,to,"nav.direct") then return {to} end
    cache=cache or {};prepare(graph,cache)
    local start=V.copy(from)
    local function attach(p,radius,limit)
        -- Exact coordinates only: rounding a key could reuse clearance through
        -- a wall or onto another floor. Bound storage across a long encounter.
        local k=string.format("%.17g/%.17g/%.17g/%d",p.x,p.y,p.z,radius)
        if cache.endpoints[k] then return cache.endpoints[k] end
        local candidates={}
        for x=math.floor((p.x-radius)/CELL),math.floor((p.x+radius)/CELL) do
            for z=math.floor((p.z-radius)/CELL),math.floor((p.z+radius)/CELL) do
                for _,i in ipairs(cache.cells[key(x,z)] or {}) do
                    local n=graph.nodes[i]
                    local distance=M.distance(p,n)
                    if distance<=radius and allowed(graph,p,n) then candidates[#candidates+1]={node=i,cost=distance} end
                end
            end
        end
        table.sort(candidates,function(a,b) return a.cost==b.cost and a.node<b.node or a.cost<b.cost end)
        local links,count={},0
        for i=1,math.min(limit,#candidates) do
            local c=candidates[i]
            if probe(p,graph.nodes[c.node],"nav.endpoints") then
                links[c.node]=c.cost
                count=count+1
                if count>=(radius==RADIUS and LINKS or LINKS*3) then break end
            end
        end
        if #cache.order>=64 then cache.endpoints[table.remove(cache.order,1)]=nil end
        cache.order[#cache.order+1]=k;cache.endpoints[k]=links
        return links
    end
    local function search(radius,limit)
        local starts,goals=attach(start,radius,limit),attach(to,radius,limit)
        if not next(starts) or not next(goals) then return end
        local dist,prev,closed={},{},{}
        for i,cost in pairs(starts) do dist[i]=cost end
        local finish,best_cost
        for _=1,#graph.nodes do
            local best
            for i=1,#graph.nodes do if not closed[i] and dist[i] and (not best or dist[i]<dist[best]) then best=i end end
            if not best or (best_cost and dist[best]>=best_cost) then break end
            if goals[best] and (not best_cost or dist[best]+goals[best]<best_cost) then
                finish=best;best_cost=dist[best]+goals[best]
            end
            closed[best]=true
            for _,edge in ipairs(cache.adj[best]) do
                local i=edge.node
                if not closed[i] and (not dist[i] or dist[best]+edge.cost<dist[i]) then
                    if cache.edges[edge.index]==nil then
                        cache.edges[edge.index]=probe(graph.nodes[best],graph.nodes[i],"nav.static_edges")
                    end
                    if cache.edges[edge.index] then dist[i]=dist[best]+edge.cost;prev[i]=best end
                end
            end
        end
        if not finish then return end
        local result={V.copy(to)}
        while finish do table.insert(result,1,V.copy(graph.nodes[finish]));finish=prev[finish] end
        return result
    end
    local result=search(RADIUS,CANDIDATES)
    -- Sparse alley spans need a wider, still bounded search. A failed local
    -- component also gets this fallback; never silently attach through walls.
    if not result then result=search(RADIUS*2,CANDIDATES*2) end
    -- The soldier may have continued its previous route while probes yielded.
    -- Validate the actual current start immediately before installing the route.
    if result and not same(from,start) and not probe(from,result[1],"nav.reconnect") then return end
    return result
end
function M.route(graph,from,to,query,cache,options)
    -- Scopes must not remain open across a coroutine yield.
    if profiler and not options then profiler.scope_begin("nav.route") end
    local result=route(graph,from,to,query,cache,options)
    if profiler and not options then profiler.scope_end() end
    return result
end
return M
