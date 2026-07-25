-- Keep mpv chrome in sync with the macOS light/dark appearance.
-- Video pixels are untouched; only the empty-window background and OSD change.
local utils = require("mp.utils")

local palettes = {
  dark = {
    background = "#191724",
    text = "#e0def4",
  },
  light = {
    background = "#faf4ed",
    text = "#575279",
  },
}

local current

local function appearance()
  local result = utils.subprocess({
    args = { "/usr/bin/defaults", "read", "-g", "AppleInterfaceStyle" },
    cancellable = false,
  })
  return result.status == 0 and result.stdout:match("Dark") and "dark" or "light"
end

local function apply()
  local mode = appearance()
  if mode == current then
    return
  end
  current = mode
  local palette = palettes[mode]
  mp.set_property("background-color", palette.background)
  mp.set_property("osd-color", palette.text)
  mp.set_property("osd-border-color", palette.background)
end

apply()
mp.add_periodic_timer(2, apply)
