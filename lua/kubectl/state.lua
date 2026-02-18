local M = {}

-- Module state
M.namespace_mode = "current" -- "current" | "all" | "specific"
M.current_namespace = nil -- Cached current namespace
M.selected_namespace = nil -- User-selected specific namespace
M.active_jobs = {} -- Track active log stream jobs
M.timers = {} -- Track refresh timers

--- Get namespace mode
-- @return string: "current" or "all"
function M.get_namespace_mode()
	return M.namespace_mode
end

--- Set namespace mode
-- @param mode string: "current", "all", or "specific"
function M.set_namespace_mode(mode)
	if mode ~= "current" and mode ~= "all" and mode ~= "specific" then
		error("Invalid namespace mode: " .. mode)
	end
	M.namespace_mode = mode
end

--- Toggle namespace mode between "current" and "all"
function M.toggle_namespace_mode()
	M.namespace_mode = (M.namespace_mode == "all") and "current" or "all"
end

--- Get current namespace (cached)
-- @return string|nil: current namespace or nil if not set
function M.get_current_namespace()
	return M.current_namespace
end

--- Set current namespace
-- @param namespace string: namespace name
function M.set_current_namespace(namespace)
	M.current_namespace = namespace
end

--- Get selected specific namespace
-- @return string|nil: selected namespace or nil if not set
function M.get_selected_namespace()
	return M.selected_namespace
end

--- Set selected specific namespace
-- @param namespace string: namespace name
function M.set_selected_namespace(namespace)
	M.selected_namespace = namespace
	M.namespace_mode = "specific"
end

--- Register active job
-- @param job_id number: job id from vim.fn.jobstart
-- @param pod_name string: pod name
function M.register_job(job_id, pod_name)
	M.active_jobs[job_id] = pod_name
end

--- Unregister active job
-- @param job_id number: job id
function M.unregister_job(job_id)
	M.active_jobs[job_id] = nil
end

--- Stop all active jobs
function M.stop_all_jobs()
	for job_id, _ in pairs(M.active_jobs) do
		vim.fn.jobstop(job_id)
	end
	M.active_jobs = {}
end

--- Register timer
-- @param timer_id number: timer id from vim.fn.timer_start
function M.register_timer(timer_id)
	table.insert(M.timers, timer_id)
end

--- Stop all timers
function M.stop_all_timers()
	for _, timer_id in ipairs(M.timers) do
		vim.fn.timer_stop(timer_id)
	end
	M.timers = {}
end

--- Cleanup all resources (jobs, timers)
function M.cleanup()
	M.stop_all_jobs()
	M.stop_all_timers()
end

return M
