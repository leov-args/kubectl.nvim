local M = {}

-- ============================================================================
-- Module Dependencies
-- ============================================================================

local config_mod = require("kubectl.config")
local state = require("kubectl.state")
local cache = require("kubectl.cache")
local k8s_client = require("kubectl.k8s_client")

--- Setup user configuration
-- @param opts table: user options
function M.setup(opts)
	config_mod.setup(opts)

	-- Check if kubectl is available
	local available, err = k8s_client.check_kubectl_available()
	if not available then
		vim.notify("kubectl.nvim: " .. err, vim.log.levels.ERROR)
	end

	-- Setup cleanup on exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			state.cleanup()
		end,
	})
end

-- ============================================================================
-- Telescope Dependencies
-- ============================================================================

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
	vim.notify("kubectl.nvim: Telescope is required", vim.log.levels.ERROR)
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
	local conf = config_mod.get()
	vim.notify(msg, level or conf.log_level, { timeout = conf.notify_timeout })
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
-- @param namespace string|nil: namespace of the deployment
function M.restart_deployment(deployment_name, namespace)
	local success, err = k8s_client.restart_deployment(deployment_name, namespace)
	if success then
		notify("Deployment " .. deployment_name .. " restarted.", vim.log.levels.INFO)
		cache.invalidate("pods")
	else
		notify("Failed to restart deployment: " .. err, vim.log.levels.ERROR)
	end
end

--- Update container image interactively
-- Prompts user for new version tag and updates deployment image
-- @param container_name string: name of the container/deployment
-- @param image string: current image (e.g., "registry/image:v1.0")
-- @param namespace string|nil: namespace of the deployment
-- @param cb function|nil: optional callback after successful update
function M.update_image(container_name, image, namespace, cb)
	vim.ui.input({ prompt = "New version for " .. container_name .. ": " }, function(new_version)
		if new_version and #new_version > 0 then
			local image_base = image:match("^[^:]+")
			local new_image = image_base .. ":" .. new_version

			local success, err = k8s_client.update_image(container_name, container_name, new_image, namespace)
			if success then
				notify("Deployment image updated to " .. new_image, vim.log.levels.INFO)
				cache.invalidate("pods")
				if cb then
					cb()
				end
			else
				notify("Failed to update image: " .. err, vim.log.levels.ERROR)
			end
		end
	end)
end

--- Select a specific namespace interactively
-- Opens a Telescope picker with all available namespaces
function M.select_namespace()
	local conf = config_mod.get()

	-- Fetch namespaces
	local namespaces, err = k8s_client.get_namespaces()
	if not namespaces then
		notify("Failed to get namespaces: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return
	end

	-- Build namespace list
	local ns_list = {}
	for _, ns in ipairs(namespaces) do
		local ns_name = ns.metadata and ns.metadata.name or "unknown"
		local ns_status = ns.status and ns.status.phase or "Unknown"
		table.insert(ns_list, {
			name = ns_name,
			status = ns_status,
			display = string.format("%-40s | %s", ns_name, ns_status),
		})
	end

	-- Create Telescope picker
	pickers
		.new({}, {
			prompt_title = "Select Namespace",
			finder = finders.new_table({
				results = ns_list,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				-- <CR>: Select namespace and list pods
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					
					state.set_selected_namespace(selection.name)
					cache.invalidate("pods")
					notify("Selected namespace: " .. selection.name, vim.log.levels.INFO)
					
					vim.schedule(function()
						M.list_pods()
					end)
				end)

				return true
			end,
		})
		:find()
end

--- List all pods and containers with interactive Telescope picker
-- Shows pod name, container image, status, age, and restart count
-- Key mappings:
--   <CR>: Open logs (tmux or buffer based on config)
--   <C-r>: Restart deployment
--   <C-i>: Update container image version
--   <C-n>: Toggle namespace mode (current/all)
--   <C-s>: Select specific namespace
function M.list_pods()
	local conf = config_mod.get()
	local namespace_mode = state.get_namespace_mode()

	-- Determine namespace to query
	local query_namespace
	if namespace_mode == "all" then
		query_namespace = "all"
	elseif namespace_mode == "specific" then
		query_namespace = state.get_selected_namespace() or "current"
	else
		query_namespace = "current"
	end

	-- Fetch pods (with caching)
	local fetch_pods = function()
		return k8s_client.get_pods(query_namespace)
	end

	local json, err = cache.get_or_fetch("pods", fetch_pods, conf.cache_ttl)
	if not json then
		notify("Failed to get pods: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return
	end

	-- Get current namespace for title
	local current_namespace = state.get_current_namespace()
	if not current_namespace then
		current_namespace, _ = k8s_client.get_current_namespace()
		state.set_current_namespace(current_namespace)
	end

	-- Build prompt title
	local prompt_title
	if namespace_mode == "all" then
		prompt_title = "Kubernetes Pods (all namespaces)"
	elseif namespace_mode == "specific" then
		local selected_ns = state.get_selected_namespace()
		prompt_title = string.format("Kubernetes Pods (namespace: %s)", selected_ns)
	else
		prompt_title = string.format("Kubernetes Pods (namespace: %s)", current_namespace)
	end

	-- Process pods data
	local pods = {}
	for _, pod in ipairs(json.items or {}) do
		local pod_status = "Unknown"
		if pod.status and pod.status.phase then
			pod_status = pod.status.phase
		end

		local pod_namespace = pod.metadata and pod.metadata.namespace or "default"

		-- Extract container status to get actual runtime (startedAt) and restart count
		local container_statuses = pod.status and pod.status.containerStatuses or {}
		for _, container in ipairs(pod.spec.containers or {}) do
			-- Find the container's startedAt time and restart count
			local started_at = nil
			local restart_count = 0

			for _, cs in ipairs(container_statuses) do
				if cs.name == container.name then
					if cs.state and cs.state.running and cs.state.running.startedAt then
						started_at = cs.state.running.startedAt
					end
					restart_count = cs.restartCount or 0
					break
				end
			end

			local age = format_age(started_at)

			-- Build display string with conditional namespace prefix
			local display
			if namespace_mode == "all" then
				display = string.format(
					"[%s] %-35s | %-50s | %-8s | %6s | %3d",
					pod_namespace,
					pod.metadata.name,
					container.image,
					pod_status,
					age,
					restart_count
				)
			else
				display = string.format(
					"%-40s | %-50s | %-8s | %6s | %3d",
					pod.metadata.name,
					container.image,
					pod_status,
					age,
					restart_count
				)
			end

			table.insert(pods, {
				pod_name = pod.metadata.name,
				container_name = container.name,
				namespace = pod_namespace,
				status = pod_status,
				image = container.image,
				age = age,
				restarts = restart_count,
				display = display,
			})
		end
	end

	-- Create Telescope picker
	pickers
		.new({}, {
			prompt_title = prompt_title,
			finder = finders.new_table({
				results = pods,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.pod_name .. " " .. entry.container_name,
					}
				end,
			}),
			sorter = sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				-- <CR>: Show logs (tmux or buffer based on config)
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)

					if conf.log_output == "buffer" then
						require("kubectl.ui.buffers").open_logs(selection.pod_name, selection.container_name, selection.namespace)
					else
						-- Tmux mode (backward compatibility)
						local logs_cmd = string.format("kubectl logs -f --tail 100 %s -n %s", selection.pod_name, selection.namespace)
						if selection.container_name then
							logs_cmd = logs_cmd .. " -c " .. selection.container_name
						end
						local tmux_cmd = string.format(conf.tmux_split_cmd, logs_cmd)
						vim.fn.system(tmux_cmd)
					end
				end)

				-- <C-r>: Restart deployment
				map("i", "<C-r>", function()
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					M.restart_deployment(selection.container_name, selection.namespace)
				end)

				-- <C-i>: Change image version
				map("i", "<C-i>", function()
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					M.update_image(selection.container_name, selection.image, selection.namespace)
				end)

				-- <C-n>: Toggle namespace mode
				map("i", "<C-n>", function()
					actions.close(prompt_bufnr)
					state.toggle_namespace_mode()
					cache.invalidate("pods")
					notify(
						"Namespace mode: " .. state.get_namespace_mode(),
						vim.log.levels.INFO
					)
					-- Re-open picker with new mode
					vim.schedule(function()
						M.list_pods()
					end)
				end)

				-- <C-f>: Force refresh (invalidate cache and reload)
				map("i", "<C-f>", function()
					actions.close(prompt_bufnr)
					cache.invalidate("pods")
					notify("Refreshing pods...", vim.log.levels.INFO)
					vim.schedule(function()
						M.list_pods()
					end)
				end)

				-- <C-s>: Select specific namespace
				map("i", "<C-s>", function()
					actions.close(prompt_bufnr)
					vim.schedule(function()
						M.select_namespace()
					end)
				end)

				return true
			end,
		})
		:find()
end

return M
