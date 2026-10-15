-- One encounter-wide budget, shared by every fixed tick in a rendered frame.
-- Jobs yield before clearance probes; one in-flight probe may exceed the time
-- allowance, but no second probe starts after it. Round robin prevents starvation.
local M = {}
function M.new(seconds,steps,clock)
    return {jobs={},seconds=seconds or .002,limit=steps or 32,clock=clock or os.clock,used=0,steps=0}
end
function M.add(planner,owner,run)
    local job={owner=owner,thread=coroutine.create(run)}
    planner.jobs[#planner.jobs+1]=job
    return job
end
function M.checkpoint() coroutine.yield() end
function M.step(planner,frame,valid)
    if planner.frame~=frame then planner.frame=frame;planner.used=0;planner.steps=0 end
    while #planner.jobs>0 and planner.steps<planner.limit and planner.used<planner.seconds do
        local job=table.remove(planner.jobs,1)
        if valid(job) then
            local started=planner.clock()
            if profiler then profiler.scope_begin("ai.navigation") end
            local ok,err=coroutine.resume(job.thread)
            if profiler then profiler.scope_end() end
            planner.used=planner.used+planner.clock()-started;planner.steps=planner.steps+1
            assert(ok,err)
            if coroutine.status(job.thread)~="dead" then planner.jobs[#planner.jobs+1]=job end
        end
    end
end
return M
