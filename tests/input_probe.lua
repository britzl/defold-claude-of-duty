-- Opt-in observation/setup only. Browser tests send real DOM input to the engine.
local ui=require 'game.ui.controller'
local weapons=require 'game.systems.weapons'
local input=require 'game.input'
local M={}
function M.state(self)
    local p=self.ctx.player.motion
    local held={}
    for name,b in pairs(self.ctx.input.buttons) do if b.held then held[name]=true end end
    local width,height=window.get_size()
    local layout=self.touch_layout
    local targets={}
    if layout then
        local function add(name,x,y,w,h)
            targets[name]={x=x*layout.scale,y=height-y*layout.scale,w=(w or 0)*layout.scale,h=(h or 0)*layout.scale}
        end
        for _,b in ipairs(layout.buttons) do add(b.id,b.x,b.y,b.w,b.h) end
        local s=layout.stick;add('move',s.x,s.y,s.r*2,s.r*2)
        add('look',layout.right-170,layout.top-(layout.portrait and 240 or 145),layout.look.w,layout.look.h)
    end
    return {ready=self.ctx.world.ready and self.renderer_stats.ready or false,
        ui=ui.snapshot(self),weapons=weapons.snapshot(self.ctx),targets=targets,
        x=p.position.x,y=p.position.y,z=p.position.z,yaw=p.yaw,pitch=p.pitch,stance=p.stance,
        fov=self.ctx.presentation.fov,touch_fingers=self.touch.fingers,look_id=self.touch.look_id,held=held,move_x=self.ctx.input.move_x,move_z=self.ctx.input.move_z,
        alive=self.ctx.player.actor.alive,mouse_locked=window.get_mouse_lock(),width=width,height=height}
end
function M.command(self,data,restart,on_input)
    if data.kind=='prepare' then
        self.ctx.ai.enabled=false
        ui.focus(self,true);ui.pause(self,false)
    elseif data.kind=='focus' then ui.focus(self,data.value)
    elseif data.kind=='damage' then require('game.combat').request(self.ctx.combat,{target='player',amount=1000})
    elseif data.kind=='restart' then restart(self);self.ctx.ai.enabled=false
    elseif data.kind=='configure' then ui.configure(self,data.setting)
    elseif data.kind=='inject' then on_input(self,hash(data.name),data.action or {})
    end
end
function M.install(self,restart,on_input)
    self.input_probe={restart=restart,on_input=on_input}
    if automation_bridge then
        automation_bridge.command('input_validation.state',function() return M.state(self) end)
        automation_bridge.command('input_validation.command',function(data) M.command(self,data,restart,on_input);return M.state(self) end)
    end
end
function M.update(self)
    if not html5 then return end
    local request=html5.run("JSON.stringify(window.__INPUT_REQUEST__ || null)")
    if request and request~='null' then
        html5.run('window.__INPUT_REQUEST__=null')
        M.command(self,json.decode(request),self.input_probe.restart,self.input_probe.on_input)
    end
    html5.run('window.__INPUT_STATE__='..json.encode(M.state(self)))
end
return M
