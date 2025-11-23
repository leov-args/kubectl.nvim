local M = {}

-- Default configuration
local config = {
	log_level = vim.log.levels.INFO,
	tmux_split_cmd = "tmux split-window -h '%s; read'",
	notify_timeout = 5000,
}

--- Setup user configuration
-- @param opts table: user options
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Utility: Notification wrapper
local function notify(msg, level)
	vim.notify(msg, level or config.log_level, { timeout = config.notify_timeout })
end

-- Utility: Safe system command execution
local function run_cmd(cmd)
	local ok, result = pcall(vim.fn.system, cmd)
	if not ok or vim.v.shell_error ~= 0 then
		notify("Command failed: " .. cmd .. "\n" .. (result or ""), vim.log.levels.ERROR)
		return nil
	end
	return result
end

-- Telescope dependencies
local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
	notify("Telescope is required for kubectl.nvim", vim.log.levels.ERROR)
	return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local sorter = require("telescope.config").values.generic_sorter

--- Restart a Kubernetes deployment
-- @param deployment_name string
function M.restart_deployment(deployment_name)
	local cmd = string.format("kubectl rollout restart deployment %s", deployment_name)
	local result = run_cmd(cmd)
	if result then
		notify("Deployment " .. deployment_name .. " restarted.", vim.log.levels.INFO)
	end
end

--- Update container image interactively
-- @param pod_name string
-- @param container_name string
-- @param image string
-- @param cb function|nil
function M.update_image(pod_name, container_name, image, cb)
	vim.ui.input({ prompt = "New version for " .. container_name .. ": " }, function(new_version)
		if new_version and #new_version > 0 then
			local image_base = image:match("^[^:]+")
			local new_image = image_base .. ":" .. new_version
			local cmd = string.format("kubectl set image pod/%s %s=%s", pod_name, container_name, new_image)
			local result = run_cmd(cmd)
			if result then
				notify("Image updated: " .. cmd, vim.log.levels.INFO)
				if cb then
					cb()
				end
			end
		end
	end)
end

--- List pods and containers with Telescope
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
		for _, container in ipairs(pod.spec.containers or {}) do
			table.insert(pods, {
				pod_name = pod.metadata.name,
				container_name = container.name,
				image = container.image,
				display = string.format("%-30s | %-20s | %s", pod.metadata.name, container.name, container.image),
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
				-- <C-r>: restart deployment
				map("i", "<C-r>", function()
					local selection = action_state.get_selected_entry().value
					M.restart_deployment(selection.container_name)
				end)
				-- <C-i>: Change image version
				map("i", "<C-i>", function(prompt_bufnr)
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					M.update_image(selection.pod_name, selection.container_name, selection.image)
				end)
				return true
			end,
		})
		:find()
end

return M
