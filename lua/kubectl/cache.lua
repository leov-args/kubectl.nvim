local M = {}
local config = require("kubectl.config")

-- Cache storage
local cache = {
	pods = { data = nil, timestamp = 0, namespace = nil },
	namespaces = { data = nil, timestamp = 0 },
}

--- Check if cache entry is valid
-- @param entry table: cache entry with data, timestamp
-- @param ttl number: time-to-live in seconds
-- @return boolean: true if cache is valid and not expired
local function is_cache_valid(entry, ttl)
	return entry.data ~= nil and (os.time() - entry.timestamp) < ttl
end

--- Get cached data or fetch new
-- @param key string: cache key (e.g., "pods", "namespaces")
-- @param fetch_fn function: function to fetch fresh data if cache is invalid
-- @param ttl number|nil: time-to-live in seconds (uses config.cache_ttl if nil)
-- @param force_refresh boolean|nil: force refresh even if cache is valid
-- @return any: cached or freshly fetched data
function M.get_or_fetch(key, fetch_fn, ttl, force_refresh)
	ttl = ttl or config.get().cache_ttl

	local entry = cache[key]
	if not entry then
		error("Invalid cache key: " .. key)
	end

	-- Return cached data if valid and not forcing refresh
	if not force_refresh and is_cache_valid(entry, ttl) then
		return entry.data
	end

	-- Fetch fresh data
	local data = fetch_fn()
	if data then
		entry.data = data
		entry.timestamp = os.time()
	end

	return entry.data
end

--- Invalidate specific cache entry
-- @param key string: cache key to invalidate
function M.invalidate(key)
	local entry = cache[key]
	if entry then
		entry.data = nil
		entry.timestamp = 0
	end
end

--- Invalidate all cache entries
function M.invalidate_all()
	for key, _ in pairs(cache) do
		M.invalidate(key)
	end
end

--- Set namespace for pods cache (used to detect namespace changes)
-- @param namespace string: namespace name
function M.set_pods_namespace(namespace)
	cache.pods.namespace = namespace
end

--- Get namespace from pods cache
-- @return string|nil: namespace or nil
function M.get_pods_namespace()
	return cache.pods.namespace
end

--- Check if cache is valid for specific namespace
-- @param namespace string: namespace to check
-- @return boolean: true if cache matches namespace
function M.is_valid_for_namespace(namespace)
	return cache.pods.namespace == namespace and cache.pods.data ~= nil
end

return M
