-- Runtime mesh recipes. Dimensions/attachments follow the reference weapons;
-- detail is deliberately bounded and merged into independently animated parts.
local V = require "game.weapons.math"
local M = {}
-- Vertex alpha is metalness; the weapon shader writes opaque coverage.
M.colors={metal={.15,.18,.19,.8},steel={.29,.32,.34,1},dark={.025,.032,.035,0},
    polymer={.085,.105,.10,0},tan={.33,.28,.18,0},skin={.50,.32,.22,0},glove={.22,.24,.18,0},
    light={.85,.91,.78,0},red={1,.08,.02,0},flash={1,.72,.22,0}}
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
local function hand(batch,left)
    M.box(batch,0,0,0,.055,.07,.038,"glove",-.22)
    M.box(batch,0,-.048,.018,.048,.052,.042,"skin",-.22)
    M.box(batch,0,-.090,.040,.064,.068,.060,"tan",-.30)
    for i=0,3 do M.box(batch,(i-1.5)*.014,.038,-.012,.012,.035,.018,"glove",.6) end
    M.box(batch,left and .032 or -.032,.004,-.026,.021,.039,.023,"glove",-.65)
end
function M.weapon(id)
    local pistol=id=="pistol"
    local smg=id=="smg"
    local bore=pistol and .036 or smg and .068 or .075
    local muzzle=pistol and -.153 or smg and -.330 or -.502
    local sight=pistol and .070 or smg and .123 or .142
    local parts={}
    for _,name in ipairs({"body","magazine","bolt","charge","left_hand","right_hand","reticle","flash"}) do parts[name]=M.batch() end
    local b=parts.body
    if pistol then
        M.box(b,0,.003,-.04,.029,.045,.15,"polymer")
        M.box(b,0,-.047,.012,.028,.115,.04,"polymer",-.24)
        M.box(b,0,-.031,-.038,.029,.008,.047,"dark")
        M.box(b,0,-.016,-.061,.029,.034,.008,"polymer")
        M.tube(b,0,bore,muzzle+.026,.007,.0045,.052,"steel")
        M.box(parts.bolt,0,bore,-.055,.031,.031,.183,"steel")
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
        M.tube(b,0,bore,-.045,.023,0,.185,"metal")
        M.box(b,0,bore-.025,-.036,.043,.045,.133,"metal")
        M.box(b,0,-.031,.021,.031,.10,.045,"polymer",-.30)
        M.box(b,0,-.007,-.032,.032,.007,.052,"dark")
        M.box(b,0,.006,-.061,.032,.028,.008,"metal")
        M.tube(b,0,bore,fore,.028,.020,fore_len,"polymer",12)
        M.tube(b,0,bore,(fore-fore_len/2+muzzle)/2,.009,.0045,fore-fore_len/2-muzzle,"steel")
        M.tube(b,0,bore,muzzle+.013,.013,.006,.026,"dark")
        for i=0,5 do
            M.box(b,.028,bore,fore+fore_len*.42-i*fore_len/6,.003,.013,.015,"dark")
            M.box(b,-.028,bore,fore+fore_len*.42-i*fore_len/6,.003,.013,.015,"dark")
        end
        M.box(b,0,bore+.027,-.095,.036,.008,.235,"steel")
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
        M.box(parts.bolt,.021,bore,-.018,.006,.019,.06,"steel")
        M.box(b,.024,bore,-.020,.003,.026,.075,"dark")
        local mw=smg and .024 or .030
        local mh=smg and .162 or .182
        M.box(parts.magazine,0,-.035,-.075,mw,mh,smg and .037 or .065,smg and "polymer" or "steel",.13)
        for i=0,3 do M.box(parts.magazine,mw/2+.001,-.035,-.100+i*.016,.002,mh*.85,.004,"dark",.13) end
        M.box(parts.magazine,0,-.13,-.087,mw+.007,.010,smg and .046 or .075,"dark")
    end
    hand(parts.left_hand,true);hand(parts.right_hand,false)
    M.tube(parts.flash,0,0,0,.024,0,.06,"flash",6)
    M.box(parts.flash,0,0,0,.095,.006,.006,"flash")
    M.box(parts.flash,0,0,0,.006,.095,.006,"flash")
    return {parts=parts,muzzle={0,bore,muzzle},sight={0,sight,pistol and .012 or .006},
        left=pistol and {-.025,-.024,-.025} or {-.016,.006,smg and -.20 or -.28},right={.014,-.040,.024},
        magazine=pistol and {0,-.08,.02} or {0,-.09,-.075}}
end
return M
