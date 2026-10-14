-- Runtime GPU maps. Every level owns a periodic one-texel border; no hardware
-- mip attachment or texture-array support is required. IDs are stable.
local M={levels=11,detail_kind=15}
local definitions={
    {"plaster",1024,2.2,.06,.014,.75},
    {"asphalt",1024,3,.075,.014,.65},
    {"wood",1024,2,.038,.008,.60},
    {"metal_brushed",512,.8,.004,0,.20},
    {"fabric",512,.7,.008,0,.35},
    {"concrete",1024,2.5,.09,.016,.75},
    {"concrete_floor",1024,2.5,.075,.010,.70},
    {"brick",1024,1.35,.055,.024,.70},
    {"tile",1024,1.5,.03,.030,.45},
    {"dirt",1024,2.5,.12,.012,.65},
    {"gravel",1024,1.6,.055,.018,.65},
    {"metal_painted",1024,1.5,.018,.003,.40},
    {"metal_rust",1024,1.2,.035,.004,.45},
    {"rubber",512,.5,.013,.003,.50},
    {"glass",512,2,.0008,0,.04},
    {"detail",1024,.25,.0034,0,0},
}
M.presets={low={divisor=4,width=1024},medium={divisor=2,width=2048},high={divisor=1,width=4096}}
function M.new(quality)
    local preset=assert(M.presets[quality],"render.material_quality must be low, medium or high")
    local a={quality=quality,width=preset.width,height=0,scratch_size=1024/preset.divisor,
        levels=M.levels,detail_kind=M.detail_kind,surfaces={}}
    local pending={}
    for kind,d in ipairs(definitions) do
        local s={name=d[1],size=d[2]/preset.divisor,metres=d[3],relief=d[4],parallax=d[5],detail=d[6],rects={}}
        s.last_level=math.floor(math.log(s.size)/math.log(2)+.5)
        a.surfaces[kind]=s
        for level=0,s.last_level do
            local r={size=s.size/2^level,kind=kind,level=level}
            s.rects[level+1]=r;pending[#pending+1]=r
        end
    end
    table.sort(pending,function(x,y) if x.size~=y.size then return x.size>y.size end return x.kind<y.kind end)
    local shelves={}
    for _,r in ipairs(pending) do
        local size=r.size+2
        local shelf
        for _,candidate in ipairs(shelves) do
            if size<=candidate.h and candidate.x+size<=a.width then shelf=candidate;break end
        end
        if not shelf then
            shelf={x=0,y=a.height,h=size};shelves[#shelves+1]=shelf;a.height=a.height+size
        end
        r.x,r.y=shelf.x,shelf.y;shelf.x=shelf.x+size
    end
    a.height=math.ceil(a.height/2)*2 -- diagnostic half-atlas captures use whole pixels
    function a.rects(vector)
        local result={}
        for _,s in ipairs(a.surfaces) do for level=0,a.levels-1 do
            local r=s.rects[math.min(level,s.last_level)+1]
            result[#result+1]=vector((r.x+1)/a.width,(r.y+1)/a.height,r.size/a.width,r.size/a.height)
        end end
        return result
    end
    function a.jobs()
        local jobs={}
        local function add(job) jobs[#jobs+1]=job end
        for kind,s in ipairs(a.surfaces) do
            for channel=0,1 do add({op="recipe",kind=kind-1,channel=channel,size=s.size,target=channel==0 and "scratch_a" or "scratch_b"}) end
            for channel,name in ipairs({"albedo","material","normal"}) do
                add({op=channel==3 and "normal" or "copy",target=name,source=channel==2 and "scratch_b" or "scratch_a",
                    rect=s.rects[1],source_rect={x=0,y=0,size=s.size},source_width=a.scratch_size,source_height=a.scratch_size,relief=s.relief/s.metres})
            end
            for level=1,s.last_level do for _,name in ipairs({"albedo","material","normal"}) do
                local prev,r=s.rects[level],s.rects[level+1]
                add({op="reduce",target="scratch_a",source=name,rect={x=0,y=0,size=r.size},
                    source_rect={x=prev.x+1,y=prev.y+1,size=prev.size},source_width=a.width,source_height=a.height})
                add({op="copy",target=name,source="scratch_a",rect=r,source_rect={x=1,y=1,size=r.size},
                    source_width=a.scratch_size,source_height=a.scratch_size})
            end end
        end
        return jobs
    end
    a.job_count=#a.jobs()+1;a.draw_count=a.job_count
    for _,job in ipairs(a.jobs()) do
        if job.target~="scratch_a" and job.target~="scratch_b" then a.draw_count=a.draw_count+1 end
    end
    return a
end
local quality=sys and sys.get_config_string("render.material_quality","medium") or "medium"
for key,value in pairs(M.new(quality)) do M[key]=value end
return M
