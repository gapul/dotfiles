local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

local spaces = {}

-- Create event for Aerospace workspace changes
sbar.exec("sketchybar --add event aerospace_workspace_change")

-- Define workspaces 1-8 for Aerospace
local aerospace_workspaces = {"1", "2", "3", "4", "5", "6", "7", "8"}

for i, workspace_id in ipairs(aerospace_workspaces) do
  local space = sbar.add("item", "space." .. workspace_id, {
    icon = {
      font = { family = settings.font.numbers },
      string = workspace_id,
      padding_left = 12,
      padding_right = 6,
      color = colors.white,
      highlight_color = colors.red,
    },
    label = {
      padding_right = 16,
      color = colors.grey,
      highlight_color = colors.white,
      font = "sketchybar-app-font:Regular:14.0",
      y_offset = -1,
    },
    padding_right = 1,
    padding_left = 1,
    background = {
      color = colors.bg1,
      border_width = 1,
      height = 24,
      border_color = colors.transparent,
    },
    popup = { background = { border_width = 5, border_color = colors.black } }
  })

  spaces[workspace_id] = space

  -- Single item bracket for space items to achieve highlight effect
  local space_bracket = sbar.add("bracket", { space.name }, {
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 26,
      border_width = 1
    }
  })

  -- Padding space for better visual separation
  sbar.add("item", "space.padding." .. workspace_id, {
    script = "",
    width = 2,
  })

  local space_popup = sbar.add("item", {
    position = "popup." .. space.name,
    padding_left= 5,
    padding_right= 0,
    background = {
      drawing = true,
      image = {
        corner_radius = 9,
        scale = 0.2
      }
    }
  })

  -- Handle space change events (both traditional and aerospace)
  space:subscribe("space_change", function(env)
    local selected = env.SELECTED == "true"
    space:set({
      icon = { highlight = selected, },
      label = { highlight = selected },
      background = { border_color = selected and colors.blue or colors.transparent }
    })
    space_bracket:set({
      background = { border_color = selected and colors.blue or colors.bg2 }
    })
  end)

  -- Handle aerospace workspace changes
  space:subscribe("aerospace_workspace_change", function(env)
    local focused_workspace = env.AEROSPACE_FOCUSED_WORKSPACE or "1"
    local selected = workspace_id == focused_workspace
    
    space:set({
      icon = { highlight = selected, },
      label = { highlight = selected },
      background = { border_color = selected and colors.blue or colors.transparent }
    })
    space_bracket:set({
      background = { border_color = selected and colors.blue or colors.bg2 }
    })
  end)

  -- Aerospace-specific mouse click handling
  space:subscribe("mouse.clicked", function(env)
    if env.BUTTON == "right" then
      -- Right click: close all windows in workspace
      sbar.exec("aerospace close-all-windows-but-current")
    else
      -- Left click: switch to workspace
      sbar.exec("aerospace workspace " .. workspace_id)
      sbar.trigger("aerospace_workspace_change", { AEROSPACE_FOCUSED_WORKSPACE = workspace_id })
    end
  end)

  space:subscribe("mouse.exited", function(_)
    space:set({ popup = { drawing = false } })
  end)
end

-- Window observer for updating workspace app icons
local space_window_observer = sbar.add("item", {
  drawing = false,
  updates = true,
})

-- Update workspace with app icons when windows change
local function update_workspace_apps(workspace_id)
  if not spaces[workspace_id] then return end
  
  local icon_line = ""
  local no_app = true
  
  -- Get apps in workspace using Aerospace
  local cmd = "aerospace list-windows --workspace " .. workspace_id .. " 2>/dev/null"
  local handle = io.popen(cmd)
  if handle then
    local result = handle:read("*a")
    handle:close()
    
    if result and result ~= "" then
      local apps = {}
      for line in result:gmatch("[^\r\n]+") do
        -- Parse aerospace list-windows output: window-id | app-name | window-title
        local app_name = line:match("|%s*([^|]+)%s*|")
        if app_name then
          app_name = app_name:gsub("^%s*(.-)%s*$", "%1") -- trim
          if app_name ~= "" and app_name ~= "AeroSpace" then
            apps[app_name] = (apps[app_name] or 0) + 1
            no_app = false
          end
        end
      end
      
      local app_list = {}
      for app, count in pairs(apps) do
        table.insert(app_list, app)
      end
      
      for i, app in ipairs(app_list) do
        local lookup = app_icons[app]
        local icon = ((lookup == nil) and app_icons["Default"] or lookup)
        if i > 1 then
          icon_line = icon_line .. " " .. icon
        else
          icon_line = icon_line .. icon
        end
      end
    end
  end

  if no_app then
    icon_line = ""
  end
  
  sbar.animate("tanh", 10, function()
    spaces[workspace_id]:set({ label = icon_line })
  end)
end

-- Subscribe to window changes for all workspaces
space_window_observer:subscribe("space_windows_change", function(env)
  -- Get current focused workspace
  local handle = io.popen("aerospace list-workspaces --focused 2>/dev/null")
  local focused_workspace = "1"
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and result ~= "" then
      focused_workspace = result:gsub("^%s*(.-)%s*$", "%1")
    end
  end
  
  -- Trigger aerospace workspace change to update visibility
  sbar.trigger("aerospace_workspace_change", { AEROSPACE_FOCUSED_WORKSPACE = focused_workspace })
end)

-- Subscribe to aerospace workspace changes
space_window_observer:subscribe("aerospace_workspace_change", function(env)
  local focused_workspace = env.AEROSPACE_FOCUSED_WORKSPACE or "1"
  
  -- Get list of workspaces that have windows
  local active_workspaces = {}
  for _, workspace_id in ipairs(aerospace_workspaces) do
    local cmd = "aerospace list-windows --workspace " .. workspace_id .. " 2>/dev/null"
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and result ~= "" then
        active_workspaces[workspace_id] = true
      end
    end
  end
  
  -- Always show the focused workspace even if it has no windows
  active_workspaces[focused_workspace] = true
  
  -- Update workspace visibility and highlights
  for workspace_id, space in pairs(spaces) do
    local selected = workspace_id == focused_workspace
    local is_active = active_workspaces[workspace_id] or false
    
    space:set({
      drawing = is_active,
      icon = { highlight = selected },
      label = { highlight = selected },
      background = { border_color = selected and colors.blue or colors.transparent }
    })
    
    -- Update the focused workspace apps
    if selected then
      update_workspace_apps(workspace_id)
    end
  end
end)

-- Menu indicator (renamed from spaces indicator)
local menu_indicator = sbar.add("item", "menu_indicator", {
  padding_left = 1,
  padding_right = 1,
  icon = {
    padding_left = 6,
    padding_right = 6,
    color = colors.grey,
    string = icons.switch.on,
  },
  label = {
    width = 0,
    padding_left = 0,
    padding_right = 6,
    string = "Menu",
    color = colors.bg1,
  },
  background = {
    color = colors.with_alpha(colors.grey, 0.0),
    border_color = colors.with_alpha(colors.bg1, 0.0),
  }
})

-- Initial update of all workspaces
sbar.exec("sleep 1 && sketchybar --trigger space_windows_change")
sbar.exec("sleep 1 && sketchybar --trigger aerospace_workspace_change AEROSPACE_FOCUSED_WORKSPACE=1")

-- Menu indicator interactions
menu_indicator:subscribe("mouse.entered", function(env)
  sbar.animate("tanh", 30, function()
    menu_indicator:set({
      background = {
        color = { alpha = 1.0 },
        border_color = { alpha = 1.0 },
      },
      icon = { color = colors.bg1 },
      label = { width = "dynamic" }
    })
  end)
end)

menu_indicator:subscribe("mouse.exited", function(env)
  sbar.animate("tanh", 30, function()
    menu_indicator:set({
      background = {
        color = { alpha = 0.0 },
        border_color = { alpha = 0.0 },
      },
      icon = { color = colors.grey },
      label = { width = 0, }
    })
  end)
end)

-- Menu toggle functionality (swap between spaces and menus)
menu_indicator:subscribe("mouse.clicked", function(env)
  sbar.trigger("swap_menus_and_spaces")
end)
