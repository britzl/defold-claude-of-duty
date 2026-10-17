package.path = "./?.lua;"..package.path
local mantle = require "game.player.mantle"
local capsule = require "game.player.capsule"
local T = require "game.player.tuning"
local h,count = 1/120,0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function near(a,b) assert(math.abs(a-b)<1e-7,a.." != "..b) end
-- An independent box/plane fixture; native/browser suites use actual Bullet shapes.
local function fixture(depth,height)
    local q={depth=depth,top=height,floor=true,floor_y=0,ceiling=math.huge,normal=1}
    function q:fits(p,height)
        if self.blocked and p.z< -0.5 then return false end
        return p.y>=0 and p.y+height<=self.ceiling
            and not (p.z-T.radius<0 and p.z+T.radius> -self.depth and p.y<self.top)
    end
    function q:ray(p,dx,dy,dz)
        if dz<0 and p.z>=0 and p.z+dz<=0 and p.y<self.top then
            return {x=p.x,y=p.y,z=0,nx=0,ny=0,nz=1,surface="wood"}
        end
        if dy<0 then
            local surface=p.z<=0 and p.z>=-self.depth and self.top or self.floor and self.floor_y
            if surface and p.y>surface and p.y+dy<=surface then
                return {x=p.x,y=surface,z=p.z,nx=0,ny=surface==0 and self.normal or 1,nz=0,surface="concrete"}
            end
        end
    end
    function q:sweep(p,height,dx,dy,dz)
        if p.y+height+dy>self.ceiling then return {fraction=0.5} end
        local lo,hi=0,1
        for _,v in ipairs({{p.z,dz,-self.depth-T.radius,T.radius},{p.y,dy,-height,self.top}}) do
            if math.abs(v[2])<1e-10 then
                if v[1]<=v[3] or v[1]>=v[4] then return end
            else
                local a,b=(v[3]-v[1])/v[2],(v[4]-v[1])/v[2]
                if a>b then a,b=b,a end
                lo,hi=math.max(lo,a),math.min(hi,b)
                if lo>=hi then return end
            end
        end
        if lo<hi then return {fraction=lo} end
    end
    local m=capsule.new({x=0,y=T.skin,z=0.6})
    m.grounded=true;m.velocity.z=-4.57
    return m,q
end
local function intent(extra)
    local i={enabled=true,move_x=0,move_z=-1}
    for k,v in pairs(extra or {}) do i[k]=v end
    return i
end

test("automatic low thin vault lands beyond the obstacle and retains momentum",function()
    local m,q=fixture(0.2,0.65)
    assert(mantle.try_begin(m,intent(),q) and m.vault_started and m.mantle.kind=="vault")
    near(m.mantle.duration,0.34)
    for _=1,42 do if m.mantle then mantle.update(m,intent(),h,q) end end
    assert(m.vault_completed and m.grounded and not m.mantle)
    near(m.position.y,T.skin);near(m.position.z,-0.8);near(m.velocity.z,-4.57*0.88)
end)

test("deep ledges require jump and finish on top; high thin obstacles require jump and finish beyond",function()
    local m,q=fixture(2,0.65)
    assert(not mantle.try_begin(m,intent(),q))
    assert(mantle.try_begin(m,intent({jump=true}),q) and m.mantle.kind=="mantle")
    near(m.mantle.target.y,0.65+T.skin)
    m,q=fixture(0.15,1.2)
    assert(not mantle.try_begin(m,intent(),q))
    assert(mantle.try_begin(m,intent({jump=true}),q) and m.mantle.kind=="vault")
    near(m.mantle.duration,0.34*1.45);near(m.mantle.target.y,T.skin)
end)

test("stairs, distance, slow approaches, backwards intent and prone cannot trigger automatic vaults",function()
    for _,mode in ipairs({"step","far","slow","back","prone","air","ai"}) do
        local m,q=fixture(0.2,mode=="step" and 0.3 or 0.65)
        local i=intent()
        if mode=="far" then m.position.z=0.9 end
        if mode=="slow" then m.velocity.z=-2 end
        if mode=="back" then i.move_z=1 end
        if mode=="prone" then m.stance="prone" end
        if mode=="air" then m.grounded=false end
        if mode=="ai" then i.auto_vault=false end
        assert(not mantle.try_begin(m,i,q),mode)
    end
end)

test("blocked landings, absent or steep floors, excessive drops and low roofs reject vaults",function()
    for _,mode in ipairs({"blocked","missing","steep","roof","drop"}) do
        local m,q=fixture(0.2,0.65)
        if mode=="blocked" then q.blocked=true end
        if mode=="missing" then q.floor=false end
        if mode=="steep" then q.normal=0.5 end
        if mode=="roof" then q.ceiling=1.5 end
        if mode=="drop" then q.floor_y=-1.8 end
        assert(not mantle.try_begin(m,intent({jump=true}),q),mode)
    end
    local m,q=fixture(0.2,3)
    assert(not mantle.try_begin(m,intent({jump=true}),q))
end)

test("dynamic obstruction and disabled input abort without a destination teleport",function()
    for _,mode in ipairs({"blocked","disabled"}) do
        local m,q=fixture(0.2,0.65)
        assert(mantle.try_begin(m,intent(),q))
        for _=1,6 do mantle.update(m,intent(),h,q) end
        local y,z=m.position.y,m.position.z
        if mode=="blocked" then function q:sweep() return {fraction=0.5} end end
        mantle.update(m,intent({enabled=mode~="disabled"}),h,q)
        assert(m.vault_aborted and m.mantle_aborted and not m.grounded and not m.mantle)
        near(m.position.y,y);near(m.position.z,z)
    end
end)

test("disappearing landing support leaves a falling actor and cannot report completion",function()
    local m,q=fixture(0.2,0.65)
    assert(mantle.try_begin(m,intent(),q));q.floor=false
    for _=1,42 do if m.mantle then mantle.update(m,intent(),h,q) end end
    assert(m.vault_aborted and not m.vault_completed and not m.grounded)
end)

print(count.." vault tests passed")
