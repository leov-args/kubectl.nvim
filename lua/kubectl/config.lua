local M = {}

-- Default configuration
M.defaults = {
	-- Logging & Notifications
	log_level = vim.log.levels.INFO,
	notify_timeout = 5000,

	-- Tmux Integration
	tmux_split_cmd = "tmux split-window -h '%s; read'",

	-- Cache Settings
	cache_ttl = 30, -- seconds
	auto_refresh = true,
	auto_refresh_interval = 30, -- seconds

	-- Log Output
	log_output = "tmux", -- "tmux" | "buffer"
	log_buffer_split = "vsplit", -- "vsplit" | "split" | "tabnew"
	log_follow_mode = true, -- Auto-scroll to end

	-- Namespace Settings
	namespace_mode = "current", -- "current" | "all"

	-- UI Display
	show_restart_count = true,
	display_format = {
		pod_name_width = 40,
		image_width = 50,
		status_width = 10,
		age_width = 8,
		restarts_width = 8,
		namespace_width = 15,
	},
}

-- Current configuration (merged with user options)
M.options = vim.deepcopy(M.defaults)

--- Setup configuration with user options
-- @param user_opts table: user configuration options
function M.setup(user_opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

--- Get current configuration
-- @return table: current configuration
function M.get()
	return M.options
end

return M
