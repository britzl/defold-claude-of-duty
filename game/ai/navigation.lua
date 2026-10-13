-- Shortest paths over authored, layered nodes. Start/goal links and every edge
-- must be capsule-clear and floor-supported according to the query adapter.
local V = require "game.weapons.math"
local M = {}
function M.distance(a,b) return V.length({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z}) end
function M.route(graph,from,to,query)
    if query:walkable(from,to) then return {V.copy(to)} end
    local nodes={V.copy(from),V.copy(to)}
    local names,edges={},{}
    for _,n in ipairs(graph.nodes) do nodes[#nodes+1]=n;names[n.id]=#nodes end
    for i=1,#nodes do edges[i]={} end
    local function connect(a,b)
        if a and b and query:walkable(nodes[a],nodes[b]) then
            local cost=M.distance(nodes[a],nodes[b])
            edges[a][b]=cost;edges[b][a]=cost
        end
    end
    for _,e in ipairs(graph.edges) do connect(names[e.from],names[e.to]) end
    for i=3,#nodes do connect(1,i);connect(2,i) end
    local dist,prev,closed={[1]=0},{},{}
    for _=1,#nodes do
        local best
        for i=1,#nodes do if not closed[i] and dist[i] and (not best or dist[i]<dist[best]) then best=i end end
        if not best then return nil end
        if best==2 then
            local route={}
            while best~=1 do table.insert(route,1,V.copy(nodes[best]));best=prev[best] end
            return route
        end
        closed[best]=true
        -- Numeric iteration keeps equal-cost choices deterministic.
        for i=1,#nodes do
            local cost=edges[best][i]
            if cost and not closed[i] and (not dist[i] or dist[best]+cost<dist[i]) then dist[i]=dist[best]+cost;prev[i]=best end
        end
    end
end
return M
