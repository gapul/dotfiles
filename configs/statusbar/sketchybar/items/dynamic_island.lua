-- Dynamic Island for SketchyBar
-- Adds iPhone 14 Pro style dynamic island functionality

local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

-- Dynamic Island Settings
local ISLAND_HEIGHT = 44
local ISLAND_WIDTH = 100
local ISLAND_CORNER_RADIUS = 22

-- Create dynamic island container
local dynamic_island = sbar.add("item", "dynamic_island", {
    position = "center",
    icon = {
        drawing = false
    },
    label = {
        drawing = false
    },
    background = {
        color = colors.black,
        corner_radius = ISLAND_CORNER_RADIUS,
        height = ISLAND_HEIGHT,
        width = ISLAND_WIDTH,
        border_width = 1,
        border_color = colors.with_alpha(colors.white, 0.1)
    },
    padding_left = 0,
    padding_right = 0
})

-- Dynamic Island Music Display
local island_music = sbar.add("item", "island_music", {
    position = "popup.dynamic_island",
    icon = {
        string = "♪",
        color = colors.white,
        font = {
            family = settings.font.text,
            style = settings.font.style_map["Bold"],
            size = 14.0
        },
        padding_left = 8,
        padding_right = 4
    },
    label = {
        string = "No Music",
        color = colors.white,
        font = {
            family = settings.font.text,
            style = settings.font.style_map["Regular"],
            size = 12.0
        },
        padding_right = 8
    },
    background = {
        drawing = false
    }
})

-- Update music info
island_music:subscribe("media_change", function(env)
    if env.INFO.state == "playing" then
        local artist = env.INFO.artist or "Unknown"
        local title = env.INFO.title or "Unknown"
        local display_text = artist .. " - " .. title
        
        -- Truncate if too long
        if string.len(display_text) > 30 then
            display_text = string.sub(display_text, 1, 27) .. "..."
        end
        
        island_music:set({
            label = display_text,
            icon = "▶"
        })
        
        -- Expand island when music is playing
        dynamic_island:set({
            background = {
                width = math.min(200, 100 + string.len(display_text) * 6)
            },
            popup = {
                drawing = true
            }
        })
    else
        island_music:set({
            label = "No Music",
            icon = "♪"
        })
        
        -- Contract island when no music
        dynamic_island:set({
            background = {
                width = ISLAND_WIDTH
            },
            popup = {
                drawing = false
            }
        })
    end
end)

-- Dynamic Island interaction
dynamic_island:subscribe("mouse.clicked", function(env)
    dynamic_island:set({
        popup = {
            drawing = "toggle"
        }
    })
end)

dynamic_island:subscribe("mouse.exited", function(env)
    -- Auto-hide popup after a delay
    sbar.delay(3, function()
        dynamic_island:set({
            popup = {
                drawing = false
            }
        })
    end)
end)

-- Trigger initial update
sbar.trigger("media_change")