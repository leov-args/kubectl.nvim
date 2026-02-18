local M = {}

-- ============================================================================
-- Configuration
-- ============================================================================

local config = {
	log_level = vim.log.levels.INFO,
	tmux_split_cmd = "tmux split-window -h '%s; read'",
	notify_timeout = 5000,
}

--- Setup user configuration
-- @param opts table: user options (log_level, tmux_split_cmd, notify_timeout)
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- ============================================================================
-- Dependencies
-- ============================================================================

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
	vim.notify("Telescope is required for kubectl.nvim", vim.log.levels.ERROR)
	return M
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local sorter = require("telescope.config").values.generic_sorter

-- ============================================================================
-- Utility Functions
-- ============================================================================

--- Show notification to user
-- @param msg string: message to display
-- @param level number: vim.log.levels (optional)
local function notify(msg, level)
	vim.notify(msg, level or config.log_level, { timeout = config.notify_timeout })
end

--- Execute system command safely
-- @param cmd string: command to execute
-- @return string|nil: command output or nil on error
local function run_cmd(cmd)
	print("Running command: " .. cmd)
	local ok, result = pcall(vim.fn.system, cmd)
	if not ok or vim.v.shell_error ~= 0 then
		notify("Command failed: " .. cmd .. "\n" .. (result or ""), vim.log.levels.ERROR)
		return nil
	end
	return result
end

--- Convert date components to UTC epoch timestamp
-- Uses mathematical algorithm to calculate days since epoch without timezone issues
-- @param y number: year
-- @param m number: month (1-12)
-- @param d number: day
-- @param H number: hour
-- @param M number: minute
-- @param S number: second
-- @return number: seconds since Unix epoch (UTC)
local function utc_epoch(y, m, d, H, M, S)
	-- Algorithm based on https://stackoverflow.com/a/41099361
	if m < 3 then
		y = y - 1
		m = m + 12
	end
	local days = math.floor(365.25 * y) + math.floor(30.6001 * (m + 1)) + d - 719561
	return days * 86400 + H * 3600 + M * 60 + S
end

--- Format timestamp as age string (matches kubectl output format)
-- Calculates time elapsed since startedAt in same format as 'kubectl get pods'
-- @param start_time string: RFC3339 timestamp (e.g., "2026-02-18T18:36:18Z")
-- @return string: formatted age (e.g., "35m", "2h", "3d") or "?" if invalid
local function format_age(start_time)
	if not start_time then
		return "?"
	end

	local pattern = "^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z$"
	local y, m, d, H, M, S = start_time:match(pattern)
	if not y then
		return "?"
	end

	local started_utc = utc_epoch(tonumber(y), tonumber(m), tonumber(d), tonumber(H), tonumber(M), tonumber(S))
	local now_dt = os.date("!*t")
	local now_utc = utc_epoch(now_dt.year, now_dt.month, now_dt.day, now_dt.hour, now_dt.min, now_dt.sec)
	local diff = now_utc - started_utc

	if diff < 0 then
		return "0s"
	elseif diff < 60 then
		return string.format("%ds", diff)
	elseif diff < 3600 then
		return string.format("%dm", math.floor(diff / 60))
	elseif diff < 86400 then
		return string.format("%dh", math.floor(diff / 3600))
	else
		return string.format("%dd", math.floor(diff / 86400))
	end
end

-- ============================================================================
-- Kubernetes Operations
-- ============================================================================

--- Restart a Kubernetes deployment
-- @param deployment_name string: name of the deployment to restart
function M.restart_deployment(deployment_name)
	local cmd = string.format("kubectl rollout restart deployment %s", deployment_name)
	local result = run_cmd(cmd)
	if result then
		notify("Deployment " .. deployment_name .. " restarted.", vim.log.levels.INFO)
	end
end

--- Update container image interactively
-- Prompts user for new version tag and updates deployment image
-- @param container_name string: name of the container/deployment
-- @param image string: current image (e.g., "registry/image:v1.0")
-- @param cb function|nil: optional callback after successful update
function M.update_image(container_name, image, cb)
	vim.ui.input({ prompt = "New version for " .. container_name .. ": " }, function(new_version)
		if new_version and #new_version > 0 then
			local image_base = image:match("^[^:]+")
			local new_image = image_base .. ":" .. new_version
			local cmd =
				string.format("kubectl set image deployment/%s %s=%s", container_name, container_name, new_image)
			local result = run_cmd(cmd)
			if result then
				notify("Deployment image updated: " .. cmd, vim.log.levels.INFO)
				if cb then
					cb()
				end
			end
		end
	end)
end

--- List all pods and containers with interactive Telescope picker
-- Shows pod name, container image, status, and age (time since last restart)
-- Key mappings:
--   <CR>: Open logs in tmux split
--   <C-r>: Restart deployment
--   <C-i>: Update container image version
function M.list_pods()
	local output = run_cmd("kubectl get pods -o json")
	if not output then
		return
	end

	local ok, json = pcall(vim.fn.json_decode, output)
	if not ok or not json or not json.items then
		notify("Failed to parse kubectl output.", vim.log.levels.ERROR)
		return
	end

	local pods = {}
	for _, pod in ipairs(json.items) do
		local pod_status = "Unknown"
		if pod.status and pod.status.phase then
			pod_status = pod.status.phase
		end

		-- Extract container status to get actual runtime (startedAt)
		local container_statuses = pod.status and pod.status.containerStatuses or {}
		for _, container in ipairs(pod.spec.containers or {}) do
			-- Find the container's startedAt time (reflects time since last restart)
			local started_at = nil
			for _, cs in ipairs(container_statuses) do
				if cs.name == container.name and cs.state and cs.state.running and cs.state.running.startedAt then
					started_at = cs.state.running.startedAt
					break
				end
			end

			local age = format_age(started_at)
			table.insert(pods, {
				pod_name = pod.metadata.name,
				container_name = container.name,
				status = pod_status,
				image = container.image,
				age = age,
				display = string.format("%-40s | %-60s | %-8s | %6s", pod.metadata.name, container.image, pod_status, age),
			})
		end
	end

	pickers
		.new({}, {
			prompt_title = "Kubernetes Pods (Images)",
			finder = finders.new_table({
				results = pods,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.container_name,
					}
				end,
			}),
			sorter = sorter({}),
			attach_mappings = function(_, map)
				-- <CR>: Show logs in tmux split
				map("i", "<CR>", function(prompt_bufnr)
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					local logs_cmd = string.format("kubectl logs -f --tail 100 %s", selection.pod_name)
					local tmux_cmd = string.format(config.tmux_split_cmd, logs_cmd)
					run_cmd(tmux_cmd)
				end)
				-- <C-r>: Restart deployment
				map("i", "<C-r>", function(prompt_bufnr)
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					M.restart_deployment(selection.container_name)
				end)
				-- <C-i>: Change image version
				map("i", "<C-i>", function(prompt_bufnr)
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					M.update_image(selection.container_name, selection.image)
				end)
				return true
			end,
		})
		:find()
end

return M
