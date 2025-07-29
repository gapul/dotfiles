-- WezTerm Configuration - Poimandres Theme (falleco/dotfiles inspired)
-- Enhanced terminal experience with modern styling and transparency
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Poimandres Color Scheme
local poimandres = {
  foreground = '#a6accd',
  background = '#1b1e28',
  cursor_bg = '#5de4c7',
  cursor_fg = '#1b1e28',
  cursor_border = '#5de4c7',
  selection_fg = '#a6accd',
  selection_bg = '#303340',
  scrollbar_thumb = '#505168',
  split = '#303340',
  
  ansi = {
    '#1b1e28', -- black
    '#d0679d', -- red
    '#5de4c7', -- green  
    '#fffac2', -- yellow
    '#89ddff', -- blue
    '#fcc5e9', -- magenta
    '#add7ff', -- cyan
    '#a6accd', -- white
  },
  brights = {
    '#767c9d', -- bright black
    '#d0679d', -- bright red
    '#5de4c7', -- bright green
    '#fffac2', -- bright yellow
    '#add7ff', -- bright blue
    '#fcc5e9', -- bright magenta
    '#89ddff', -- bright cyan
    '#ffffff', -- bright white
  },
}

-- Font Configuration
config.font = wezterm.font_with_fallback {
  { family = 'SF Mono', weight = 'Medium' },
  { family = 'JetBrains Mono', weight = 'Medium' },
  { family = 'FiraCode Nerd Font', weight = 'Medium' },
  'Menlo',
}
config.font_size = 13.0
config.line_height = 1.25
config.cell_width = 1.0
config.freetype_load_target = 'HorizontalLcd'
config.freetype_render_target = 'HorizontalLcd'

-- Color Configuration
config.colors = poimandres

-- Window Appearance 
config.window_background_opacity = 0.85
config.macos_window_background_blur = 40
config.text_background_opacity = 1.0
config.window_decorations = "RESIZE"
config.window_close_confirmation = "NeverPrompt"
config.native_macos_fullscreen_mode = false

-- Window Size & Padding
config.initial_cols = 120
config.initial_rows = 30
config.window_padding = {
  left = 16,
  right = 16,
  top = 16,
  bottom = 16,
}

-- Tab Bar Configuration
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = true
config.tab_max_width = 32

-- Tab Bar Colors
config.colors.tab_bar = {
  background = '#1b1e28',
  active_tab = {
    bg_color = '#303340',
    fg_color = '#a6accd',
    intensity = 'Bold',
  },
  inactive_tab = {
    bg_color = '#1b1e28',
    fg_color = '#767c9d',
  },
  inactive_tab_hover = {
    bg_color = '#303340',
    fg_color = '#a6accd',
  },
  new_tab = {
    bg_color = '#1b1e28',
    fg_color = '#767c9d',
  },
  new_tab_hover = {
    bg_color = '#303340',
    fg_color = '#a6accd',
  },
}

-- Pane Configuration
config.inactive_pane_hsb = {
  saturation = 0.7,
  brightness = 0.6,
}

-- Enhanced Key Bindings (falleco-inspired)
config.keys = {
  -- Tab management
  { key = 't', mods = 'CMD', action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CMD', action = wezterm.action.CloseCurrentTab { confirm = false } },
  { key = 'Tab', mods = 'CTRL', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'Tab', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },
  
  -- Numbered tab selection
  { key = '1', mods = 'CMD', action = wezterm.action.ActivateTab(0) },
  { key = '2', mods = 'CMD', action = wezterm.action.ActivateTab(1) },
  { key = '3', mods = 'CMD', action = wezterm.action.ActivateTab(2) },
  { key = '4', mods = 'CMD', action = wezterm.action.ActivateTab(3) },
  { key = '5', mods = 'CMD', action = wezterm.action.ActivateTab(4) },
  { key = '6', mods = 'CMD', action = wezterm.action.ActivateTab(5) },
  { key = '7', mods = 'CMD', action = wezterm.action.ActivateTab(6) },
  { key = '8', mods = 'CMD', action = wezterm.action.ActivateTab(7) },
  { key = '9', mods = 'CMD', action = wezterm.action.ActivateTab(-1) },
  
  -- Pane splitting
  { key = 'd', mods = 'CMD', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'd', mods = 'CMD|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'x', mods = 'CMD', action = wezterm.action.CloseCurrentPane { confirm = false } },
  
  -- Pane navigation (Vi-style)
  { key = 'h', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Right' },
  
  -- Pane navigation (Arrow keys)
  { key = 'LeftArrow', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'DownArrow', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'UpArrow', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'RightArrow', mods = 'CMD|OPT', action = wezterm.action.ActivatePaneDirection 'Right' },
  
  -- Pane resizing
  { key = 'LeftArrow', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Left', 3 } },
  { key = 'RightArrow', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Right', 3 } },
  { key = 'UpArrow', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Up', 3 } },
  { key = 'DownArrow', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Down', 3 } },
  
  -- Zoom pane
  { key = 'z', mods = 'CMD', action = wezterm.action.TogglePaneZoomState },
  
  -- Search mode
  { key = 'f', mods = 'CMD', action = wezterm.action.Search { CaseSensitiveString = '' } },
  
  -- Copy mode
  { key = '[', mods = 'CMD', action = wezterm.action.ActivateCopyMode },
  
  -- Font size adjustment
  { key = '=', mods = 'CMD', action = wezterm.action.IncreaseFontSize },
  { key = '-', mods = 'CMD', action = wezterm.action.DecreaseFontSize },
  { key = '0', mods = 'CMD', action = wezterm.action.ResetFontSize },
  
  -- Fullscreen
  { key = 'Enter', mods = 'CMD|SHIFT', action = wezterm.action.ToggleFullScreen },
  
  -- Workspace management
  { key = 'n', mods = 'CMD|SHIFT', action = wezterm.action.SwitchWorkspaceRelative(1) },
  { key = 'p', mods = 'CMD|SHIFT', action = wezterm.action.SwitchWorkspaceRelative(-1) },
  { key = 'w', mods = 'CMD|SHIFT', action = wezterm.action.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' } },
  
  -- Quick utilities
  { key = 'r', mods = 'CMD|SHIFT', action = wezterm.action.ReloadConfiguration },
  { key = 'u', mods = 'CMD|SHIFT', action = wezterm.action.CharSelect { copy_on_select = true, copy_to = 'ClipboardAndPrimarySelection' } },
  
  -- Debug overlay
  { key = 'l', mods = 'CMD|SHIFT', action = wezterm.action.ShowDebugOverlay },
}

-- Mouse Configuration
config.mouse_bindings = {
  -- Click to open links
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CMD',
    action = wezterm.action.OpenLinkAtMouseCursor,
  },
  -- Triple-click to select line
  {
    event = { Down = { streak = 3, button = 'Left' } },
    action = wezterm.action.SelectTextAtMouseCursor 'Line',
  },
  -- Middle click to paste
  {
    event = { Down = { streak = 1, button = 'Middle' } },
    action = wezterm.action.PasteFrom 'PrimarySelection',
  },
  -- Right click to paste (falleco-style)
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = wezterm.action.PasteFrom 'Clipboard',
  },
}

-- Performance Configuration
config.max_fps = 120
config.animation_fps = 60
config.cursor_blink_rate = 700
config.scrollback_lines = 10000
config.enable_scroll_bar = false

-- System Integration
config.check_for_updates = false
config.show_update_window = false
config.use_ime = true
config.macos_forward_to_ime_modifier_mask = 'SHIFT|CTRL'
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Bell and Notifications
config.audible_bell = 'Disabled'
config.visual_bell = {
  fade_in_function = 'EaseIn',
  fade_in_duration_ms = 100,
  fade_out_function = 'EaseOut',
  fade_out_duration_ms = 100,
}

-- Workspace Configuration
config.default_workspace = 'main'
config.default_prog = { '/bin/zsh', '-l' }

-- URL handling
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- Event Handlers
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():set_position(100, 100)
end)

wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local zoomed = tab.active_pane.is_zoomed and ' [ZOOM]' or ''
  local workspace = tab.window.active_workspace ~= 'default' and (' [' .. tab.window.active_workspace .. ']') or ''
  return tab.active_pane.title .. zoomed .. workspace
end)

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane
  local title = pane.title
  
  if #title > 20 then
    title = title:sub(1, 17) .. '...'
  end
  
  local index = tab.tab_index + 1
  return {
    { Text = ' ' .. index .. ': ' .. title .. ' ' },
  }
end)

-- Custom notification support
wezterm.on('bell', function(window, pane)
  window:toast_notification('WezTerm', 'Command completed', nil, 3000)
end)

wezterm.on('user-var-changed', function(window, pane, name, value)
  if name == 'notification' then
    window:toast_notification('Terminal Notification', value, nil, 4000)
  end
end)

return config