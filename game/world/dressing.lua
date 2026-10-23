-- Source layout's set-piece families, adapted to the shared Defold routes.
-- Only small scatter uses randomness. Each location has its own stream, so
-- adding a lamp does not shuffle a room, cover, an enemy or a weapon sequence.
local kit=require "game.world.kit"
local rng=require "game.rng"
local M={}
local box=kit.box

local function barrel(id,x,y,z)
    kit.solid("cylinder",id,"metal_rust",x,y+.45,z,.65,.9,.65,"metal")
    for _,h in ipairs({.12,.75}) do kit.solid("cylinder",id.."/band/"..h,"metal",x,y+h,z,.68,.045,.68) end
end
local function goods(id,x,y,z,n,along_z,span)
    local random=rng.new(1337,id)
    local spacing=span and math.min(.32,(span-.23)/(n-1)) or .32
    for i=1,n do
        local offset=(i-(n+1)/2)*spacing
        local px,pz=x+(along_z and 0 or offset),z+(along_z and offset or 0)
        px,pz=px+(random()-.5)*.035,pz+(random()-.5)*.08
        local h=.18+random()*.16
        if i%3==0 then
            kit.solid("cylinder",id.."/jar/"..i,"awning_cream",px,y+h/2,pz,.17,h,.17,nil,nil,{taper=.78})
            kit.solid("cylinder",id.."/neck/"..i,"metal_painted",px,y+h+.02,pz,.09,.04,.09)
        else kit.solid("bevel",id.."/box/"..i,i%2==0 and "awning_sage" or "wood",px,y+h/2,pz,.23,h,.24,
            nil,nil,{rotation_y=(random()-.5)*.35,bevel=.025}) end
    end
end
local function rubble(id,x,y,z,radius,count,random)
    for i=1,count do
        local a=2*math.pi*random();local r=radius*math.sqrt(random())
        local size=.09+random()*.23
        kit.solid("bevel",id.."/"..i,i%3==0 and "brick" or "concrete",x+math.cos(a)*r,y+size*.35,z+math.sin(a)*r,
            size*1.5,size*.7,size,nil,nil,{rotation_y=a,bevel=.025})
    end
end
local function partition(id,axis,fixed,lo,hi,door,width,base)
    local function piece(name,a,b,y,h)
        box(id.."/"..name,"plaster_inside",axis=="x" and fixed or (a+b)/2,y,axis=="x" and (a+b)/2 or fixed,
            axis=="x" and .22 or b-a,h,axis=="x" and b-a or .22,"plaster")
    end
    local holes=type(door)=="table" and door or {{door,width}}
    local cursor=lo
    for i,hole in ipairs(holes) do
        piece("pier/"..i,cursor,hole[1]-hole[2]/2,base+1.5,3)
        piece("lintel/"..i,hole[1]-hole[2]/2,hole[1]+hole[2]/2,base+2.78,.44)
        cursor=hole[1]+hole[2]/2
    end
    piece("end",cursor,hi,base+1.5,3)
end

local function furnish(layout,b,detail,seed)
    local y=layout.street.walk_height
    local x0,x1,z0,z1=b.x-b.w/2,b.x+b.w/2,b.z-b.d/2,b.z+b.d/2
    local id=b.id.."/furnishing"
    if b.id=="W2" then
        -- Same shop/storage/living programme as the source. The hall opening
        -- follows the tested stair approach; the back divider stops at the well.
        partition(id.."/shop_wall","x",-13.25,z0+.3,z1-.3,{{-3.58,1.8},{1.15,2.5}},nil,y)
        partition(id.."/back_wall","z",-1.24,-17.6,-13.36,-15.4,1.8,y)
        box(id.."/sofa/base","burlap",-16.2,y+.32,4,2.6,.64,1,"fabric")
        box(id.."/sofa/back","burlap",-16.2,y+.75,4.42,2.6,.75,.2)
        box(id.."/storage","wood",-15.6,y+.55,-6.6,2.3,1.1,1,"wood")
    elseif b.id=="E1" then
        partition(id.."/shop_wall","z",14.72,x0+.3,15.8,9.82,2.15,y)
        partition(id.."/store_wall","x",15.8,z0+.3,14.61,11.5,1.8,y)
        box(id.."/storage","wood",13.8,y+.6,10.1,2.2,1.2,1.2,"wood")
        box(id.."/storage/top","wood",13.45,y+1.5,10.2,1.2,.6,1.1,"wood")
    elseif b.id=="E3" then
        partition(id.."/store_wall","x",13.25,z0+.3,-19.6,-25.5,1.8,y)
        box(id.."/storage","wood",8,y+.5,-27.6,1.8,1,2.1,"wood")
        barrel(id.."/drum",18.9,y,-27.5)
        kit.box(id.."/fallen/slab","concrete",18.2,y+.45,-23,2.5,.9,2.4,"concrete")
        kit.box(id.."/fallen/sheet","corrugated",17.9,y+1,-23,2.8,.05,2.5,nil,nil,{rotation_x=.23,rotation_y=.18})
    elseif b.id=="E2" then
        box(id.."/stock","wood",19.4,y+.6,.5,1,1.2,1,"wood")
    end
    local corner_x=b.id=="W2" and x0+.85 or x1-.85
    if b.id~="E2" then box(id.."/corner/crate","wood",corner_x,y+.45,z1-.9,1,.9,1,"wood") end
    if not detail then return end
    local random=rng.new(seed,id)
    if b.counter then
        local c=b.counter;goods(id.."/counter/goods",x0+c.x*b.w,y+.96,z0+c.z*b.d,7)
        box(id.."/till","metal_painted",x0+c.x*b.w-c.w*.3,y+1.11,z0+c.z*b.d,.45,.3,.35)
    end
    if b.shelves then
        local s=b.shelves
        for i=1,3 do goods(id.."/shelf/"..i,x0+s.x*b.w,y+i*.6+.045,z0+s.z*b.d,9,true) end
        for _,s1 in ipairs({-1,1}) do box(id.."/shelf/upright/"..s1,"wood",x0+s.x*b.w,y+.95,z0+s.z*b.d+s1*b.shelves.d/2,.1,1.9,.1) end
    end
    if b.id=="W2" then kit.rug(id.."/living/rug",-16,y,3.2,2.2,1)
    elseif b.id=="E1" then kit.rug(id.."/shop/rug",11.8,y,19,3.4,2.1) end
    if b.id=="W2" then
        box(id.."/hall/shelf","wood",-13.55,y+1.2,-1.65,.4,.07,1.2)
        kit.solid("cylinder",id.."/hall/bucket","metal_painted",-13.55,y+1.46,-1.65,.34,.45,.34,nil,nil,{taper=1.2})
        for _,z in ipairs({-2.1,-1.2}) do box(id.."/hall/bracket/"..z,"metal",-13.44,y+1.04,z,.18,.3,.06) end
    end
    if b.ruin then
        rubble(id.."/rubble",18,y,-23,2,42,random)
        rubble(id.."/chips",8,y,-15.1,.8,14,random)
    end
    for level=0,(b.stairs and b.floors-1 or 0) do
        local fy=y+level*layout.storey
        local p=id.."/floor/"..level
        -- Ceiling beams and surface wiring remain attached to the shell.
        if not b.ruin then
            box(p.."/conduit","metal",b.x,fy+2.76,z1-.33,b.w-.6,.035,.035)
            box(p.."/conduit/drop","metal",b.x+1,fy+2,z1-.33,.035,1.5,.035)
            box(p.."/switch","metal_painted",b.x+1,fy+1.3,z1-.34,.16,.2,.07)
            kit.beam(p.."/bulb/cord","dark",{b.x,fy+layout.storey-layout.slab+.015,b.z+2},{b.x,fy+2.45,b.z+2},.018)
            kit.solid("cylinder",p.."/bulb/shade","metal",b.x,fy+2.45,b.z+2,.38,.12,.38,nil,nil,{taper=.45})
            kit.solid("cylinder",p.."/bulb","awning_cream",b.x,fy+2.34,b.z+2,.09,.13,.09)
            local shelf_x=b.id=="W2" and b.x-2.6 or b.x-2
            box(p.."/wall/shelf","wood",shelf_x,fy+1.65,z1-.45,2.4,.08,.3)
            goods(p.."/wall/goods",shelf_x,fy+1.69,z1-.45,6)
            for _,side in ipairs({-1,1}) do
                box(p.."/wall/bracket/"..side,"metal",shelf_x+side*.95,fy+1.51,z1-.4,.06,.24,.2)
            end
            box(p.."/wall/cloth","awning_red",shelf_x+2.1,fy+1.45,z1-.32,.7,1.3,.035)
            for j=1,3 do box(p.."/wall/cloth/stripe/"..j,"awning_cream",shelf_x+2.1,fy+.95+j*.27,z1-.345,.7,.055,.025) end
            box(p.."/leaning","corrugated",corner_x,fy+.8,z1-.5,.7,1.6,.025,nil,nil,{rotation_x=-.15})
        end
        if level>0 then
            local u=b.upper
            goods(p.."/desk/goods",u.desk.x,fy+.8,u.desk.z,3,true)
            box(p.."/bed/blanket","awning_red",u.bed.x,fy+.61,u.bed.z-.25,u.bed.w-.12,.025,u.bed.d*.55)
            for i=1,3 do box(p.."/cabinet/drawer/"..i,"metal",u.cabinet.x,fy+i*.42,u.cabinet.z-u.cabinet.d/2-.015,.25,.035,.035) end
            kit.rug(p.."/rug",u.rug.x,fy+.025,u.rug.z,u.rug.w*.9,u.rug.d*.9)
            box(p.."/chair/seat","wood",u.desk.x,fy+.42,u.desk.z+1,.6,.08,.6)
            box(p.."/chair/back","wood",u.desk.x,fy+.75,u.desk.z+1.27,.6,.65,.07)
            for _,dx in ipairs({-.24,.24}) do for _,dz in ipairs({-.24,.24}) do
                box(p.."/chair/leg/"..dx.."/"..dz,"wood",u.desk.x+dx,fy+.21,u.desk.z+1+dz,.055,.42,.055)
            end end
        end
        rubble(p.."/corner",x1-.7,fy,z1-.7,.4,5,random)
    end
end

local function wall_anchor(id,point,supports,mount)
    local best,normal,distance,mounting_wall
    local axes,sizes={"x","y","z"},{"w","h","d"}
    for _,wall in ipairs(supports) do
        for face=1,3 do for _,side in ipairs({-1,1}) do
            -- Laundry runs parallel to the street facade. Corner faces and
            -- ruin wall tops would pull its hanging span back into masonry.
            if not mount or (face==1 and side==mount.side) then
                local p={}
                for i,key in ipairs(axes) do
                    local half=wall[sizes[i]]/2
                    p[i]=i==face and wall[key]+side*half
                        or math.max(wall[key]-half+.03,math.min(wall[key]+half-.03,point[i]))
                end
                local d=(p[1]-point[1])^2+(p[2]-point[2])^2+(p[3]-point[3])^2
                if not distance or d<distance then
                    best,normal,distance,mounting_wall=p,{0,0,0},d,wall
                    normal[face]=side
                end
            end
        end end
    end
    assert(best,"Suspended dressing needs a structural wall anchor")
    -- Keep the wall fixing separate from the arm so both attachment points
    -- remain visible. Laundry needs room for trim, balconies and shop awnings.
    local center,size={},{}
    for i=1,3 do
        center[i]=best[i]+normal[i]*.025
        size[i]=normal[i]~=0 and .12 or .09
        best[i]=best[i]+normal[i]*.06
    end
    box(id,"metal_rust",center[1],center[2],center[3],size[1],size[2],size[3],nil,nil,{unclipped=true})
    if mount then
        local tip={best[1]+mount.side*(mount.offset-.06),best[2],best[3]}
        kit.beam(id.."/arm","metal_rust",best,tip,.045)
        if mount.offset>.6 then
            local brace_z=best[3]+(best[3]<mounting_wall.z and .25 or -.25)
            brace_z=math.max(mounting_wall.z-mounting_wall.d/2+.03,
                math.min(mounting_wall.z+mounting_wall.d/2-.03,brace_z))
            kit.beam(id.."/brace","metal_rust",{best[1],best[2],brace_z},
                {tip[1]-mount.side*.15,tip[2],tip[3]},.035)
            box(id.."/brace_mount","metal_rust",center[1],center[2],brace_z,
                size[1],size[2],size[3],nil,nil,{unclipped=true})
        end
        return tip
    end
    return best
end

function M.generate(layout,detail,seed,supports)
    seed=seed or layout.seed
    local d=layout.dressing or {}
    local function base(x) return math.abs(x)>=layout.street.half_width and math.abs(x)<=layout.street.kerb and layout.street.walk_height or 0 end
    for _,b in ipairs(layout.buildings) do if b.room then furnish(layout,b,detail,seed) end end
    for i,p in ipairs(d.jerseys or {}) do
        local id="dressing/jersey/"..i;local x,z=p[1],p[2]
        box(id.."/core","concrete",x,.43,z,.55,.86,1.9,"concrete",{normal_x=x<0 and 1 or -1,normal_z=0})
        kit.prism(id,"concrete",{{x-.4,0},{x+.4,0},{x+.4,.18},{x+.19,.57},{x+.16,.92},{x-.16,.92},{x-.19,.57},{x-.4,.18}},z,1.95)
        if detail then for _,s in ipairs({-1,1}) do box(id.."/reflector/"..s,"awning_cream",x+s*.17,.75,z,.015,.11,.4) end end
    end
    for i,p in ipairs(d.sandbags or {}) do
        kit.bags("dressing/bags/"..i,p[1],0,p[2],p[3],4,{normal_x=0,normal_z=i==2 and -1 or 1})
    end
    for i,p in ipairs(d.wrecks or {}) do
        local id="dressing/wreck/"..i;local x,z,y=p[1],p[2],base(p[1])
        kit.solid("bevel",id.."/body","metal_rust",x,y+.55,z,1.85,.65,4.1,"metal",{normal_x=x<0 and 1 or -1,normal_z=0,ground_y=0},{bevel=.16})
        box(id.."/cabin","dark",x,y+1.06,z-.2,1.5,.54,1.8,"metal")
        kit.solid("bevel",id.."/roof","metal_rust",x,y+1.37,z-.25,1.65,.13,1.85)
        for _,s in ipairs({-1,1}) do
            box(id.."/pillar/front/"..s,"metal_rust",x+s*.77,y+1.06,z-.95,.1,.55,.1)
            box(id.."/pillar/back/"..s,"metal_rust",x+s*.77,y+1.06,z+.58,.1,.55,.1)
            for _,t in ipairs({-1,1}) do
                kit.solid("torus",id.."/wheel/"..s.."/"..t,"rubber",x+s*.94,y+.35,z+t*1.25,.7,.23,.7,nil,nil,{rotation_z=math.pi/2})
                kit.solid("cylinder",id.."/hub/"..s.."/"..t,"metal",x+s*1.065,y+.35,z+t*1.25,.29,.035,.29,nil,nil,{rotation_z=math.pi/2})
            end
        end
        kit.box(id.."/hood","metal_rust",x,y+.97,z+1.2,1.75,.06,1.3,nil,nil,{rotation_x=.15})
        box(id.."/bumper","metal",x,y+.4,z+2.08,1.85,.13,.14)
    end
    for i,p in ipairs(d.palms or {}) do
        local id="dressing/palm/"..i;local x,z,s=p[1],p[2],p[3];local y=base(x)
        kit.solid("cylinder",id.."/trunk","wood",x,y+3.3*s,z,.35*s,6.6*s,.35*s,"wood",nil,{taper=.7})
        for j=0,14 do
            local upper=j>=9
            local a=(upper and (j-9)*math.pi/3+.35 or j*math.pi*2/9)+i*.47
            local length=(upper and 2.45 or 3.7)*(1+.07*math.sin(j*2.1+i))*s
            local drop=(upper and .55 or 1.55)*s
            -- Every stem starts at the crown; a shorter raised tier fills its centre.
            kit.solid("frond",id.."/frond/"..j,"foliage",x+math.sin(a)*length/2,y+6.6*s-drop/2,z+math.cos(a)*length/2,
                (upper and 1.05 or 1.3)*s,drop,length,nil,nil,{rotation_y=a})
        end
        if detail then for j=1,9 do kit.solid("cylinder",id.."/ring/"..j,"wood",x,y+j*.65*s,z,.37*s,.08,.37*s) end end
    end
    for i,p in ipairs(d.lamps or {}) do
        local id="dressing/lamp/"..i;local x,z=p[1],p[2];local y=base(x);local side=x<0 and 1 or -1
        kit.solid("cylinder",id.."/post","metal_painted",x,y+2.7,z,.11,5.4,.11,"metal")
        kit.beam(id.."/arm","metal",{x,y+5.35,z},{x+side*1.2,y+5.55,z},.07)
        kit.solid("bevel",id.."/head","metal",x+side*1.2,y+5.5,z,.65,.18,.32)
        box(id.."/lens","awning_cream",x+side*1.2,y+5.4,z,.53,.025,.25)
    end
    for i,p in ipairs(d.tyres or {}) do
        local id="dressing/tyres/"..i;local y=base(p[1])
        box(id.."/core","rubber",p[1],y+p[3]*.12,p[2],.62,p[3]*.24,.62,"rubber")
        for j=1,p[3] do kit.solid("torus",id.."/"..j,"rubber",p[1],y+(j-.5)*.25,p[2],.85,.25,.85) end
    end
    if not detail then return end
    for i,p in ipairs(d.cables or {}) do
        local id="dressing/cable/"..i
        kit.cable(id,wall_anchor(id.."/anchor/start",{p[1],p[2],p[3]},supports),wall_anchor(id.."/anchor/end",{p[4],p[5],p[6]},supports),p[7])
    end
    for i,p in ipairs(d.laundry or {}) do
        local id="dressing/laundry/"..i
        local mount={side=p[1]<0 and 1 or -1,offset=p.stand_off or .4}
        local a=wall_anchor(id.."/anchor/start",{p[1],p[2],p[3]},supports,mount)
        local b=wall_anchor(id.."/anchor/end",{p[4],p[5],p[6]},supports,mount)
        kit.cable(id,a,b,.18)
        local yaw=math.atan2(b[1]-a[1],b[3]-a[3])
        for j=1,4 do
            local t=j/5;local y=a[2]+(b[2]-a[2])*t-.18*4*t*(1-t)
            kit.box(id.."/cloth/"..j,j%2==0 and "awning_cream" or "awning_red",a[1]+(b[1]-a[1])*t,y-.475,a[3]+(b[3]-a[3])*t,
                .025,.95,.65,nil,nil,{rotation_y=yaw})
        end
    end
    for i,p in ipairs(d.rubble or {}) do rubble("dressing/rubble/"..i,p[1],base(p[1]),p[2],p[3],p[4],rng.new(seed,"rubble/"..i)) end
    -- Cluster crates, sacks, trays and small refuse at the authored stalls.
    for i,p in ipairs(layout.stalls) do
        local id="dressing/stall/"..i
        local random=rng.new(seed,id)
        local width=p.w-.25
        box(id.."/tray","wood",p.x,.93,p.z,width,.06,.65)
        for _,side in ipairs({-1,1}) do
            box(id.."/tray/rim/"..side,"wood",p.x,1.005,p.z+side*.315,width,.15,.025)
        end
        for j=0,2 do box(id.."/tray/divider/"..j,"wood",p.x-width/2+j*width/2,1.005,p.z,.025,.15,.65) end
        for j=1,12 do
            local col,row=(j-1)%6,math.floor((j-1)/6)
            local px=p.x-width/2+(col+.5)*width/6+(random()-.5)*.035
            local pz=p.z+(row-.5)*.26+(random()-.5)*.04
            local h=.12+random()*.055
            local material=({"produce_red","produce_green","produce_gold"})[(i+math.floor(col/3))%3+1]
            kit.solid("bevel",id.."/fruit/"..j,material,px,.96+h/2,pz,.14,h,.15,nil,nil,
                {bevel=.07,rotation_y=random()*math.pi})
        end
        local sx=p.x+math.min(.5,p.w*.26)
        kit.solid("bevel",id.."/sack","burlap",sx,.29,p.z+.75,.55,.58,.48,nil,nil,{bevel=.19,rotation_y=(random()-.5)*.35})
        kit.solid("cylinder",id.."/sack/tie","wood",sx+.035,.59,p.z+.75,.13,.065,.12,nil,nil,{taper=.55})
        local bx=p.x-math.min(.6,p.w*.32)
        kit.solid("cylinder",id.."/bucket","metal_painted",bx,.2,p.z+.72,.35,.4,.35,nil,nil,{taper=1.12})
        kit.solid("cylinder",id.."/bucket/inside","dark",bx,.402,p.z+.72,.34,.008,.34)
        kit.solid("torus",id.."/bucket/rim","metal",bx,.41,p.z+.72,.40,.035,.40)
        -- Refuse stays tucked beneath existing tables, clear of authored routes.
        for j=1,3 do
            kit.box(id.."/paper/"..j,"awning_cream",p.x+(random()-.5)*width,.009,p.z+(random()-.5)*.6,
                .12+random()*.12,.012,.14,nil,nil,{rotation_y=random()*math.pi})
        end
    end
    for i,p in ipairs({{-19,8.9},{19.6,3.1},{-20.4,-11.3},{26.5,-26.5}}) do
        -- Fixed solid crates/covers already own these wall-side footprints;
        -- smaller clutter is purely visual and cannot close a route.
        box("dressing/pallet/"..i,"wood",p[1],.08,p[2],1.4,.16,.9)
        goods("dressing/pallet/goods/"..i,p[1],.16,p[2],4)
    end
    kit.rug("dressing/courtyard/rug",-16.2,.005,8.5,2.3,1.1)
end
return M
