-- Opt-in native integration fixture. macOS Automation Bridge cannot inject
-- touch hardware, so deliver Defold-shaped actions to the real on_input path.
local M={}
function M.install(self,on_input)
    assert(automation_bridge,"Touch validation requires Automation Bridge")
    automation_bridge.command("touch_validation.input",function(data)
        local width,height=window.get_size()
        local points={}
        for _,p in ipairs(data.points or {}) do
            points[#points+1]={id=p.id,x=p.x/width*960,y=(height-p.y)/height*640,
                screen_x=p.x,screen_y=height-p.y,pressed=p.pressed,released=p.released}
        end
        if data.mouse then
            on_input(self,hash("fire"),{source=hash("touch"),pressed=true})
        else on_input(self,hash("touch_multi"),{source=hash("touch"),touch=points}) end
        return {accepted=true}
    end)
end
return M
