local M = {}

--- Execute system command safely
-- @param cmd string: command to execute
-- @return string|nil: command output or nil on error
-- @return string|nil: error message if command failed
local function run_cmd(cmd)
	local ok, result = pcall(vim.fn.system, cmd)
	if not ok or vim.v.shell_error ~= 0 then
		local error_msg = result or "Unknown error"
		
		-- Parse common kubectl errors
		if error_msg:match("connection refused") then
			error_msg = "Cannot connect to Kubernetes cluster"
		elseif error_msg:match("context.*not found") or error_msg:match("current-context") then
			error_msg = "No Kubernetes context configured. Run 'kubectl config get-contexts'"
		elseif error_msg:match("forbidden") or error_msg:match("Forbidden") then
			error_msg = "Insufficient permissions to access this resource"
		elseif error_msg:match("not found") or error_msg:match("NotFound") then
			error_msg = "Resource not found in cluster"
		elseif error_msg:match("timed out") or error_msg:match("timeout") then
			error_msg = "Request timed out. Cluster may be slow or unreachable"
		end
		
		return nil, error_msg
	end
	return result, nil
end

--- Check if kubectl is available
-- @return boolean: true if kubectl is available
-- @return string|nil: error message if not available
function M.check_kubectl_available()
	local result, err = run_cmd("kubectl version --client -o json 2>&1")
	if not result then
		return false, "kubectl not found in PATH or not accessible"
	end
	return true, nil
end

--- Get current namespace from context
-- @return string: namespace name (defaults to "default" if not set)
-- @return string|nil: error message if command failed
function M.get_current_namespace()
	local cmd = "kubectl config view --minify -o json"
	local result, err = run_cmd(cmd)
	if not result then
		return "default", err
	end

	local ok, json = pcall(vim.fn.json_decode, result)
	if not ok or not json then
		return "default", "Failed to parse kubectl config"
	end

	-- Extract namespace from context
	if json.contexts and json.contexts[1] and json.contexts[1].context then
		local namespace = json.contexts[1].context.namespace
		return namespace or "default", nil
	end

	return "default", nil
end

--- Get all namespaces
-- @return table|nil: list of namespace objects or nil on error
-- @return string|nil: error message if command failed
function M.get_namespaces()
	local cmd = "kubectl get namespaces -o json"
	local result, err = run_cmd(cmd)
	if not result then
		return nil, err
	end

	local ok, json = pcall(vim.fn.json_decode, result)
	if not ok or not json or not json.items then
		return nil, "Failed to parse namespaces output"
	end

	return json.items, nil
end

--- Get pods from kubectl
-- @param namespace string|nil: namespace to query ("current", "all", or specific namespace)
-- @return table|nil: kubectl JSON output or nil on error
-- @return string|nil: error message if command failed
function M.get_pods(namespace)
	namespace = namespace or "current"

	local cmd
	if namespace == "all" then
		cmd = "kubectl get pods --all-namespaces -o json"
	elseif namespace == "current" then
		cmd = "kubectl get pods -o json"
	else
		cmd = string.format("kubectl get pods -n %s -o json", namespace)
	end

	local result, err = run_cmd(cmd)
	if not result then
		return nil, err
	end

	local ok, json = pcall(vim.fn.json_decode, result)
	if not ok or not json or not json.items then
		return nil, "Failed to parse kubectl output"
	end

	return json, nil
end

--- Restart a Kubernetes deployment
-- @param deployment_name string: name of the deployment
-- @param namespace string|nil: namespace (uses current if nil)
-- @return boolean: true if successful
-- @return string|nil: error message if failed
function M.restart_deployment(deployment_name, namespace)
	local cmd
	if namespace and namespace ~= "current" then
		cmd = string.format("kubectl rollout restart deployment %s -n %s", deployment_name, namespace)
	else
		cmd = string.format("kubectl rollout restart deployment %s", deployment_name)
	end

	local result, err = run_cmd(cmd)
	if not result then
		return false, err
	end
	return true, nil
end

--- Update container image
-- @param deployment_name string: name of the deployment
-- @param container_name string: name of the container
-- @param new_image string: new image with tag
-- @param namespace string|nil: namespace (uses current if nil)
-- @return boolean: true if successful
-- @return string|nil: error message if failed
function M.update_image(deployment_name, container_name, new_image, namespace)
	local cmd
	if namespace and namespace ~= "current" then
		cmd = string.format(
			"kubectl set image deployment/%s %s=%s -n %s",
			deployment_name,
			container_name,
			new_image,
			namespace
		)
	else
		cmd = string.format("kubectl set image deployment/%s %s=%s", deployment_name, container_name, new_image)
	end

	local result, err = run_cmd(cmd)
	if not result then
		return false, err
	end
	return true, nil
end

return M
