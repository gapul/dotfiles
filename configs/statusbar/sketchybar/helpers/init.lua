-- Add the sketchybar module to the package cpath
package.cpath = package.cpath .. ";/Users/" .. os.getenv("USER") .. "/.local/share/sketchybar_lua/?.so"

-- Build helpers (commented out to avoid startup delays)
-- local config_dir = os.getenv("HOME") .. "/.config/sketchybar"
-- os.execute("(cd " .. config_dir .. "/helpers && make)")
