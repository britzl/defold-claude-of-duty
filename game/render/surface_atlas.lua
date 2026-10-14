-- Explicit mip rectangles: render targets cannot attach a hardware mip level.
-- Four reference recipes at 1K; the remaining legacy recipes stay at 256.
-- Every level owns a wrapped one-texel border, including the 1x1 tail.
local M={width=3080,height=2052,scratch_size=1024,levels=11}
M.surfaces={
    {name="plaster",size=1024,metres=2.2,relief=.06},
    {name="asphalt",size=1024,metres=3,relief=.075},
    {name="wood",size=1024,metres=2,relief=.038},
    {name="metal",size=256,metres=2,relief=.024},
    {name="cloth",size=256,metres=2,relief=.024},
    {name="concrete",size=1024,metres=2.5,relief=.09},
}
local pending={}
local big=0
for kind,s in ipairs(M.surfaces) do
    s.rects={}; s.last_level=math.floor(math.log(s.size)/math.log(2)+.5)
    for level=0,s.last_level do
        local r={size=s.size/2^level,kind=kind,level=level}
        s.rects[level+1]=r
        if level==0 and s.size==1024 then
            r.x=(big%2)*1026;r.y=math.floor(big/2)*1026;big=big+1
        else pending[#pending+1]=r end
    end
end
table.sort(pending,function(a,b)
    if a.size~=b.size then return a.size>b.size end
    return a.kind<b.kind
end)
local x,y,row_height=2052,0,0
for _,r in ipairs(pending) do
    local width=r.size+2
    if x+width>M.width then x=2052;y=y+row_height;row_height=0 end
    r.x,r.y=x,y;x=x+width;row_height=math.max(row_height,width)
    assert(y+width<=M.height,"Surface atlas overflow")
end
function M.rects(vector)
    local result={}
    for _,s in ipairs(M.surfaces) do for level=0,M.levels-1 do
        local r=s.rects[math.min(level,s.last_level)+1]
        result[#result+1]=vector((r.x+1)/M.width,(r.y+1)/M.height,r.size/M.width,r.size/M.height)
    end end
    return result
end
-- Scratch A/B hold albedo+height high byte and RMA+height residual. Filtering
-- always writes scratch first, then copies to the atlas: no feedback loops.
function M.jobs()
    local jobs={}
    local function add(job) jobs[#jobs+1]=job end
    for kind,s in ipairs(M.surfaces) do
        local base=s.rects[1]
        for channel=0,1 do add({op="recipe",kind=kind-1,channel=channel,size=s.size,target=channel==0 and "scratch_a" or "scratch_b"}) end
        for channel,name in ipairs({"albedo","material","normal"}) do
            add({op=channel==3 and "normal" or "copy",target=name,source=channel==2 and "scratch_b" or "scratch_a",
                rect=base,source_rect={x=0,y=0,size=s.size},source_width=1024,source_height=1024,relief=s.relief/s.metres})
        end
        for level=1,s.last_level do for channel,name in ipairs({"albedo","material","normal"}) do
            local previous=s.rects[level];local r=s.rects[level+1]
            add({op="reduce",target="scratch_a",source=name,rect={x=0,y=0,size=r.size},
                source_rect={x=previous.x+1,y=previous.y+1,size=previous.size},source_width=M.width,source_height=M.height})
            add({op="copy",target=name,source="scratch_a",rect=r,
                source_rect={x=1,y=1,size=r.size},source_width=1024,source_height=1024})
        end end
    end
    return jobs
end
M.job_count=#M.jobs()+6
M.draw_count=M.job_count
for _,job in ipairs(M.jobs()) do
    if job.target~="scratch_a" and job.target~="scratch_b" then M.draw_count=M.draw_count+1 end
end
return M
