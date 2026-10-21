local W=require "game.ui.widgets"
local limits=require "game.ui.feedback"
local M={}
local amber=vmath.vector4(1,.76,.28,1)
local function colour(kind) return kind=="kill" and W.red or kind=="head" and amber or W.white end
local function box(id,x,y,w,h,c,layer,anchor) return W.box(id,x,y,w,h,c,layer or "markers",anchor) end
local function text(id,x,y,t,scale,c,anchor) return W.text(id,x,y,t,scale,c,nil,"markers",anchor) end
local function place(n,x,y) gui.set_position(n,vmath.vector3(480+x,320+y,0)) end
local function size(n,w,h) gui.set_size(n,vmath.vector3(math.max(.01,w),h,0)) end
local function enable(item,on) for _,n in ipairs(item.nodes) do gui.set_enabled(n,on) end end
function M.new(TL,BR,BOTTOM,TOP)
    local s={pools={},TL=TL,BR=BR,BOTTOM=BOTTOM,TOP=TOP}
    for _,kind in ipairs({"contacts","grenades","numbers","arcs","objectives"}) do
        s.pools[kind]={}
        for i=1,limits[kind] do
            local id="feedback_"..kind.."_"..i
            local v={nodes={}}
            local function add(n) v.nodes[#v.nodes+1]=n;return n end
            if kind=="contacts" then
                v.label=add(text(id,98,510,"o",.85,W.red,TL))
            elseif kind=="arcs" then
                for j=1,7 do add(box(id.."_"..j,480,320,10,3,W.red,"damage")) end
            elseif kind=="numbers" then v.label=add(text(id,480,320,"",1.1,W.white))
            elseif kind=="objectives" then
                v.glyph=add(text(id,480,320,"",1,W.accent))
                v.label=add(text(id.."_label",480,296,"",.65,W.accent))
                v.map=add(text(id.."_map",98,510,"",.7,W.accent,TL))
            else
                v.back=add(box(id.."_back",480,320,110,48,W.panel))
                v.glyph=add(text(id,480,320,"!",1.1,W.red))
                v.title=add(text(id.."_title",480,320,"GRENADE",.65,W.red))
                v.label=add(text(id.."_label",480,300,"",.7,W.red))
                v.track=add(box(id.."_track",480,288,62,3,W.muted))
                v.bar=add(box(id.."_fuse",449,288,62,3,W.red))
                gui.set_pivot(v.bar,gui.PIVOT_W)
            end
            enable(v,false);s.pools[kind][i]=v
        end
    end
    s.banner=text("elimination_banner",480,521,"",1.15,W.white,TOP)
    s.banner_sub=text("elimination_detail",480,500,"",.72,amber,TOP)
    s.prompt=text("interaction_prompt",480,215,"",.9,W.white,BOTTOM)
    s.prompt_sub=text("interaction_detail",480,193,"",.7,W.muted,BOTTOM)
    s.prompt_bar=box("interaction_progress",400,179,160,3,amber,"markers",BOTTOM)
    gui.set_pivot(s.prompt_bar,gui.PIVOT_W)
    s.reload=box("reload_progress",748,96,188,4,amber,"hud",BR)
    gui.set_pivot(s.reload,gui.PIVOT_W)
    s.reload_label=text("reload_detail",842,113,"",.72,amber,BR)
    s.pips={}
    for i=1,32 do s.pips[i]=box("ammo_pip_"..i,748+(i-1)*5.9,86,4,3,W.white,"hud",BR) end
    s.chamber=text("chamber_indicator",736,86,"+",.6,W.accent,BR)
    for _,n in ipairs({s.banner,s.banner_sub,s.prompt,s.prompt_sub,s.prompt_bar,s.reload,s.reload_label,s.chamber}) do gui.set_enabled(n,false) end
    return s
end
function M.state(s,d,hud)
    s.visible=d.visible
    for kind,pool in pairs(s.pools) do
        for i,item in ipairs(pool) do enable(item,d.visible and i<=(d[kind] or 0)) end
    end
    gui.set_enabled(s.banner,d.visible and d.banner~="")
    gui.set_enabled(s.banner_sub,d.visible and d.banner~="")
    gui.set_text(s.banner,d.banner);gui.set_text(s.banner_sub,d.banner_sub)
    gui.set_alpha(s.banner,d.banner_alpha);gui.set_alpha(s.banner_sub,d.banner_alpha)
    local p=d.prompt or {}
    local has=d.visible and p.text~=nil
    gui.set_enabled(s.prompt,has);gui.set_enabled(s.prompt_sub,has)
    gui.set_enabled(s.prompt_bar,has and p.progress>=0)
    gui.set_text(s.prompt,has and "["..p.key.."]  "..p.text or "")
    gui.set_text(s.prompt_sub,has and p.sub or "")
    if has then size(s.prompt_bar,160*math.max(0,p.progress),3) end
    gui.set_enabled(s.reload,d.visible and d.reload)
    gui.set_enabled(s.reload_label,d.visible and (d.reload or d.ammo_low or d.ammo_empty))
    gui.set_text(s.reload_label,d.reload and string.format("RELOADING  %d%%",math.floor(d.progress*100))
        or d.ammo_empty and (d.reserve>0 and "EMPTY / RELOAD" or "OUT OF AMMO") or "LOW AMMO")
    size(s.reload,188*d.progress,4)
    local c=d.ammo_empty and W.red or d.ammo_low and amber or W.white
    gui.set_color(hud.ammo,c)
    for i,n in ipairs(s.pips) do
        gui.set_enabled(n,d.visible and i<=d.capacity)
        gui.set_color(n,i<=d.mag and c or W.muted);gui.set_alpha(n,i<=d.mag and 1 or .25)
    end
    gui.set_enabled(s.chamber,d.visible and d.chambered)
    gui.set_enabled(hud.hit,d.visible and d.hit_alpha>0)
    gui.set_color(hud.hit,colour(d.hit_kind));gui.set_alpha(hud.hit,d.hit_alpha)
end
function M.item(s,d)
    local v=s.pools[d.kind][d.index]
    if not v then return end
    if d.kind=="contacts" then
        W.position(v.label,98+d.x,510+d.y,s.TL)
        gui.set_text(v.label,d.floor==1 and "^" or d.floor==-1 and "v" or "o")
    elseif d.kind=="arcs" then
        local bell={.1,.28,.62,1,.62,.28,.1}
        for j,n in ipairs(v.nodes) do
            local a=d.angle+math.rad((j-4)*8.2)
            place(n,math.sin(a)*80,math.cos(a)*80)
            gui.set_euler(n,vmath.vector3(0,0,-math.deg(a)))
            gui.set_alpha(n,d.alpha*bell[j])
        end
    elseif d.kind=="numbers" then
        place(v.label,d.x,d.y)
        gui.set_text(v.label,tostring(d.amount));gui.set_color(v.label,colour(d.kind_colour))
        gui.set_alpha(v.label,d.alpha)
    elseif d.kind=="objectives" then
        place(v.glyph,d.x,d.y);place(v.label,d.x,d.y-22)
        gui.set_text(v.glyph,d.offscreen and "^" or "["..d.label.."]")
        gui.set_euler(v.glyph,vmath.vector3(0,0,d.offscreen and d.angle or 0))
        gui.set_text(v.label,string.format("%s %dm",d.name,math.floor(d.distance+.5)))
        W.position(v.map,98+d.map_x,510+d.map_y,s.TL)
        gui.set_text(v.map,d.label..(d.floor==1 and "^" or d.floor==-1 and "v" or ""))
    else
        place(v.back,d.x,d.y-10);place(v.glyph,d.x-43,d.y+3);place(v.title,d.x+4,d.y+3);place(v.label,d.x,d.y-16)
        place(v.track,d.x,d.y-29);place(v.bar,d.x-31,d.y-29)
        gui.set_text(v.glyph,d.offscreen and "^" or "!")
        gui.set_euler(v.glyph,vmath.vector3(0,0,d.offscreen and d.angle or 0))
        gui.set_text(v.label,string.format("%.1fs %dm%s",d.fuse,math.floor(d.distance+.5),d.floor))
        size(v.bar,62*d.fill,3);gui.set_alpha(v.glyph,d.alpha)
    end
end
function M.inspect(s)
    local result={}
    for kind,pool in pairs(s.pools) do
        local count=0
        for _,v in ipairs(pool) do if gui.is_enabled(v.nodes[1]) then count=count+1 end end
        result[kind]=count
    end
    result.banner=gui.is_enabled(s.banner) and gui.get_text(s.banner) or ""
    result.prompt=gui.is_enabled(s.prompt) and gui.get_text(s.prompt) or ""
    result.reload=gui.is_enabled(s.reload)
    result.reload_width=gui.get_size(s.reload).x
    result.pips=0
    for _,n in ipairs(s.pips) do if gui.is_enabled(n) then result.pips=result.pips+1 end end
    return result
end
return M
