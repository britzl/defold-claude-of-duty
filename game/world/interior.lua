-- Shared dimensions for each floor opening, stair flight and layered route.
-- side faces the street (+X/-X); stairs.direction is the ascent direction on Z.
local M = {}
local architecture=require "game.world.architecture"

function M.prefix(b, level)
    return b.id .. (level == 1 and "/" or "/floor" .. level .. "/")
end

local function upper(b, level)
    return b.uppers and assert(b.uppers[level], "Missing upper floor recipe") or b.upper
end

function M.describe(layout, b, level)
    level = level or 1
    local s = assert(b.stairs, "Enterable building needs stairs")
    assert(level >= 1 and level < b.floors, "Invalid stair floor")
    local base = layout.street.walk_height + (level-1)*layout.storey
    local upper = base + layout.storey
    local direction = s.direction or -1
    assert(direction == -1 or direction == 1)
    local finish = s.z + direction*s.run
    local stair = { x = s.x, z0 = math.min(s.z,finish), z1 = math.max(s.z,finish),
        start = s.z, finish = finish, direction = direction,
        x0 = s.x - s.hole_width/2, x1 = s.x + s.hole_width/2,
        width = s.width, tread = s.run/s.steps, rise = layout.storey/s.steps,
        steps = s.steps, base = base, upper = upper }
    stair.bottom = { x = s.x, y = base, z = s.z - direction*s.landing }
    stair.top = { x = s.x, y = upper, z = finish + direction*s.landing }
    local x0, x1, z0, z1 = b.x-b.w/2, b.x+b.w/2, b.z-b.d/2, b.z+b.d/2
    assert(stair.x0 > x0+layout.wall and stair.x1 < x1-layout.wall)
    assert(math.min(stair.top.z,stair.bottom.z) > z0+layout.wall+.32
        and math.max(stair.top.z,stair.bottom.z) < z1-layout.wall-.32)
    assert(stair.width >= .64 and stair.rise <= .42 and stair.tread > .32)
    -- The four slabs leave a genuine hole, including standing headroom over the flight.
    stair.slabs = {
        { id = "west", x0 = x0, x1 = stair.x0, z0 = z0, z1 = z1 },
        { id = "east", x0 = stair.x1, x1 = x1, z0 = z0, z1 = z1 },
        { id = direction == -1 and "landing" or "bottom", x0 = stair.x0, x1 = stair.x1, z0 = z0, z1 = stair.z0 },
        { id = direction == -1 and "bottom" or "landing", x0 = stair.x0, x1 = stair.x1, z0 = stair.z1, z1 = z1 },
    }
    return stair
end

local function floor_geometry(layout, b, level, box)
    b=architecture.floor_spec(b,level)
    local s, u = M.describe(layout,b,level), upper(b,level)
    local node_prefix = M.prefix(b,level)
    local wall, slab, storey = layout.wall, layout.slab, layout.storey
    local wall_height = storey - slab
    local x0, x1, z0, z1 = b.x-b.w/2, b.x+b.w/2, b.z-b.d/2, b.z+b.d/2
    local prefix = level == 1 and b.id .. "/upper/" or node_prefix
    for _, r in ipairs(s.slabs) do
        box(prefix.."floor/"..r.id,"concrete_floor",(r.x0+r.x1)/2,s.upper-slab/2,(r.z0+r.z1)/2,
            r.x1-r.x0,slab,r.z1-r.z0,"concrete")
    end
    for i=1,s.steps do
        local h = i*s.rise
        -- Upper flights use thin treads so the flight below retains headroom.
        local thickness = level == 1 and h or slab
        box(node_prefix.."stair/"..i,"concrete_floor",s.x,s.base+h-thickness/2,s.start+s.direction*(i-.5)*s.tread,
            s.width,thickness,s.tread,"concrete")
    end
    -- Solid guards surround the opening on three sides; the upper landing stays open.
    for _, x in ipairs({s.x0-.06,s.x1+.06}) do
        box(prefix.."guard/"..x,"wood",x,s.upper+.55,(s.z0+s.z1)/2,.12,1.1,s.z1-s.z0,"wood")
        box(prefix.."handrail/"..x,"wood",x,s.upper+1.13,(s.z0+s.z1)/2,.18,.08,s.z1-s.z0)
    end
    if level == b.floors-1 then
        box(prefix.."guard/end","wood",s.x,s.upper+.55,s.start-s.direction*.06,s.x1-s.x0,1.1,.12,"wood")
    end
    for _, side in ipairs({{"west",x0+wall/2},{"east",x1-wall/2}}) do
        if (side[1]=="west" and b.side==-1) or (side[1]=="east" and b.side==1) then
            architecture.window_wall(layout,b,level,box)
        else box(prefix..side[1],b.material,side[2],s.upper+wall_height/2,b.z,wall,wall_height,b.d,"plaster") end
    end
    for _, side in ipairs({{"south",z0+wall/2},{"north",z1-wall/2}}) do
        box(prefix..side[1],b.material,b.x,s.upper+wall_height/2,side[2],b.w-2*wall,wall_height,wall,"plaster")
    end
    if level == b.floors-1 then
        box(b.id.."/roof","concrete_floor",b.x,s.upper+storey-slab/2,b.z,b.w,slab,b.d,"concrete")
    end
    -- Split each partition around a full-height open doorway with a lintel.
    local function partition(id, axis, fixed, lo, hi, door, width)
        local function piece(name, a, c, y, h)
            box(prefix..id.."/"..name,"plaster_inside",axis=="x" and fixed or (a+c)/2,y,
                axis=="x" and (a+c)/2 or fixed,axis=="x" and wall or c-a,h,
                axis=="x" and c-a or wall,"plaster")
        end
        piece("left",lo,door-width/2,s.upper+wall_height/2,wall_height)
        piece("right",door+width/2,hi,s.upper+wall_height/2,wall_height)
        piece("lintel",door-width/2,door+width/2,s.upper+(wall_height+u.door_height)/2,wall_height-u.door_height)
    end
    partition("hall_door","x",u.partition_x,z0+wall,z1-wall,u.door_z,u.door_width)
    partition("bedroom_door","z",u.bedroom_z,b.side == 1 and u.partition_x or x0+wall,
        b.side == 1 and x1-wall or u.partition_x,u.bedroom_door_x,u.bedroom_door_width)
    local bed,desk,cabinet,rug=u.bed,u.desk,u.cabinet,u.rug
    box(prefix.."bed/frame","wood",bed.x,s.upper+.23,bed.z,bed.w,.46,bed.d,"wood")
    box(prefix.."bed/mattress","awning_cream",bed.x,s.upper+.53,bed.z,bed.w-.1,.14,bed.d-.1,"fabric")
    box(prefix.."bed/pillow","awning_cream",bed.x,s.upper+.65,bed.z+bed.d/2-.5,bed.w*.65,.12,.55)
    box(prefix.."desk","wood",desk.x,s.upper+.4,desk.z,desk.w,.8,desk.d,"wood")
    box(prefix.."cabinet","wood",cabinet.x,s.upper+.8,cabinet.z,cabinet.w,1.6,cabinet.d,"wood")
    box(prefix.."rug","awning_red",rug.x,s.upper+.012,rug.z,rug.w,.024,rug.d)
end

function M.geometry(layout,b,box)
    if not b.stairs then
        architecture.ruin(layout,b)
        return
    end
    for level=1,b.floors-1 do floor_geometry(layout,b,level,box) end
end

local function floor_navigation(layout,b,level,nav,entry)
    b=architecture.floor_spec(b,level)
    local s,u=M.describe(layout,b,level),upper(b,level)
    nav.stairs=nav.stairs or {}
    local flight={x0=s.x-s.width/2,x1=s.x+s.width/2,z0=s.z0,z1=s.z1,
        bottom=s.base,top=s.upper}
    nav.stairs[#nav.stairs+1]=flight
    local function node(id,x,y,z,layer)
        id=M.prefix(b,level)..id
        nav.nodes[#nav.nodes+1]={id=id,x=x,y=y,z=z,layer=layer}
        return id
    end
    local function edge(a,c,kind)
        nav.edges[#nav.edges+1]={from=a,to=c,kind=kind or "walk"}
    end
    local approach=node("stair_approach",s.x+b.side*((s.x1-s.x0)/2+1.2),s.base,s.bottom.z,level-1)
    local bottom=node("stair_bottom",s.bottom.x,s.bottom.y,s.bottom.z,level-1)
    edge(entry,approach);edge(approach,bottom)
    local previous=bottom
    for i=1,s.steps do
        local id=node("stair/"..i,s.x,s.base+i*s.rise,s.start+s.direction*(i-.5)*s.tread,level-1)
        nav.nodes[#nav.nodes].stair=#nav.stairs
        edge(previous,id,"stairs");previous=id
        nav.surfaces[#nav.surfaces+1]={id=id,layer=level-1,y=s.base+i*s.rise,
            x0=s.x-s.width/2,x1=s.x+s.width/2,z0=math.min(s.start+s.direction*i*s.tread,s.start+s.direction*(i-1)*s.tread),
            z1=math.max(s.start+s.direction*i*s.tread,s.start+s.direction*(i-1)*s.tread)}
    end
    local top=node("stair_top",s.top.x,s.top.y,s.top.z,level)
    local hall=node("upper_hall",u.partition_x-b.side,s.upper,u.door_z,level)
    local door=node("upper_door",u.partition_x,s.upper,u.door_z,level)
    local room=node("upper_room",u.bedroom_door_x,s.upper,u.door_z,level)
    local bedroom_door=node("bedroom_door",u.bedroom_door_x,s.upper,u.bedroom_z,level)
    local bedroom=node("bedroom",u.bedroom_door_x,s.upper,u.bedroom_z+(u.bedroom_side or 1),level)
    edge(previous,top,"stairs");edge(top,hall);edge(hall,door,"doorway");edge(door,room)
    edge(room,bedroom_door,"doorway");edge(bedroom_door,bedroom)
    for _,e in ipairs(nav.edges) do
        if e.to==door or e.to==bedroom_door then
            e.width=e.to==door and u.door_width or u.bedroom_door_width;e.height=u.door_height
        end
    end
    for _,r in ipairs(s.slabs) do
        nav.surfaces[#nav.surfaces+1]={id=M.prefix(b,level).."surface/"..r.id,layer=level,y=s.upper,
            x0=r.x0,x1=r.x1,z0=r.z0,z1=r.z1}
    end
end

function M.navigation(layout,b,nav,entry)
    local function ground(id,x,z,from)
        id=b.id.."/"..id
        nav.nodes[#nav.nodes+1]={id=id,x=x,y=layout.street.walk_height,z=z,layer=0}
        nav.edges[#nav.edges+1]={from=from,to=id,kind="walk"}
        return id
    end
    if b.id=="W2" then
        local approach=ground("shop_back",-11.8,-3.58,entry)
        local door=ground("storage_door",-13.25,-3.58,approach)
        ground("storage",-15.6,-3.58,door)
        ground("living",-16.2,3.1,b.id.."/stair_approach")
    elseif b.id=="E1" then ground("storage",11.5,12,entry)
    elseif b.id=="E3" then
        ground("storage",10,-25.5,entry)
        ground("ruin",16,-18.4,entry)
    end
    if not b.stairs then return end
    for level=1,b.floors-1 do
        floor_navigation(layout,b,level,nav,entry)
        entry=M.prefix(b,level).."upper_hall"
    end
end

function M.awning(layout,b)
    return {x=b.x+b.side*(b.w/2+.85),y=layout.street.walk_height+2.95,z=b.door.z,
        w=1.7,d=4.4,side=b.side}
end

-- Coarse indirect visibility, derived from the same shell/awning dimensions as
-- geometry. Footprint feather distinguishes outer and inner wall faces. The
-- roof terrace remains outdoors; floor slabs and every storey stay inside.
function M.lighting_volumes(layout,b)
    local base=layout.street.walk_height
    local a=M.awning(layout,b)
    return {
        {id=b.id,minimum={b.x-b.w/2,base-layout.slab-.3,b.z-b.d/2},
            maximum={b.x+b.w/2,base+b.floors*layout.storey-.06,b.z+b.d/2},
            params={b.ruin and .75 or require("game.render.daylight").indirect[3],.06,layout.wall,1},
            doorway={b.x+b.side*b.w/2,b.door.z,base,b.side},
            -- Diffuse room fill includes unresolved bounces; open roofs admit more sky.
            aperture={b.door.width,b.door.height,3,b.ruin and .85 or .60}},
        {id=b.id.."/awning",minimum={a.x-a.w/2,base-.5,a.z-a.d/2},
            maximum={a.x+a.w/2,a.y+.035,a.z+a.d/2},params={.45,.03,.25,0}},
    }
end

function M.lights(layout,b)
    local base,storey,wall=layout.street.walk_height,layout.storey,layout.wall
    local x0,x1,z0,z1=b.x-b.w/2+wall,b.x+b.w/2-wall,b.z-b.d/2+wall,b.z+b.d/2-wall
    local lights={}
    local function room(id,lo,hi,near,far,floor,colour)
        -- Low-energy diffuse bounces keep lamp shadows readable, also at night.
        lights[#lights+1]={id=b.id.."/"..id,kind="room",x=(lo+hi)/2,y=floor+2.55,z=(near+far)/2,
            radius=8,intensity=18,colour=colour,bounce=.012,
            minimum={x=lo,y=floor,z=near},maximum={x=hi,y=floor+storey-layout.slab,z=far}}
    end
    room("shop",x0,x1,z0,z1,base,{1,.76,.48})
    for level=1,(b.stairs and b.floors-1 or 0) do
        local u=upper(b,level)
        local floor=base+level*storey
        local hall0,hall1=b.side==1 and x0 or u.partition_x+wall/2,b.side==1 and u.partition_x-wall/2 or x1
        local room0,room1=b.side==1 and u.partition_x+wall/2 or x0,b.side==1 and x1 or u.partition_x-wall/2
        room(level.."/hall",hall0,hall1,z0,z1,floor,{1,.82,.6})
        room(level.."/south",room0,room1,z0,u.bedroom_z-wall/2,floor,{1,.84,.65})
        room(level.."/north",room0,room1,u.bedroom_z+wall/2,z1,floor,{1,.84,.65})
    end
    return lights
end
return M
