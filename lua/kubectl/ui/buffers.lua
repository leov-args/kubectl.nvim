local M = {}
local config = require("kubectl.config")
local state = require("kubectl.state")

local MAX_LOG_LINES = 10000 -- Maximum lines to keep in buffer

--- Create a scratch buffer for logs
-- @param pod_name string: name of the pod
-- @param container_name string|nil: name of the container
-- @return number: buffer number
local function create_log_buffer(pod_name, container_name)
	local buf = vim.api.nvim_create_buf(false, true) -- not listed, scratch
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "log")
	vim.api.nvim_buf_set_option(buf, "wrap", true)

	local title = container_name and string.format("%s/%s", pod_name, container_name) or pod_name
	vim.api.nvim_buf_set_name(buf, string.format("kubectl-logs://%s", title))

	return buf
end

--- Trim buffer to max lines (circular buffer)
-- @param buf number: buffer number
local function trim_buffer(buf)
	local line_count = vim.api.nvim_buf_line_count(buf)
	if line_count > MAX_LOG_LINES then
		local lines_to_delete = line_count - MAX_LOG_LINES
		vim.api.nvim_buf_set_lines(buf, 0, lines_to_delete, false, {})
	end
end

--- Set keymaps for log buffer
-- @param buf number: buffer number
-- @param job_id number: job id
local function set_log_keymaps(buf, job_id)
	local opts = { buffer = buf, nowait = true, silent = true }

	-- q: Close buffer and stop job
	vim.keymap.set("n", "q", function()
		vim.fn.jobstop(job_id)
		state.unregister_job(job_id)
		vim.cmd("close")
	end, opts)

	-- <C-c>: Stop log stream
	vim.keymap.set("n", "<C-c>", function()
		vim.fn.jobstop(job_id)
		state.unregister_job(job_id)
		vim.notify("Log stream stopped", vim.log.levels.INFO)
	end, opts)
end

--- Open log window
-- @param buf number: buffer number
local function open_log_window(buf)
	local split_type = config.get().log_buffer_split

	if split_type == "tabnew" then
		vim.cmd("tabnew")
	elseif split_type == "split" then
		vim.cmd("split")
	else -- "vsplit"
		vim.cmd("vsplit")
	end

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
end

--- Stream logs from pod to buffer
-- @param pod_name string: name of the pod
-- @param container_name string|nil: name of the container (for multi-container pods)
-- @param namespace string|nil: namespace of the pod
function M.open_logs(pod_name, container_name, namespace)
	local buf = create_log_buffer(pod_name, container_name)
	open_log_window(buf)

	local cmd = { "kubectl", "logs", "-f", "--tail=100", pod_name }
	if namespace then
		table.insert(cmd, "-n")
		table.insert(cmd, namespace)
	end
	if container_name then
		table.insert(cmd, "-c")
		table.insert(cmd, container_name)
	end

	local follow_mode = config.get().log_follow_mode

	local job_id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data, _)
			if not data then
				return
			end

			vim.schedule(function()
				-- Filter out empty lines at the end
				local lines = vim.tbl_filter(function(line)
					return line ~= ""
				end, data)

				if #lines > 0 then
					-- Get current line count before appending
					local line_count = vim.api.nvim_buf_line_count(buf)
					local was_at_end = false

					-- Check if cursor is at the end (for follow mode)
					local windows = vim.fn.win_findbuf(buf)
					if #windows > 0 and follow_mode then
						local win = windows[1]
						local cursor = vim.api.nvim_win_get_cursor(win)
						was_at_end = cursor[1] >= line_count - 1
					end

					-- Append new lines
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)

					-- Auto-scroll if follow mode and was at end
					if follow_mode and was_at_end and #windows > 0 then
						local win = windows[1]
						local new_line_count = vim.api.nvim_buf_line_count(buf)
						vim.api.nvim_win_set_cursor(win, { new_line_count, 0 })
					end

					-- Trim buffer to max lines
					trim_buffer(buf)
				end
			end)
		end,
		on_stderr = function(_, data, _)
			if not data then
				return
			end
			vim.schedule(function()
				local lines = vim.tbl_filter(function(line)
					return line ~= ""
				end, data)
				if #lines > 0 then
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
					trim_buffer(buf)
				end
			end)
		end,
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				if exit_code ~= 0 then
					vim.notify(
						string.format("Log stream exited with code %d", exit_code),
						vim.log.levels.WARN
					)
				end
				state.unregister_job(job_id)
			end)
		end,
		stdout_buffered = false,
		stderr_buffered = false,
	})

	if job_id <= 0 then
		vim.notify("Failed to start log stream", vim.log.levels.ERROR)
		vim.api.nvim_buf_delete(buf, { force = true })
		return
	end

	state.register_job(job_id, pod_name)
	set_log_keymaps(buf, job_id)

	-- Add initial message
	vim.schedule(function()
		vim.api.nvim_buf_set_lines(
			buf,
			0,
			0,
			false,
			{ string.format("=== Streaming logs from %s ===", pod_name), "" }
		)
	end)
end

return M
