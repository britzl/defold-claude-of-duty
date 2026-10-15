local kit=require "game.world.kit"
local M={}
function M.floor_spec(b,level)
    if not b.setback or level<b.setback.from then return b end
    local r={};for k,v in pairs(b) do r[k]=v end
    r.x=b.x-b.side*b.setback.depth/2;r.w=b.w-b.setback.depth
    return r
end

-- The four window apertures are actual recesses, with a closed backing and
-- jamb depth. The same recipe is used by solid facades and accessible floors.
function M.window_wall(layout,b,level,box)
    local base=layout.street.walk_height+level*layout.storey
    local bottom,top=base+.975,base+2.625
    local x=b.x+b.side*(b.w/2-layout.wall/2)
    local z0,z1=b.z-b.d/2,b.z+b.d/2
    local prefix=b.id.."/facade/"..level
    local cursor=z0
    for i=1,4 do
        local z=z0+(i-.5)*b.d/4
        local lo,hi=z-.625,z+.625
        box(prefix.."/pier/"..i,b.material,x,base+(layout.storey-layout.slab)/2,(cursor+lo)/2,
            layout.wall,layout.storey-layout.slab,lo-cursor,"plaster")
        box(prefix.."/below/"..i,b.material,x,(base+bottom)/2,z,layout.wall,bottom-base,1.25,"plaster")
        box(prefix.."/above/"..i,b.material,x,(top+base+layout.storey-layout.slab)/2,z,
            layout.wall,base+layout.storey-layout.slab-top,1.25,"plaster")
        cursor=hi
    end
    box(prefix.."/pier/5",b.material,x,base+(layout.storey-layout.slab)/2,(cursor+z1)/2,
        layout.wall,layout.storey-layout.slab,z1-cursor,"plaster")
end

function M.details(layout,b,detail,random)
    local box=kit.box
    local base,storey=layout.street.walk_height,layout.storey
    local top=M.floor_spec(b,b.floors-1)
    local roof=base+b.floors*storey
    local id=b.id.."/detail"
    -- Visible setback terraces do not change the authored stair openings.
    if b.setback then
        local y=base+b.setback.from*storey
        local x=b.x+b.side*(b.w/2-b.setback.depth/2)
        box(id.."/terrace","concrete_floor",x,y-.1,b.z,b.setback.depth,.2,b.d,"concrete")
        box(id.."/terrace/rail",b.material,b.x+b.side*(b.w/2-.12),y+.43,b.z,.24,.86,b.d,"plaster")
        kit.solid("bevel",id.."/terrace/coping","trim",b.x+b.side*(b.w/2-.12),y+.91,b.z,.35,.12,b.d+.15)
        for _,s in ipairs({-1,1}) do
            box(id.."/terrace/end/"..s,b.material,x,y+.43,b.z+s*(b.d/2-.12),b.setback.depth-.24,.86,.24,"plaster")
        end
    end
    if b.balconies then
        for level=1,b.floors-1 do
            local f=M.floor_spec(b,level)
            local y=base+level*storey
            local x=f.x+b.side*(f.w/2+.56)
            for i=1,b.balconies do
                local z=b.z-b.d/2+(i==1 and .375 or .875)*b.d
                local p=id.."/balcony/"..level.."/"..i
                kit.solid("bevel",p.."/slab","concrete",x,y-.08,z,1.3,.24,2.5,"concrete")
                for _,s in ipairs({-1,1}) do
                    kit.beam(p.."/bracket/"..s,"metal",{x-b.side*.5,y-.85,z+s*.85},{x+b.side*.4,y-.17,z+s*.85},.09)
                    box(p.."/return/"..s,"metal",x,y+.9,z+s*1.18,1.3,.055,.055)
                end
                box(p.."/rail","metal",x+b.side*.6,y+.95,z,.06,.06,2.5)
                for j=0,8 do box(p.."/bar/"..j,"metal",x+b.side*.6,y+.48,z-1.18+j*.295,.035,.94,.035) end
            end
        end
    end
    if b.arches then
        for level=1,b.floors-1 do
            local f=M.floor_spec(b,level)
            local front=f.x+b.side*(f.w/2+.06)
            for i=1,4 do
                local z=b.z-b.d/2+(i-.5)*b.d/4
                for j=0,7 do
                    local a,c=j*math.pi/8,(j+1)*math.pi/8
                    kit.beam(id.."/arch/"..level.."/"..i.."/"..j,"trim",
                        {front,base+level*storey+2.35+.48*math.sin(a),z+.7*math.cos(a)},
                        {front,base+level*storey+2.35+.48*math.sin(c),z+.7*math.cos(c)},.16)
                end
            end
        end
    end
    if b.ruin then
        if not b.room then M.ruin(layout,b) end
        return
    end
    -- Roof tanks, service hut, corrugated lean-to, dish and aerial give every
    -- roof a varied skyline. All heavy pieces have collision at their base.
    local rx,rz=top.x-b.side*top.w*.22,top.z+top.d*.24
    box(id.."/roof/hut",b.material,rx,roof+.85,rz,2.3,1.7,2.1,"plaster")
    kit.solid("bevel",id.."/roof/cap","concrete",rx,roof+1.76,rz,2.5,.16,2.3)
    box(id.."/roof/door","shutters",rx,roof+.7,rz-1.06,.85,1.4,.045)
    kit.solid("cylinder",id.."/roof/tank","metal_painted",top.x+b.side*1.4,roof+.9,top.z-1.6,1.4,1.8,1.4,"metal")
    kit.solid("cylinder",id.."/roof/lid","metal",top.x+b.side*1.4,roof+1.84,top.z-1.6,1.5,.08,1.5)
    kit.beam(id.."/roof/aerial","metal",{rx,roof+1.85,rz},{rx+.12,roof+4,rz},.035)
    for j=1,3 do box(id.."/roof/aerial/"..j,"metal",rx,roof+2.4+j*.4,rz,1.2-j*.22,.035,.035) end
    if not detail then return end
    box(id.."/roof/sheet","corrugated",top.x,roof+.35,top.z+2,2.3,.055,1.9,nil,nil,{rotation_x=.18})
    kit.solid("cylinder",id.."/roof/dish","metal",rx-1.8,roof+.9,rz,1.1,.15,1.1,nil,nil,{rotation_x=.9,taper=.75})
    kit.beam(id.."/roof/dish/stand","metal",{rx-1.8,roof,rz},{rx-1.8,roof+.9,rz},.07)
    if b.facade_axis=="z" then return end
    local front=b.x+b.side*(b.w/2+.07)
    local pipe_top=base+(b.setback and b.setback.from or b.floors)*storey
    box(id.."/pipe","metal_rust",front,pipe_top/2,b.z-b.d/2+.5,.07,pipe_top,.07)
    for i=1,4 do
        local f=M.floor_spec(b,math.min(i% b.floors,b.floors-1))
        local fx=f.x+b.side*(f.w/2+.009)
        local z=b.z-b.d/2+.9+random()*(b.d-1.8)
        local y=base+.5+random()*(b.floors*storey-1)
        if b.setback and y>base+b.setback.from*storey then fx=top.x+b.side*(top.w/2+.009) end
        -- Irregular chipped render on solid piers, below the window band.
        y=base+math.floor((y-base)/storey)*storey+.45
        box(id.."/spall/"..i,"brick",fx,y,z,.023,.25+random()*.25,.3+random()*.5,nil,nil,{rotation_x=(random()-.5)*.4})
    end
end

function M.ruin(layout,b)
    local y=layout.street.walk_height+layout.storey
    local x0,x1,z0,z1=b.x-b.w/2,b.x+b.w/2,b.z-b.d/2,b.z+b.d/2
    local id=b.id.."/ruin"
    local back=b.x-b.side*(b.w/2-.15)
    local strip=b.x-b.side*(b.w/2-1.8)
    local broken=b.side<0 and x0 or x1-2.3
    -- A surviving eastern slab and two end strips frame the collapse. Broken
    -- slab edges, exposed beams and rebar remain overhead, outside walk space.
    kit.box(id.."/slab/back","concrete_floor",strip,y-.1,b.z,3.6,.2,b.d,"concrete")
    for _,s in ipairs({-1,1}) do
        local z=b.z+s*(b.d/2-1.2)
        kit.box(id.."/slab/end/"..s,"concrete_floor",b.x+b.side*1.8,y-.1,z,b.w-3.6,.2,2.4,"concrete")
        local h=s==1 and 1.9 or 2.8
        kit.box(id.."/wall/"..s,b.material,b.x,y+h/2,b.z+s*(b.d/2-.15),b.w,h,.3,"plaster")
        kit.prism(id.."/break/"..s,"brick",{{broken,y+1.1},{broken+2.3,y+1.1},{broken+1.7,y+2.7},{broken,y+2.3}},z,.32)
    end
    kit.box(id.."/back",b.material,back,y+1.5,b.z,.3,3,b.d,"plaster")
    kit.box(id.."/roof/remnant","concrete_floor",b.x-b.side*(b.w/2-1.4),y+3.1,b.z,2.8,.2,b.d,"concrete")
    for i=1,3 do
        local z=z0+2+i*2.7
        kit.beam(id.."/beam/"..i,"concrete",{b.x+b.side*2,y-.15,z},{back,y-.15,z+.4},.18)
        for j=1,3 do kit.beam(id.."/rebar/"..i.."/"..j,"metal_rust",{strip+b.side*1.9,y,z+j*.14},{strip+b.side*2.7,y+.16,z+j*.14},.018) end
    end
    for i=0,4 do
        local h=.6+(i%3)*.48
        kit.box(id.."/front/remnant/"..i,b.material,b.x+b.side*(b.w/2-.15),y+h/2,z0+.5+i*(b.d-1)/4,.3,h,.9,"plaster")
    end
end

function M.gate(layout,detail)
    local g=layout.gate;if not g then return end
    local box=kit.box
    for i,b in ipairs(g.blocks) do
        local id="gate/"..b.id
        local x,z,d=(b.x0+b.x1)/2,g.z+b.proud/2,g.depth+b.proud
        local material=({"plaster_sand","plaster_blue","plaster_cream"})[i]
        box(id,material,x,b.height/2,z,b.x1-b.x0,b.height,d,"plaster")
        for _,s in ipairs({-1,1}) do
            box(id.."/pilaster/"..s,material,x+s*((b.x1-b.x0)/2-.3),b.height/2,z+d/2+.13,.5,b.height,.3)
        end
        kit.solid("bevel",id.."/cornice","concrete",x,b.height-.15,z+.15,b.x1-b.x0+.4,.3,d+.6)
        box(id.."/belt","trim",x,b.height*.46,z+d/2+.08,b.x1-b.x0+.15,.17,.24)
        for j=1,math.floor(b.x1-b.x0) do
            local px=b.x0+(j-.5)*(b.x1-b.x0)/math.floor(b.x1-b.x0)
            box(id.."/merlon/"..j,material,px,b.height+.38,z+d/2-.16,.58,.62+(j%2)*.15,.34)
            box(id.."/corbel/"..j,"concrete",px,b.height-.55,z+d/2+.16,.2,.5,.45)
        end
        for j=1,(i==1 and 3 or 2) do
            local px=i==1 and b.x0+.9+(j-1)*1.9 or x
            local y=i==1 and b.height*.66 or b.height*(.32+j*.2)
            box(id.."/aperture/"..j,"dark",px,y,z+d/2+.012,.78,1.25,.03)
            for _,s in ipairs({-1,1}) do box(id.."/jamb/"..j.."/"..s,"trim",px+s*.45,y,z+d/2+.13,.12,1.45,.24) end
            kit.solid("bevel",id.."/lintel/"..j,"trim",px,y+.7,z+d/2+.13,1,.15,.28)
        end
        kit.bags(id.."/bags",x,b.height+.1,z,math.min(2.4,b.x1-b.x0-.4),3,false)
    end
    -- Pointed arch, with real depth and individual wedge stones. Collision
    -- envelopes start above 2.1 m even at the spring, leaving the route clear.
    local r=g.opening/2
    local function arch(x) return g.clearance-(g.clearance-2.2)*(math.abs(x)/r)^1.55 end
    for i=0,15 do
        local x0,x1=-r+i*g.opening/16,-r+(i+1)*g.opening/16
        local y0,y1=arch(x0),arch(x1)
        kit.prism("gate/arch/"..i,"plaster_sand",{{x0,y0},{x1,y1},{x1,g.height},{x0,g.height}},g.z,g.depth,"plaster")
        kit.prism("gate/stone/"..i,"concrete",{{x0+.008,y0-.04},{x1-.008,y1-.04},{x1-.008,y1+.26},{x0+.008,y0+.26}},g.z,g.depth+.16)
    end
    box("gate/walkway","concrete_floor",0,g.height+.11,g.z+g.depth/2+.35,g.opening+1.4,.22,.85,"concrete")
    for i=0,5 do
        local x=-g.opening/2+i*g.opening/5
        box("gate/walkway/corbel/"..i,"concrete",x,g.height-.24,g.z+g.depth/2+.3,.2,.46,.65)
        box("gate/walkway/merlon/"..i,"plaster_sand",x,g.height+.56,g.z+g.depth/2+.7,.6,.7,.3)
    end
    kit.bags("gate/walkway/bags",-.6,g.height+.23,g.z+.5,2,3,false)
    kit.beam("gate/aerial","metal_rust",{8.7,12.5,g.z+1},{8.9,15.4,g.z+1},.055)
end
return M
