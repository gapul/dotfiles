-- SketchyBar Helpers Initialization
-- Enhanced with error handling and robustness

-- Utility functions
local function log_error(message)
    io.stderr:write("[ERROR] Helpers: " .. message .. "\n")
end

local function log_info(message)
    io.stdout:write("[INFO] Helpers: " .. message .. "\n")
end

-- Get username safely
local user = os.getenv("USER") or os.getenv("USERNAME") or "unknown"
if user == "unknown" then
    log_error("Could not determine username")
end

-- Add the sketchybar module to the package cpath
local sketchybar_lua_path = "/Users/" .. user .. "/.local/share/sketchybar_lua/?.so"
package.cpath = package.cpath .. ";" .. sketchybar_lua_path

-- Get and validate config directory
local config_dir = os.getenv("CONFIG_DIR") or "/Users/yuki/dotfiles/configs/wm/sketchybar"
local helpers_dir = config_dir .. "/helpers"

-- Check if helpers directory exists
local function directory_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

if not directory_exists(helpers_dir .. "/makefile") and not directory_exists(helpers_dir .. "/Makefile") then
    log_error("Helpers makefile not found in: " .. helpers_dir)
    return false
end

-- Build helpers with error checking
log_info("Building helper binaries...")
local build_cmd = "cd '" .. helpers_dir .. "' && make 2>&1"
local handle = io.popen(build_cmd)

if handle then
    local build_output = handle:read("*a")
    local success = handle:close()
    
    if success then
        log_info("Helper binaries built successfully")
        -- Verify critical binaries exist
        local cpu_binary = helpers_dir .. "/event_providers/cpu_load/bin/cpu_load"
        local network_binary = helpers_dir .. "/event_providers/network_load/bin/network_load"
        
        if directory_exists(cpu_binary) and directory_exists(network_binary) then
            log_info("All critical helper binaries verified")
        else
            log_error("Some helper binaries missing after build")
        end
    else
        log_error("Failed to build helper binaries:")
        log_error(build_output)
    end
else
    log_error("Could not execute build command")
end

return true
