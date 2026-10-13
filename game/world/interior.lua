-- Shared dimensions for W2's floor opening, stairs, landings and layered routes.
local M = {}

function M.describe(layout, b)
    local s = assert(b.stairs, "Enterable building needs stairs")
    assert(b.floors == 2, "This interior recipe supports two floors")
    local base, upper = layout.street.walk_height, layout.street.walk_height + layout.storey
    local stair = { x = s.x, z0 = s.z - s.run, z1 = s.z,
        x0 = s.x - s.hole_width/2, x1 = s.x + s.hole_width/2,
        width = s.width, tread = s.run/s.steps, rise = layout.storey/s.steps,
        steps = s.steps, base = base, upper = upper }
    stair.bottom = { x = s.x, y = base, z = stair.z1 + s.landing }
    stair.top = { x = s.x, y = upper, z = stair.z0 - s.landing }
    local x0, x1, z0, z1 = b.x-b.w/2, b.x+b.w/2, b.z-b.d/2, b.z+b.d/2
    assert(stair.x0 > x0+layout.wall and stair.x1 < x1-layout.wall)
    assert(stair.top.z > z0+layout.wall+.32 and stair.bottom.z < z1-layout.wall-.32)
    assert(stair.width >= .64 and stair.rise <= .42 and stair.tread > .32)
    -- The four slabs leave a genuine hole, including standing headroom over the flight.
    stair.slabs = {
        { id = "west", x0 = x0, x1 = stair.x0, z0 = z0, z1 = z1 },
        { id = "east", x0 = stair.x1, x1 = x1, z0 = z0, z1 = z1 },
        { id = "landing", x0 = stair.x0, x1 = stair.x1, z0 = z0, z1 = stair.z0 },
        { id = "bottom", x0 = stair.x0, x1 = stair.x1, z0 = stair.z1, z1 = z1 },
    }
    return stair
end

function M.geometry(layout, b, box)
    local s, u = M.describe(layout,b), b.upper
    local wall, slab, storey = layout.wall, layout.slab, layout.storey
    local x0, x1, z0, z1 = b.x-b.w/2, b.x+b.w/2, b.z-b.d/2, b.z+b.d/2
    local prefix = b.id .. "/upper/"
    for _, r in ipairs(s.slabs) do
        box(prefix.."floor/"..r.id,"concrete",(r.x0+r.x1)/2,s.upper-slab/2,(r.z0+r.z1)/2,
            r.x1-r.x0,slab,r.z1-r.z0,"concrete")
    end
    for i=1,s.steps do
        local h = i*s.rise
        box(b.id.."/stair/"..i,"concrete",s.x,s.base+h/2,s.z1-(i-.5)*s.tread,
            s.width,h,s.tread,"concrete")
    end
    -- Solid guards surround the opening on three sides; the upper landing stays open.
    for _, x in ipairs({s.x0-.06,s.x1+.06}) do
        box(prefix.."guard/"..x,"wood",x,s.upper+.55,(s.z0+s.z1)/2,.12,1.1,s.z1-s.z0,"wood")
        box(prefix.."handrail/"..x,"wood",x,s.upper+1.13,(s.z0+s.z1)/2,.18,.08,s.z1-s.z0)
    end
    box(prefix.."guard/end","wood",s.x,s.upper+.55,s.z1+.06,s.x1-s.x0,1.1,.12,"wood")
    for _, side in ipairs({{"west",x0+wall/2},{"east",x1-wall/2}}) do
        box(prefix..side[1],b.material,side[2],s.upper+storey/2,b.z,wall,storey,b.d,"plaster")
    end
    for _, side in ipairs({{"south",z0+wall/2},{"north",z1-wall/2}}) do
        box(prefix..side[1],b.material,b.x,s.upper+storey/2,side[2],b.w,storey,wall,"plaster")
    end
    box(b.id.."/roof","concrete",b.x,s.upper+storey-slab/2,b.z,b.w,slab,b.d,"concrete")
    -- Split each partition around a full-height open doorway with a lintel.
    local function partition(id, axis, fixed, lo, hi, door, width)
        local function piece(name, a, c, y, h)
            box(prefix..id.."/"..name,"plaster_inside",axis=="x" and fixed or (a+c)/2,y,
                axis=="x" and (a+c)/2 or fixed,axis=="x" and wall or c-a,h,
                axis=="x" and c-a or wall,"plaster")
        end
        piece("left",lo,door-width/2,s.upper+storey/2,storey)
        piece("right",door+width/2,hi,s.upper+storey/2,storey)
        piece("lintel",door-width/2,door+width/2,s.upper+(storey+u.door_height)/2,storey-u.door_height)
    end
    partition("hall_door","x",u.partition_x,z0+wall,z1-wall,u.door_z,u.door_width)
    partition("bedroom_door","z",u.bedroom_z,u.partition_x,x1-wall,u.bedroom_door_x,u.bedroom_door_width)
    local bed,desk,cabinet,rug=u.bed,u.desk,u.cabinet,u.rug
    box(prefix.."bed/frame","wood",bed.x,s.upper+.23,bed.z,bed.w,.46,bed.d,"wood")
    box(prefix.."bed/mattress","awning_cream",bed.x,s.upper+.53,bed.z,bed.w-.1,.14,bed.d-.1,"fabric")
    box(prefix.."bed/pillow","awning_cream",bed.x,s.upper+.65,bed.z+bed.d/2-.5,bed.w*.65,.12,.55)
    box(prefix.."desk","wood",desk.x,s.upper+.4,desk.z,desk.w,.8,desk.d,"wood")
    box(prefix.."cabinet","wood",cabinet.x,s.upper+.8,cabinet.z,cabinet.w,1.6,cabinet.d,"wood")
    box(prefix.."rug","awning_red",rug.x,s.upper+.012,rug.z,rug.w,.024,rug.d)
end

function M.navigation(layout,b,nav)
    local s,u=M.describe(layout,b),b.upper
    nav.stairs=nav.stairs or {}
    local flight={x0=s.x-s.width/2,x1=s.x+s.width/2,z0=s.z0,z1=s.z1,
        bottom=s.base,top=s.upper}
    nav.stairs[#nav.stairs+1]=flight
    local function node(id,x,y,z,layer)
        id=b.id.."/"..id
        nav.nodes[#nav.nodes+1]={id=id,x=x,y=y,z=z,layer=layer}
        return id
    end
    local function edge(a,c,kind)
        nav.edges[#nav.edges+1]={from=a,to=c,kind=kind or "walk"}
    end
    local approach=node("stair_approach",s.x1+1.2,s.base,s.bottom.z,0)
    local bottom=node("stair_bottom",s.bottom.x,s.bottom.y,s.bottom.z,0)
    edge("room",approach);edge(approach,bottom)
    local previous=bottom
    for i=1,s.steps do
        local id=node("stair/"..i,s.x,s.base+i*s.rise,s.z1-(i-.5)*s.tread,0)
        nav.nodes[#nav.nodes].stair=#nav.stairs
        edge(previous,id,"stairs");previous=id
        nav.surfaces[#nav.surfaces+1]={id=id,layer=0,y=s.base+i*s.rise,
            x0=s.x-s.width/2,x1=s.x+s.width/2,z0=s.z1-i*s.tread,z1=s.z1-(i-1)*s.tread}
    end
    local top=node("stair_top",s.top.x,s.top.y,s.top.z,1)
    local hall=node("upper_hall",u.partition_x-1,s.upper,u.door_z,1)
    local door=node("upper_door",u.partition_x,s.upper,u.door_z,1)
    local room=node("upper_room",u.bedroom_door_x,s.upper,u.door_z,1)
    local bedroom_door=node("bedroom_door",u.bedroom_door_x,s.upper,u.bedroom_z,1)
    local bedroom=node("bedroom",u.bedroom_door_x,s.upper,u.bedroom_z+1,1)
    edge(previous,top,"stairs");edge(top,hall);edge(hall,door,"doorway");edge(door,room)
    edge(room,bedroom_door,"doorway");edge(bedroom_door,bedroom)
    for _,e in ipairs(nav.edges) do
        if e.to==door or e.to==bedroom_door then
            e.width=e.to==door and u.door_width or u.bedroom_door_width;e.height=u.door_height
        end
    end
    for _,r in ipairs(s.slabs) do
        nav.surfaces[#nav.surfaces+1]={id=b.id.."/upper/"..r.id,layer=1,y=s.upper,
            x0=r.x0,x1=r.x1,z0=r.z0,z1=r.z1}
    end
end

function M.lights(layout,b)
    local base,storey,wall=layout.street.walk_height,layout.storey,layout.wall
    local x0,x1,z0,z1=b.x-b.w/2+wall,b.x+b.w/2-wall,b.z-b.d/2+wall,b.z+b.d/2-wall
    local function room(x,z,y,lo,hi,floor,radius,intensity,colour)
        return {kind="room",x=x,y=y,z=z,radius=radius,intensity=intensity,colour=colour,
            minimum={x=lo,y=floor,z=z0},maximum={x=hi,y=floor+storey-layout.slab,z=z1}}
    end
    return {
        room(b.x+2,b.door.z,base+2.55,x0,x1,base,6,16,{1,.76,.48}),
        room((x0+b.upper.partition_x)/2,b.z,base+storey+2.55,x0,b.upper.partition_x-wall/2,base+storey,7,18,{1,.82,.6}),
        room((x1+b.upper.partition_x)/2,b.z,base+storey+2.55,b.upper.partition_x+wall/2,x1,base+storey,8,18,{1,.84,.65}),
    }
end
return M
