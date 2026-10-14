-- Thin, non-intersecting decorative panes. Each pane owns a centred object so
-- renderer back-to-front sorting uses its real world position, not the origin.
local mesh=require "game.world.mesh"
local M={}
function M.pane(id,x,y,z,w,h,axis)
    local b=mesh.new(id,"glass",0,0)
    b.glass=true;b.centre={x=x,y=y,z=z}
    local corners={{-1,-1},{1,-1},{1,1},{-1,1}}
    for _,i in ipairs({1,2,3,1,3,4}) do
        local c=corners[i]
        local v=axis=="x" and {x,y+c[2]*h/2,z-c[1]*w/2} or {x+c[1]*w/2,y+c[2]*h/2,z}
        local n=axis=="x" and {1,0,0} or {0,0,1}
        for a=1,3 do
            b.positions[#b.positions+1]=v[a];b.normals[#b.normals+1]=n[a];b.colors[#b.colors+1]=1
            b.bounds[a]=math.min(b.bounds[a],v[a]-.002);b.bounds[a+3]=math.max(b.bounds[a+3],v[a]+.002)
        end
        b.colors[#b.colors+1]=1
        for a=1,4 do b.edges[#b.edges+1]=1;b.masks[#b.masks+1]=0 end
    end
    b.vertex_count=6
    return b
end
function M.world(layout)
    local result={}
    for _,b in ipairs(layout.buildings) do if b.room then
        local c=b.counter
        local x=b.x-b.w/2+c.x*b.w
        local z=b.z-b.d/2+c.z*b.d
        result[#result+1]=M.pane(b.id.."/display_glass",x,layout.street.walk_height+1.31,z+c.d/2+.015,c.w,.7,"z")
    end end
    return result
end
function M.laboratory()
    return {M.pane("glass/front",42,1.4,1,2.5,2.6,"z"),M.pane("glass/rear",42.65,1.4,-.5,2.5,2.6,"z")}
end
return M
