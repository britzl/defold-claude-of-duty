-- Query budgets and invalidation; native movement fixtures cover Bullet geometry.
package.path = './?.lua;'..package.path
local capsule = require 'game.player.capsule'
local T = require 'game.player.tuning'
local revision = require 'game.world.collision_revision'
local dt, count = 1/120, 0
local function test(name, fn) fn();count=count+1;print('PASS '..name) end
local function input(extra)
    local out={move_x=0,move_z=0}
    for k,v in pairs(extra or {}) do out[k]=v end
    return out
end
local function planes(versioned)
    local q={floor=0,ceiling=math.huge,revision=1,counts={contacts=0,fits=0,sweep=0,sync=0}}
    if versioned then function q:clearance_revision() return self.revision end end
    function q:sync() self.counts.sync=self.counts.sync+1 end
    function q:ray() end
    function q:camera_fraction() return 1 end
    function q:contacts(p,height)
        self.counts.contacts=self.counts.contacts+1
        local out={}
        if p.y<self.floor then out[#out+1]={distance=p.y-self.floor,nx=0,ny=1,nz=0} end
        if p.y+height>self.ceiling then out[#out+1]={distance=self.ceiling-p.y-height,nx=0,ny=-1,nz=0} end
        return out
    end
    function q:fits(p,height)
        self.counts.fits=self.counts.fits+1
        return not self.reject_fits and p.y>=self.floor-.0001 and p.y+height<=self.ceiling+.0001
    end
    function q:sweep(p,height,dx,dy,dz)
        self.counts.sweep=self.counts.sweep+1
        if dy<0 and p.y>=self.floor and p.y+dy<=self.floor then
            local n=self.normal or {x=0,y=1,z=0}
            return {fraction=(self.floor-p.y)/dy,nx=n.x,ny=n.y,nz=n.z,surface=self.surface}
        elseif dy>0 and p.y+height+dy>=self.ceiling then
            return {fraction=(self.ceiling-p.y-height)/dy,nx=0,ny=-1,nz=0}
        end
    end
    return q
end
local function tick(m,q,extra)
    q.counts={contacts=0,fits=0,sweep=0,sync=0}
    capsule.update(m,input(extra),dt,q)
    return q.counts
end
local function new(versioned)
    local m,q=capsule.new({x=0,y=T.skin,z=0}),planes(versioned)
    for _=1,3 do tick(m,q) end -- Settle ground rounding and prime clearance.
    return m,q
end

test('stationary grounded ticks reuse support only for unchanged static geometry',function()
    local m,q=new(false)
    local c=tick(m,q)
    assert(c.contacts==1 and c.fits==0 and c.sweep==1)
    assert(m.grounded and m.travel==0 and not m.landed and c.sync==1)
    m,q=new(true)
    c=tick(m,q)
    assert(c.contacts==0 and c.fits==0 and c.sweep==0)
end)

test('walking reuses only the previous final clearance, while displacement still gets checked',function()
    local m,q=new(true)
    for _=1,60 do
        local c=tick(m,q,{move_z=-1})
        assert(c.contacts==0 and c.fits==1 and c.sweep>=2)
        assert(m.grounded and not m.recovery_failed and m.safe.z==m.position.z)
    end
end)

test('teleports, height changes, query changes, resets and revisions require fresh contacts',function()
    for _,change in ipairs({
        function(m,q) m.position.x=m.position.x+1;return q end,
        function(m,q) m.position.y=m.position.y+.1;return q end,
        function(m,q) m.position.z=m.position.z+1;return q end,
        function(m,q) m.height=T.stances.crouch.height;m.stance='crouch';return q end,
        function() return planes(true) end,
        function(m,q) capsule.reset(m,{x=m.position.x,y=m.position.y,z=m.position.z});return q end,
        function(m,q) q.revision=q.revision+1;return q end,
        function(m,q) q.revision=nil;return q end,
    }) do
        local m,q=new(true)
        q=change(m,q)
        assert(tick(m,q).contacts>0)
    end
end)

test('unversioned moving geometry is recovered and disappearing support is never cached',function()
    local m,q=new(false)
    q.floor=.2
    assert(tick(m,q).contacts>=2 and m.position.y>=.2 and not m.recovery_failed)
    m,q=new(true)
    q.floor=-math.huge;q.revision=q.revision+1
    local y=m.position.y
    local c=tick(m,q)
    assert(c.contacts==1 and c.fits==1 and c.sweep==3 and not m.grounded and m.position.y<y)
end)

test('ground misses still get the longer snap and changing height rechecks ground and clearance',function()
    local m,q=new(true)
    q.floor=-.2;q.revision=q.revision+1
    local c=tick(m,q)
    assert(c.sweep==3 and m.grounded and math.abs(m.position.y-(-.2+T.skin))<1e-8)
    m,q=new(true)
    c=tick(m,q,{crouch=true})
    assert(c.contacts==1 and m.height==T.stances.crouch.height)
    c=tick(m,q)
    assert(c.sweep==1 and c.fits>=1 and m.height==T.stances.stand.height)
end)

test('cached support restores its normal and surface, and upward motion cannot reuse it',function()
    local m,q=new(true)
    q.normal={x=.2,y=.98,z=0};q.surface='wood';q.revision=q.revision+1
    assert(tick(m,q).sweep>0)
    local c=tick(m,q)
    assert(c.sweep==0 and m.ground.x==.2 and m.ground.y==.98 and m.surface=='wood')
    m.velocity.y=2
    c=tick(m,q)
    assert(not m.grounded and m.position.y>T.skin and c.sweep>0)
end)

test('failed clearance and failed recovery cannot authorize the next tick',function()
    local m,q=new(true)
    q.reject_fits=true
    tick(m,q,{move_z=-1})
    assert(tick(m,q,{move_z=-1}).contacts>0)
    q.ceiling=.5;q.revision=q.revision+1
    tick(m,q)
    assert(m.recovery_failed)
    q.ceiling=math.huge;q.reject_fits=false
    assert(tick(m,q).contacts>0 and not m.recovery_failed)
end)

test('cached and uncached worlds agree through walking, jump, stance, slide and falling',function()
    local a,qa=new(true)
    local b,qb=new(false)
    for i=1,900 do
        local controls={move_z=i<300 and -1 or 0,sprint=i<240,
            crouch=i>=60 and i<180,prone=i>=500 and i<540,jump=i==190 or i==550}
        if i==700 then qa.floor=-.2;qb.floor=-.2;qa.revision=qa.revision+1 end
        tick(a,qa,controls);tick(b,qb,controls)
        for _,axis in ipairs({'x','y','z'}) do
            -- Repeating a no-op vertical snap changes the last few bits of
            -- floor height (observed 3.5e-18 m); reuse preserves the first snap.
            assert((axis=='y' and math.abs(a.position[axis]-b.position[axis])<1e-12
                or a.position[axis]==b.position[axis]) and a.velocity[axis]==b.velocity[axis])
        end
        for _,key in ipairs({'height','grounded','jumped','landed','stance','sliding','travel','recovery_failed'}) do
            assert(a[key]==b[key],key)
        end
    end
end)

test('world edits disable reuse until deferred changes have crossed two update boundaries',function()
    local before=revision.current()
    revision.changed()
    assert(revision.current()==nil)
    revision.advance_frame()
    assert(revision.current()==nil)
    -- Another adapter editing the shared world restarts the settling window.
    revision.changed();revision.advance_frame()
    assert(revision.current()==nil)
    revision.advance_frame()
    assert(revision.current()~=nil and revision.current()~=before)
    local stable=revision.current()
    revision.advance_frame();assert(revision.current()==stable)
end)
test('clearance observed before a deferred collider appears cannot survive its installation',function()
    local m,q=new(false)
    q.clearance_revision=revision.current
    tick(m,q);assert(tick(m,q).contacts==0)
    revision.changed()
    assert(tick(m,q).contacts==1) -- The collider is still pending.
    revision.advance_frame()
    q.floor=.2 -- Simulate installation at the frame boundary.
    assert(tick(m,q).contacts>=2 and m.position.y>=.2 and not m.recovery_failed)
    revision.advance_frame()
    assert(tick(m,q).contacts==1)
    assert(tick(m,q).contacts==0)
end)
print(count..' capsule reuse checks passed')
