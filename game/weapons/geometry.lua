-- Runtime mesh recipes. Dimensions/attachments follow the reference weapons;
-- detail is deliberately bounded and merged into independently animated parts.
local V = require "game.weapons.math"
local M = {}
-- Vertex alpha identifies the generated combat surface (not opacity).
-- 0 steel, 1 coated metal, 2 polymer, 3 woven fabric, 4 skin, 5 rubber,
-- 6 camouflage fabric, 7 brass. All opaque parts retain full coverage.
M.colors={metal={.15,.18,.19,1},steel={.56,.59,.62,0},dark={.025,.032,.035,5},
    polymer={.085,.105,.10,2},tan={.33,.28,.18,3},skin={.50,.32,.22,4},glove={.22,.24,.18,3},
    light={.85,.91,.78,2},red={1,.08,.02,2},flash={1,.72,.22,2}}
function M.batch() return {positions={},normals={},colors={},vertex_count=0,bounds={math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge}} end
local function vertex(b,p,n,color)
    for i=1,3 do
        b.positions[#b.positions+1]=p[i];b.normals[#b.normals+1]=n[i]
        b.bounds[i]=math.min(b.bounds[i],p[i]);b.bounds[i+3]=math.max(b.bounds[i+3],p[i])
    end
    for i=1,4 do b.colors[#b.colors+1]=color[i] end
    b.vertex_count=b.vertex_count+1
end
local function triangle(b,a,c,d,n,color)
    vertex(b,a,n,color);vertex(b,c,n,color);vertex(b,d,n,color)
end
function M.box(b,x,y,z,w,h,d,color,rx)
    color=M.colors[color] or color
    local faces={
        {{1,0,0},{1,-1,-1},{1,1,-1},{1,1,1},{1,-1,1}},
        {{-1,0,0},{-1,-1,1},{-1,1,1},{-1,1,-1},{-1,-1,-1}},
        {{0,1,0},{-1,1,-1},{-1,1,1},{1,1,1},{1,1,-1}},
        {{0,-1,0},{-1,-1,1},{-1,-1,-1},{1,-1,-1},{1,-1,1}},
        {{0,0,1},{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}},
        {{0,0,-1},{1,-1,-1},{-1,-1,-1},{-1,1,-1},{1,1,-1}}}
    for _,f in ipairs(faces) do
        local n=V.rotate({x=f[1][1],y=f[1][2],z=f[1][3]},rx or 0,0,0)
        for _,i in ipairs({2,3,4,2,4,5}) do
            local p=V.rotate({x=f[i][1]*w/2,y=f[i][2]*h/2,z=f[i][3]*d/2},rx or 0,0,0)
            vertex(b,{x+p.x,y+p.y,z+p.z},{n.x,n.y,n.z},color)
        end
    end
end
-- A hollow tube with outward and inward faces and annular caps, along Z.
function M.tube(b,x,y,z,r,inner,length,color,segments)
    color=M.colors[color] or color
    local count=segments or 16
    for i=0,count-1 do
        local a,c=i/count*math.pi*2,(i+1)/count*math.pi*2
        local ca,sa,cc,sc=math.cos(a),math.sin(a),math.cos(c),math.sin(c)
        local n={math.cos((a+c)/2),math.sin((a+c)/2),0}
        local p={x+r*ca,y+r*sa,z-length/2};local q={x+r*cc,y+r*sc,z-length/2}
        local t={x+r*cc,y+r*sc,z+length/2};local u={x+r*ca,y+r*sa,z+length/2}
        triangle(b,p,q,t,n,color);triangle(b,p,t,u,n,color)
        local pi={x+inner*ca,y+inner*sa,z-length/2};local qi={x+inner*cc,y+inner*sc,z-length/2}
        local ti={x+inner*cc,y+inner*sc,z+length/2};local ui={x+inner*ca,y+inner*sa,z+length/2}
        if inner>0 then
            triangle(b,qi,pi,ui,{-n[1],-n[2],0},color);triangle(b,qi,ui,ti,{-n[1],-n[2],0},color)
        end
        triangle(b,q,p,pi,{0,0,-1},color);triangle(b,q,pi,qi,{0,0,-1},color)
        triangle(b,u,t,ti,{0,0,1},color);triangle(b,u,ti,ui,{0,0,1},color)
    end
end
-- Unit quad; normals face local +Z. Shared by billboards and surface decals.
function M.quad(b)
    b=b or M.batch()
    local n,c={0,0,1},{1,1,1,0}
    triangle(b,{-.5,-.5,0},{.5,-.5,0},{.5,.5,0},n,c)
    triangle(b,{-.5,-.5,0},{.5,.5,0},{-.5,.5,0},n,c)
    return b
end
-- Profile of elliptical rings along -Z, used for folded sleeves and gloves.
-- Faceted normals keep the small generated mesh independent of imported art.
function M.profile(b,rings,color,segments)
    color=M.colors[color] or color
    local count=segments or 10
    local function point(r,i)
        local a=i/count*math.pi*2
        return {math.cos(a)*r[2],math.sin(a)*r[3],-r[1]}
    end
    local function face(a,c,d)
        local ax,ay,az=c[1]-a[1],c[2]-a[2],c[3]-a[3]
        local bx,by,bz=d[1]-a[1],d[2]-a[2],d[3]-a[3]
        local n=V.normalize({x=ay*bz-az*by,y=az*bx-ax*bz,z=ax*by-ay*bx})
        triangle(b,a,c,d,{n.x,n.y,n.z},color)
    end
    for j=1,#rings-1 do for i=0,count-1 do
        local a,c,d,e=point(rings[j],i),point(rings[j+1],i),point(rings[j+1],i+1),point(rings[j],i+1)
        face(a,c,d);face(a,d,e)
    end end
    for i=0,count-1 do
        face({0,0,-rings[1][1]},point(rings[1],i),point(rings[1],i+1))
        face({0,0,-rings[#rings][1]},point(rings[#rings],i+1),point(rings[#rings],i))
    end
end

-- Chamfered box: six panels, twelve bevels and eight corner triangles.
function M.bevel(b,x,y,z,w,h,d,r,color)
    color=M.colors[color] or color
    local half={w/2,h/2,d/2};r=math.min(r,math.min(w,h,d)*.49)
    local function face(points)
        local a,c,e=points[1],points[2],points[3]
        local u={c[1]-a[1],c[2]-a[2],c[3]-a[3]}
        local v={e[1]-a[1],e[2]-a[2],e[3]-a[3]}
        local n=V.normalize({x=u[2]*v[3]-u[3]*v[2],y=u[3]*v[1]-u[1]*v[3],z=u[1]*v[2]-u[2]*v[1]})
        if n.x*a[1]+n.y*a[2]+n.z*a[3]<0 then
            local rev={};for i=#points,1,-1 do rev[#rev+1]=points[i] end;points=rev
            n.x,n.y,n.z=-n.x,-n.y,-n.z
        end
        for i=2,#points-1 do for _,p in ipairs({points[1],points[i],points[i+1]}) do
            vertex(b,{x+p[1],y+p[2],z+p[3]},{n.x,n.y,n.z},color)
        end end
    end
    for axis=1,3 do
        local j,k=axis%3+1,(axis+1)%3+1
        for _,s in ipairs({-1,1}) do
            local pts={}
            for _,q in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
                local p={0,0,0};p[axis]=s*half[axis];p[j]=q[1]*(half[j]-r);p[k]=q[2]*(half[k]-r);pts[#pts+1]=p
            end
            face(pts)
        end
        for _,sj in ipairs({-1,1}) do for _,sk in ipairs({-1,1}) do
            local pts={}
            for _,q in ipairs({{-1,0},{1,0},{1,1},{-1,1}}) do
                local p={0,0,0};p[axis]=q[1]*(half[axis]-r)
                p[j]=sj*(half[j]-(q[2]==0 and 0 or r));p[k]=sk*(half[k]-(q[2]==0 and r or 0));pts[#pts+1]=p
            end
            face(pts)
        end end
    end
    for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
        local pts={};local signs={sx,sy,sz}
        for axis=1,3 do
            local p={};for j=1,3 do p[j]=signs[j]*(half[j]-(axis==j and 0 or r)) end;pts[#pts+1]=p
        end
        face(pts)
    end end end
end

M.part_names={"body","magazine","bolt","charge","trigger","selector","reticle","flash"}
function M.weapon(id)
    local pistol=id=="pistol"
    local smg=id=="smg"
    local bore=pistol and .036 or smg and .068 or .075
    local muzzle=pistol and -.153 or smg and -.330 or -.502
    local sight=pistol and .070 or smg and .123 or .142
    local parts={}
    for _,name in ipairs(M.part_names) do parts[name]=M.batch() end
    local b=parts.body
    if pistol then
        M.box(b,0,.003,-.04,.029,.045,.15,"polymer")
        M.box(b,0,-.047,.012,.028,.115,.04,"polymer",-.24)
        M.box(b,0,-.031,-.038,.029,.008,.047,"dark")
        M.box(b,0,-.016,-.061,.029,.034,.008,"polymer")
        M.tube(b,0,bore,muzzle+.026,.007,.0045,.052,"steel")
        M.bevel(parts.bolt,0,bore,-.0395,.0262,.0248,.183,.002,"metal")
        for i=0,6 do M.box(parts.bolt,0,bore+.016,.015-i*.004,.032,.002,.0018,"dark") end
        -- Open reflex hood so ADS has a genuine sight picture.
        M.box(parts.bolt,0,sight-.015,.012,.029,.005,.018,"dark")
        M.box(parts.bolt,-.016,sight,.012,.003,.031,.018,"dark")
        M.box(parts.bolt,.016,sight,.012,.003,.031,.018,"dark")
        M.box(parts.bolt,0,sight+.016,.012,.035,.003,.018,"dark")
        M.box(parts.reticle,0,sight,.006,.0016,.0016,.0016,"red")
        M.box(parts.charge,0,.012,.016,.025,.007,.01,"dark")
        M.box(parts.magazine,0,-.045,.012,.024,.096,.032,"dark",-.24)
        M.box(parts.magazine,0,-.097,.024,.030,.010,.040,"polymer")
    else
        local fore=smg and -.200 or -.290
        local fore_len=smg and .125 or .235
        M.tube(b,0,bore,-.045,smg and .0158 or .0192,0,smg and .174 or .198,"metal")
        M.bevel(b,0,bore-.025,-.036,smg and .027 or .0245,.045,.133,.003,"metal")
        M.box(b,0,-.031,.021,.031,.10,.045,"polymer",-.30)
        M.box(b,0,-.007,-.032,.032,.007,.052,"dark")
        M.box(b,0,.006,-.061,.032,.028,.008,"metal")
        -- Open handguard: chassis rings, longitudinal panels and separated
        -- rail teeth leave real ventilation slots instead of painted holes.
        for i=0,4 do M.tube(b,0,bore,fore+fore_len*(i/4-.5),smg and .022 or .027,.018,.008,"metal",12) end
        for _,s in ipairs({-1,1}) do
            M.bevel(b,s*.021,bore-.009,fore,.012,.018,fore_len,.003,"polymer")
            M.bevel(b,s*.017,bore+.018,fore,.014,.012,fore_len,.002,"metal")
        end
        M.bevel(b,0,bore-.024,fore,.028,.009,fore_len,.002,"polymer")
        M.tube(b,0,bore,(fore-fore_len/2+muzzle)/2,.009,.0045,fore-fore_len/2-muzzle,"steel")
        M.tube(b,0,bore,muzzle+.013,.013,.006,.026,"dark")
        for i=0,5 do
            M.box(b,.028,bore,fore+fore_len*.42-i*fore_len/6,.003,.013,.015,"dark")
            M.box(b,-.028,bore,fore+fore_len*.42-i*fore_len/6,.003,.013,.015,"dark")
        end
        M.bevel(b,0,bore+.027,-.095,.030,.008,.235,.001,"metal")
        for i=0,21 do M.box(b,0,bore+.033,.017-i*.010,.040,.004,.004,"dark") end
        M.tube(b,0,bore,.11,.015,0,.15,"metal")
        if smg then
            M.box(b,-.017,bore-.005,.13,.009,.016,.15,"steel")
            M.box(b,.017,bore-.005,.13,.009,.016,.15,"steel")
        else M.box(b,0,bore-.025,.17,.042,.072,.11,"polymer") end
        M.box(b,0,bore-.030,.233,.045,.105,.018,"dark")
        -- Hollow optic and raised mount; no opaque glass blocks the scene.
        M.box(b,0,sight-.032,-.020,.025,.020,.035,"dark")
        M.tube(b,0,sight,-.020,smg and .015 or .017,smg and .012 or .014,smg and .044 or .052,"dark",24)
        M.box(parts.reticle,0,sight,-.046,.001,.001,.001,"red")
        M.box(parts.charge,0,bore+.017,.068,.057,.008,.015,"steel")
        M.box(b,.024,bore,-.020,.003,.026,.075,"dark")
        M.bevel(parts.bolt,.027,bore,-.018,.004,.015,.05,.001,"steel")
        local mw=smg and .024 or .030
        local mh=smg and .162 or .182
        M.box(parts.magazine,0,-.035,-.075,mw,mh,smg and .037 or .065,smg and "polymer" or "steel",.13)
        for i=0,3 do M.box(parts.magazine,mw/2+.001,-.035,-.100+i*.016,.002,mh*.85,.004,"dark",.13) end
        M.box(parts.magazine,0,-.13,-.087,mw+.007,.010,smg and .046 or .075,"dark")
    end
    -- Distinct attachments and controls; all dimensions remain in metres.
    if pistol then
        for _,s in ipairs({-1,1}) do
            for i=0,7 do M.box(parts.bolt,s*.0135,bore,.027-i*.004,.001,.018,.0016,"dark") end
            M.bevel(b,s*.014,-.038,.020,.003,.070,.030,.001,"dark")
        end
        M.bevel(parts.bolt,.014,bore+.001,-.008,.003,.010,.026,.001,"steel") -- extractor
        M.box(b,0,.006,-.075,.028,.004,.042,"metal") -- accessory rail
        M.bevel(b,-.016,.008,.008,.004,.008,.020,.001,"metal") -- slide stop
        M.box(parts.selector,0,-.012,-.013,.002,.015,.003,"steel") -- trigger safety
    else
        M.bevel(b,0,bore-.011,.166,.040,.066,.105,.008,"polymer")
        M.bevel(b,0,bore-.032,.235,.043,.104,.016,.004,"dark")
        for i=0,4 do M.box(b,0,bore-.032+i*.014-.028,.244,.040,.002,.002,"polymer") end
        for _,s in ipairs({-1,1}) do
            M.bevel(b,s*.024,bore-.027,-.026,.006,.013,.020,.001,"steel")
            for _,z in ipairs({.038,-.092}) do M.bevel(b,s*.023,bore-.017,z,.004,.008,.008,.001,"steel") end
        end
        M.bevel(b,0,bore+.042,-.105,.034,.008,.018,.001,"dark") -- folded rear sight
        M.bevel(b,0,bore+.038,smg and -.254 or -.38,.022,.014,.026,.002,"metal")
        M.bevel(b,.025,sight,-.020,.013,.018,.018,.002,"metal") -- optic adjustment
        if smg then
            M.bevel(b,0,-.002,-.21,.028,.10,.032,.004,"polymer") -- vertical foregrip
            for i=0,4 do M.box(b,0,-.034+i*.013,-.228,.029,.003,.003,"dark") end
        else
            M.bevel(b,.028,bore-.010,-.037,.010,.008,.070,.001,"metal") -- dust cover
            M.tube(b,0,bore,muzzle+.043,.012,.009,.022,"metal",12)
        end
        M.bevel(parts.selector,-.027,bore-.025,.020,.007,.009,.021,.002,"steel")
    end
    M.bevel(parts.trigger,0,-.019,-.030,.006,.026,.005,.001,"steel")
    M.quad(parts.flash)
    return {parts=parts,muzzle={0,bore,muzzle},sight={0,sight,pistol and .012 or .006},
        reticle={0,sight,pistol and .006 or -.046},
        left=pistol and {-.03,-.012,.076} or smg and {-.056,.015,-.153} or {-.1,.0734,-.2098},
        right=pistol and {.028,.003,.07} or smg and {.024,.028,.064} or {.0251,.06,.1223},
        left_finger=pistol and {.34,-.28,-.9} or smg and {.45,.05,-.89} or {.8977,-.3267,-.2955},
        left_back=pistol and {.15,.93,-.33} or smg and {-.88,-.05,-.45} or {-.2784,-.7648,.581},
        right_finger=pistol and {0,-.315,-.949} or smg and {-.05,-.4,-.915} or {.05,-.55,-.833},
        right_back=pistol and {.98,0,-.2} or smg and {.97,-.05,-.22} or {1,.03,.04},
        grip=pistol and "cup" or smg and "wrap" or "clamp",
        magazine=pistol and {0,-.08,.02} or {0,-.09,-.075},
        charge=pistol and {-.027,.060,.013} or {-.025,bore+.017,.068},
        trigger={0,-.006,-.030},selector=pistol and {0,-.006,-.013} or {-.027,bore-.025,.020}}
end
return M
