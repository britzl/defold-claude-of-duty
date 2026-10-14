local atlas=require "game.render.surface_atlas"
local tests=0
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
test("every mip and wrapped border fits without overlapping another material",function()
    for _,quality in ipairs({"low","medium","high"}) do
    local atlas=atlas.new(quality)
    local all={}
    for _,s in ipairs(atlas.surfaces) do
        assert(s.rects[1].size==s.size and s.rects[#s.rects].size==1)
        for i,r in ipairs(s.rects) do
            assert(r.x>=0 and r.y>=0 and r.x+r.size+2<=atlas.width and r.y+r.size+2<=atlas.height)
            if i>1 then assert(r.size*2==s.rects[i-1].size) end
            for _,other in ipairs(all) do
                assert(r.x+r.size+2<=other.x or other.x+other.size+2<=r.x or
                    r.y+r.size+2<=other.y or other.y+other.size+2<=r.y,"Overlapping mip borders")
            end
            all[#all+1]=r
        end
    end
    assert(#all==#atlas.surfaces*(atlas.surfaces[1].last_level+1)-4)
    end
end)
test("each reduction reads a completed level and copies through independent scratch",function()
    local jobs=atlas.jobs()
    for i,job in ipairs(jobs) do
        assert(job.source~=job.target)
        if job.op=="reduce" then
            assert(job.source_rect.size==job.rect.size*2)
            local copy=jobs[i+1]
            assert(copy.op=="copy" and copy.source==job.target and copy.target==job.source)
            assert(copy.source_rect.x==1 and copy.source_rect.y==1 and copy.rect.size==job.rect.size)
        end
    end
    assert(#jobs+6==atlas.job_count)
end)
test("reference recipes keep physical scale, relief and independent concrete",function()
    local materials=require "game.world.materials"
    assert(materials.concrete.kind~=materials.plaster_sand.kind)
    for _,entry in ipairs({{0,2.2,.06},{1,3,.075},{2,2,.038},{5,2.5,.09}}) do
        local s=atlas.surfaces[entry[1]+1]
        assert(s.size==512 and s.metres==entry[2] and s.relief==entry[3])
    end
end)
print(tests.." surface atlas tests passed")
