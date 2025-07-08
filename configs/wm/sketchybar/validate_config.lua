#!/usr/bin/env lua

-- SketchyBar Configuration Validator
-- Validates configuration files for syntax errors and missing dependencies

local function log_info(message)
    io.stdout:write("[INFO] Validator: " .. message .. "\n")
end

local function log_error(message)
    io.stderr:write("[ERROR] Validator: " .. message .. "\n")
end

local function log_warn(message)
    io.stderr:write("[WARN] Validator: " .. message .. "\n")
end

-- Configuration directory
local config_dir = os.getenv("CONFIG_DIR") or "/Users/yuki/dotfiles/configs/wm/sketchybar"

-- File existence checker
local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- Lua syntax validator
local function validate_lua_syntax(file_path)
    log_info("Validating Lua syntax: " .. file_path)
    
    local file = io.open(file_path, "r")
    if not file then
        log_error("Cannot open file: " .. file_path)
        return false
    end
    
    local content = file:read("*a")
    file:close()
    
    local chunk, error_msg = load(content, file_path)
    if not chunk then
        log_error("Syntax error in " .. file_path .. ": " .. error_msg)
        return false
    end
    
    log_info("Syntax OK: " .. file_path)
    return true
end

-- Required files checker
local function check_required_files()
    log_info("Checking required configuration files...")
    
    local required_files = {
        "init.lua",
        "bar.lua", 
        "colors.lua",
        "default.lua",
        "icons.lua",
        "settings.lua",
        "items/init.lua",
        "helpers/init.lua"
    }
    
    local missing_files = {}
    local invalid_files = {}
    
    for _, file in ipairs(required_files) do
        local full_path = config_dir .. "/" .. file
        if not file_exists(full_path) then
            table.insert(missing_files, file)
        elseif not validate_lua_syntax(full_path) then
            table.insert(invalid_files, file)
        end
    end
    
    if #missing_files > 0 then
        log_error("Missing required files:")
        for _, file in ipairs(missing_files) do
            log_error("  - " .. file)
        end
    end
    
    if #invalid_files > 0 then
        log_error("Files with syntax errors:")
        for _, file in ipairs(invalid_files) do
            log_error("  - " .. file)
        end
    end
    
    return #missing_files == 0 and #invalid_files == 0
end

-- Helper binaries checker
local function check_helper_binaries()
    log_info("Checking helper binaries...")
    
    local helpers_dir = config_dir .. "/helpers"
    local required_binaries = {
        "event_providers/cpu_load/bin/cpu_load",
        "event_providers/network_load/bin/network_load",
        "menus/bin/menus"
    }
    
    local missing_binaries = {}
    
    for _, binary in ipairs(required_binaries) do
        local full_path = helpers_dir .. "/" .. binary
        if not file_exists(full_path) then
            table.insert(missing_binaries, binary)
        else
            -- Check if executable
            local handle = io.popen("test -x '" .. full_path .. "' && echo 'executable' || echo 'not_executable'")
            local result = handle:read("*a"):gsub("%s+", "")
            handle:close()
            
            if result ~= "executable" then
                table.insert(missing_binaries, binary .. " (not executable)")
            end
        end
    end
    
    if #missing_binaries > 0 then
        log_error("Missing or non-executable helper binaries:")
        for _, binary in ipairs(missing_binaries) do
            log_error("  - " .. binary)
        end
        log_info("Run 'make' in the helpers directory to build missing binaries")
        return false
    end
    
    log_info("All helper binaries are present and executable")
    return true
end

-- System dependencies checker  
local function check_system_dependencies()
    log_info("Checking system dependencies...")
    
    local required_commands = {
        "sketchybar",
        "lua",
        "make"
    }
    
    local missing_commands = {}
    
    for _, cmd in ipairs(required_commands) do
        local handle = io.popen("command -v " .. cmd .. " >/dev/null 2>&1 && echo 'found' || echo 'not_found'")
        local result = handle:read("*a"):gsub("%s+", "")
        handle:close()
        
        if result ~= "found" then
            table.insert(missing_commands, cmd)
        end
    end
    
    if #missing_commands > 0 then
        log_error("Missing system dependencies:")
        for _, cmd in ipairs(missing_commands) do
            log_error("  - " .. cmd)
        end
        return false
    end
    
    log_info("All system dependencies are satisfied")
    return true
end

-- Configuration consistency checker
local function check_configuration_consistency()
    log_info("Checking configuration consistency...")
    
    -- Check if aerospace configuration matches sketchybar workspace setup
    local aerospace_config = "/Users/yuki/dotfiles/configs/wm/aerospace/aerospace.toml"
    if file_exists(aerospace_config) then
        local file = io.open(aerospace_config, "r")
        if file then
            local content = file:read("*a")
            file:close()
            
            -- Check workspace count (looking for 1-8 pattern)
            if content:match("alt%-8 = 'workspace 8'") and not content:match("alt%-9 = 'workspace 9'") then
                log_info("Aerospace configuration matches SketchyBar (1-8 workspaces)")
            else
                log_warn("Aerospace workspace configuration may not match SketchyBar setup")
            end
        end
    else
        log_warn("Aerospace configuration not found, workspace consistency cannot be verified")
    end
    
    return true
end

-- Main validation function
local function main()
    log_info("Starting SketchyBar configuration validation...")
    log_info("Configuration directory: " .. config_dir)
    
    local all_checks_passed = true
    
    -- Check configuration directory exists
    if not file_exists(config_dir .. "/init.lua") then
        log_error("Configuration directory not found or invalid: " .. config_dir)
        return false
    end
    
    -- Run all checks
    local checks = {
        {name = "System Dependencies", func = check_system_dependencies},
        {name = "Required Files", func = check_required_files},
        {name = "Helper Binaries", func = check_helper_binaries},
        {name = "Configuration Consistency", func = check_configuration_consistency}
    }
    
    for _, check in ipairs(checks) do
        log_info("Running check: " .. check.name)
        if not check.func() then
            log_error("Check failed: " .. check.name)
            all_checks_passed = false
        else
            log_info("Check passed: " .. check.name)
        end
        log_info("") -- Empty line for readability
    end
    
    -- Final result
    if all_checks_passed then
        log_info("✅ All validation checks passed!")
        log_info("SketchyBar configuration is ready to use")
        return true
    else
        log_error("❌ Some validation checks failed")
        log_error("Please fix the issues above before starting SketchyBar")
        return false
    end
end

-- Execute validation
if main() then
    os.exit(0)
else
    os.exit(1)
end