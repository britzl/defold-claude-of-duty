-- Opt-in release benchmark. Times wall-clock update intervals, not GPU work or
-- verified presentation timestamps. The report keeps those unavailable gates open.
local Q=require 'game.render.quality'
local ui=require 'game.ui.controller'
local input=require 'game.input'
local player=require 'game.systems.player'
local combat=require 'game.combat'
local grenades=require 'game.systems.grenades'
local M={}
local destinations={'street_north','W2/room','W2/bedroom','W2/room','street_south','street_gate',
    'east_loop/ruin_yard','E1/room','E1/floor2/bedroom','E1/room','E3/room','street_north'}
local function route(graph,from,to)
    local nodes,adj,dist,prev,done={},{},{},{},{}
    for _,n in ipairs(graph.nodes) do nodes[n.id]=n;adj[n.id]={} end
    for _,e in ipairs(graph.edges) do
        adj[e.from][#adj[e.from]+1]=e.to;adj[e.to][#adj[e.to]+1]=e.from
    end
    dist[from]=0
    while true do
        local current,best
        for id,d in pairs(dist) do if not done[id] and (not best or d<best) then current,best=id,d end end
        assert(current,'Disconnected benchmark route '..from..' -> '..to)
        if current==to then break end
        done[current]=true
        for _,id in ipairs(adj[current]) do
            local a,b=nodes[current],nodes[id]
            local d=best+math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
            if not dist[id] or d<dist[id] then dist[id]=d;prev[id]=current end
        end
    end
    local path={};local id=to
    while id~=from do table.insert(path,1,nodes[id]);id=prev[id] end
    return path,nodes[from]
end
local function percentiles(samples)
    local values={};local sum=0
    for i,v in ipairs(samples) do values[i]=v;sum=sum+v end
    table.sort(values)
    local function p(f) return values[math.max(1,math.ceil(#values*f))] or 0 end
    return {samples=#values,mean_ms=sum/math.max(1,#values),p50_ms=p(.5),p95_ms=p(.95),p99_ms=p(.99),worst_ms=p(1)}
end
function M.new()
    if html5 then sys.set_error_handler(function(_,message,stack)
        html5.run('console.error('..json.encode('ERROR: '..tostring(message)..'\n'..tostring(stack))..')') end) end
    local options=html5 and json.decode(html5.run('JSON.stringify(window.__SUSTAINED_OPTIONS__ || {})')) or {}
    return {options=options,created=socket.gettime(),warmup=options.warmup or sys.get_config_number('sustained.warmup',60),
        duration=options.seconds or sys.get_config_number('sustained.seconds',300),samples={},reached={},distance=0,
        grenades=0,kills=0,restarts=0,shots=0,reloads=0,stalls=0,history={}}
end
function M.update(t,self,dt,restart)
    if t.done then return end
    local ctx=self.ctx;local now=socket.gettime()
    -- An unattended page may lose focus while loading. Let the first fixed tick
    -- create the player capsule before waiting for it; never pause the workload.
    self.focused=true;require('game.runtime').set_paused(ctx,false)
    if not ctx.world.ready or not self.renderer_stats.ready or not ctx.services.capsule then
        if html5 and now>(t.loading_report or 0) then
            t.loading_report=now+2
            html5.run('window.__SUSTAINED_LOADING__='..json.encode({phase=ctx.world.phase,frame=ctx.time.frame,renderer=self.renderer_stats.ready,audio=ctx.audio.loaded}))
        end
        return
    end
    if not t.started then
        t.started=now;t.last=now;t.last_event=now;t.report_at=now+30;t.previous={x=ctx.player.position.x,z=ctx.player.position.z}
        t.loaded_seconds=now-t.created
        ui.focus(self,true);ui.pause(self,false)
        ui.quality_mode(self,t.options.preset or sys.get_config_string('sustained.preset','high'))
        t.goal=1;t.path,t.start=route(ctx.world.navigation,destinations[1],destinations[2]);t.goal=2;t.node=1
        player.reset(ctx,t.start,0);t.previous={x=t.start.x,z=t.start.z};t.reached[destinations[1]]=1
        t.node_started=now;t.last_restart=now;t.last_shots=ctx.weapons.sim.fired
        t.last_clip=ctx.weapons.clip
    end
    -- Keep the encounter going while retaining damage events, suppression and AI.
    self.focused=true;require('game.runtime').set_paused(ctx,false)
    ctx.ai.damage_scale=0;ctx.player.actor.health=100
    local elapsed=now-t.started
    local delta=(now-t.last)*1000;t.last=now
    if elapsed>=t.warmup and elapsed<t.warmup+t.duration then t.samples[#t.samples+1]=delta end
    local p,m=ctx.player.position,ctx.player.motion
    t.distance=t.distance+math.sqrt((p.x-t.previous.x)^2+(p.z-t.previous.z)^2)
    t.previous={x=p.x,z=p.z}
    local point=t.path[t.node]
    if point then
        local dx,dz=point.x-p.x,point.z-p.z;local distance=math.sqrt(dx*dx+dz*dz)
        if distance<.18 and math.abs(point.y-p.y)<.35 then
            t.node=t.node+1;t.node_started=now
        else
            local speed=math.min(2.8,distance*3)
            local c,s=math.cos(m.yaw),math.sin(m.yaw)
            local x,z=(dx*c-dz*s)/math.max(.001,distance),(dx*s+dz*c)/math.max(.001,distance)
            input.move(ctx.input,'benchmark',x*speed/(4.57*.92),z*speed/(4.57*(z>0 and .8 or 1)))
            local yaw=math.atan2(-dx,-dz);local turn=(yaw-m.yaw+math.pi)%(2*math.pi)-math.pi
            input.look(ctx.input,-math.max(-.035,math.min(.035,turn))/.0022,0)
            if now-t.node_started>20 then
                t.stalls=t.stalls+1;t.failure='Traversal blocked at '..point.id
                t.duration=math.min(t.duration,math.max(0,elapsed-t.warmup))
            end
        end
    else
        t.reached[destinations[t.goal]]=(t.reached[destinations[t.goal]] or 0)+1
        local from=destinations[t.goal];t.goal=t.goal%#destinations+1
        t.path=route(ctx.world.navigation,from,destinations[t.goal]);t.node=1;t.node_started=now
    end
    local fire=elapsed%6<2.5
    input.button(ctx.input,'fire',fire and {pressed=true} or {released=true},'benchmark')
    if ctx.weapons.inventory[ctx.weapons.equipped].mag<8 then input.button(ctx.input,'reload',{pressed=true},'benchmark')
    else input.button(ctx.input,'reload',{released=true},'benchmark') end
    local fired=ctx.weapons.sim.fired
    if fired>=t.last_shots then t.shots=t.shots+fired-t.last_shots end;t.last_shots=fired
    if ctx.weapons.clip~=t.last_clip and (ctx.weapons.clip=='reloadEmpty' or ctx.weapons.clip=='reloadTac') then t.reloads=t.reloads+1 end
    t.last_clip=ctx.weapons.clip
    if now-t.last_event>=12 then
        t.last_event=now
        if grenades.launch(ctx,'enemy_2',{x=p.x+2,y=p.y+.4,z=p.z-2},{x=0,y=0,z=0}) then t.grenades=t.grenades+1 end
        local actor=ctx.ai.actors.enemy_1
        if actor and actor.actor.alive then
            combat.request(ctx.combat,{target='enemy_1',source='player',amount=1000});t.kills=t.kills+1
        end
    end
    if now-t.last_restart>=45 then
        -- Restore all six actors and inventory while preserving the traversal pose.
        local position={x=p.x,y=p.y,z=p.z};local yaw=m.yaw
        restart(self);player.reset(ctx,position,yaw);ctx.ai.damage_scale=0
        t.last_restart=now;t.restarts=t.restarts+1;t.last_shots=0
    end
    if now>=t.report_at then
        t.report_at=now+30
        local r={elapsed=elapsed,preset=self.quality.active,targets=self.renderer_stats.target_count,
            target_bytes=self.renderer_stats.target_bytes,distance=t.distance}
        t.history[#t.history+1]=r
        local line='SUSTAINED PROGRESS '..json.encode(r)
        if html5 then html5.run('console.log('..json.encode(line)..')') else print(line) end
    end
    if elapsed>=t.warmup+t.duration then
        t.done=true;input.release_source(ctx.input,'benchmark')
        local r={engine=sys.get_engine_info(),system=sys.get_sys_info(),warmup_seconds=t.warmup,sample_seconds=t.duration,
            frame_metric='wall-clock engine update intervals; presentation timestamps unavailable',frames=percentiles(t.samples),
            raw_frame_ms=t.samples,quality=Q.snapshot(self.quality),loaded_seconds=t.loaded_seconds,
            reached=t.reached,distance=t.distance,shots=t.shots,reloads=t.reloads,grenades=t.grenades,kills=t.kills,restarts=t.restarts,
            stalls=t.stalls,failure=t.failure,history=t.history,renderer=self.renderer_stats,
            physics=require('game.physics.defold').snapshot(ctx.services.dynamics),fx=require('game.render.combat_fx_defold').snapshot(self.combat_visuals),
            missing={'GPU timestamps','per-frame CPU timestamps','verified presented-frame timestamps','shader-compilation trace','thermal telemetry'}}
        if html5 then html5.run('window.__SUSTAINED_RESULT__='..json.encode(r))
        else
            local path=sys.get_config_string('sustained.output','build/sustained-result.json')
            local f=assert(io.open(path,'w'));f:write(json.encode(r));f:close()
            print('SUSTAINED DONE '..json.encode(r.frames))
        end
    end
end
return M
