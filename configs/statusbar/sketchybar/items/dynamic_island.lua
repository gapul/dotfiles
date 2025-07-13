-- Dynamic Island for SketchyBar
-- Simplified iPhone 14 Pro style dynamic island

local colors = require("colors")
local settings = require("settings")

-- Create dynamic island - simple black rounded rectangle
local dynamic_island = sbar.add("item", "dynamic_island", {
    position = "center",
    icon = {
        string = "●",
        color = 0xffffffff,
        font = {
            family = settings.font.text,
            size = 12.0
        }
    },
    label = {
        string = "",
        color = 0xffffffff,
        font = {
            family = settings.font.text,
            size = 10.0
        }
    },
    background = {
        color = 0xff000000,
        corner_radius = 15,
        height = 30,
        width = 60,
        border_width = 1,
        border_color = 0x44ffffff
    },
    padding_left = 4,
    padding_right = 4
})

-- Simple click interaction
dynamic_island:subscribe("mouse.clicked", function(env)
    dynamic_island:set({
        background = {
            width = 120
        },
        label = {
            string = "Dynamic Island"
        }
    })
    
    -- Reset after 2 seconds
    sbar.delay(2, function()
        dynamic_island:set({
            background = {
                width = 60
            },
            label = {
                string = ""
            }
        })
    end)
end)