local temporal=require 'game.render.temporal'
local count=0
local function test(name,fn) fn();count=count+1;print('PASS '..name) end
test('jitter is bounded, deterministic and repeats after eight samples',function()
    local seen={}
    for i=0,7 do
        local x,y=temporal.jitter(i)
        assert(math.abs(x)<.5 and math.abs(y)<.5)
        local a,b=temporal.jitter(i+8);assert(x==a and y==b)
        seen[x..':'..y]=true
    end
    local n=0;for _ in pairs(seen) do n=n+1 end;assert(n==8)
end)
test('history invalidation resets convergence and records why',function()
    local s=temporal.new();s.age=32
    for _,reason in ipairs({'resize','restart','teleport','settings','capture_frame','context_restored'}) do
        temporal.reset(s,reason);assert(s.age==0 and s.warmup==2 and s.reason==reason);s.age=10
    end
    assert(s.resets==6)
end)
test('camera cuts reject translations and rotations but retain normal motion',function()
    local identity={m03=0,m13=0,m23=0,m02=0,m12=0,m22=1}
    assert(not temporal.cut(nil,identity))
    assert(not temporal.cut(identity,{m03=.1,m13=.05,m23=.05,m02=.1,m12=0,m22=.995}))
    assert(temporal.cut(identity,{m03=3,m13=0,m23=0,m02=0,m12=0,m22=1}))
    assert(temporal.cut(identity,{m03=0,m13=0,m23=0,m02=1,m12=0,m22=0}))
end)
print(count..' temporal tests passed')
