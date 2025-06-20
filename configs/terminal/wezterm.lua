local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- カラースキーム設定
local function scheme_for_appearance(appearance)
  if appearance:find 'Dark' then
    return 'Catppuccin Mocha'
  else
    return 'Catppuccin Latte'
  end
end

-- フォント設定
config.font = wezterm.font_with_fallback {
  'HackGen Console NF',
  'SF Mono',
  'Menlo',
}
config.font_size = 14.0
config.line_height = 1.2
config.freetype_load_target = 'HorizontalLcd'

-- カラーテーマ（自動切り替え）
config.color_scheme = scheme_for_appearance(wezterm.gui.get_appearance())

-- フォント色とコントラストの調整
config.colors = {
  foreground = '#c9d1d9',
  background = '#0d1117',
  cursor_bg = '#58a6ff',
  cursor_fg = '#ffffff',
  cursor_border = '#58a6ff',
  selection_fg = '#ffffff',
  selection_bg = '#264f78',
  scrollbar_thumb = '#30363d',
  split = '#21262d',
  
  ansi = {
    '#484f58', -- black
    '#ff7b72', -- red
    '#7ee787', -- green
    '#f2cc60', -- yellow
    '#79c0ff', -- blue
    '#d2a8ff', -- magenta
    '#56d4dd', -- cyan
    '#e6edf3', -- white
  },
  brights = {
    '#6e7681', -- bright black
    '#ffa198', -- bright red
    '#56d364', -- bright green
    '#e3b341', -- bright yellow
    '#79c0ff', -- bright blue
    '#d2a8ff', -- bright magenta
    '#56d4dd', -- bright cyan
    '#f0f6fc', -- bright white
  },
}

-- 背景設定とビジュアル効果
config.window_background_opacity = 0.75
config.macos_window_background_blur = 30
config.window_background_gradient = {
  colors = { '#1a1b26', '#24283b', '#1a1b26' },
  orientation = { Radial = { cx = 0.75, cy = 0.75, radius = 1.25 } },
}

-- ウィンドウ設定
config.window_decorations = "RESIZE"
config.window_close_confirmation = "NeverPrompt"
config.initial_cols = 140
config.initial_rows = 35
config.window_padding = {
  left = 20,
  right = 20,
  top = 20,
  bottom = 20,
}

-- タブバー設定
config.enable_tab_bar = false

-- ペイン設定
config.inactive_pane_hsb = {
  saturation = 0.8,
  brightness = 0.6,
}

-- 拡張キーバインド設定
config.keys = {
  -- タブ管理
  {
    key = 't',
    mods = 'CMD',
    action = wezterm.action.SpawnTab 'CurrentPaneDomain',
  },
  {
    key = 'w',
    mods = 'CMD',
    action = wezterm.action.CloseCurrentTab { confirm = false },
  },
  {
    key = 'Tab',
    mods = 'CTRL',
    action = wezterm.action.ActivateTabRelative(1),
  },
  {
    key = 'Tab',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.ActivateTabRelative(-1),
  },
  
  -- ペイン分割と管理
  {
    key = 'd',
    mods = 'CMD',
    action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  {
    key = 'd',
    mods = 'CMD|SHIFT',
    action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  {
    key = 'x',
    mods = 'CMD',
    action = wezterm.action.CloseCurrentPane { confirm = false },
  },
  
  -- ペイン移動（矢印キー）
  {
    key = 'LeftArrow',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Left',
  },
  {
    key = 'RightArrow',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Right',
  },
  {
    key = 'UpArrow',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Up',
  },
  {
    key = 'DownArrow',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Down',
  },
  
  -- ペイン移動（hjkl）
  {
    key = 'h',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Left',
  },
  {
    key = 'l',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Right',
  },
  {
    key = 'k',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Up',
  },
  {
    key = 'j',
    mods = 'CMD|OPT',
    action = wezterm.action.ActivatePaneDirection 'Down',
  },
  
  -- ペインサイズ調整
  {
    key = 'LeftArrow',
    mods = 'CMD|CTRL',
    action = wezterm.action.AdjustPaneSize { 'Left', 5 },
  },
  {
    key = 'RightArrow',
    mods = 'CMD|CTRL',
    action = wezterm.action.AdjustPaneSize { 'Right', 5 },
  },
  {
    key = 'UpArrow',
    mods = 'CMD|CTRL',
    action = wezterm.action.AdjustPaneSize { 'Up', 3 },
  },
  {
    key = 'DownArrow',
    mods = 'CMD|CTRL',
    action = wezterm.action.AdjustPaneSize { 'Down', 3 },
  },
  
  -- フルスクリーン
  {
    key = 'Enter',
    mods = 'CMD|SHIFT',
    action = wezterm.action.ToggleFullScreen,
  },
  
  -- ワークスペース管理
  {
    key = 'n',
    mods = 'CMD|SHIFT',
    action = wezterm.action.SwitchWorkspaceRelative(1),
  },
  {
    key = 'p',
    mods = 'CMD|SHIFT',
    action = wezterm.action.SwitchWorkspaceRelative(-1),
  },
  {
    key = 'w',
    mods = 'CMD|SHIFT',
    action = wezterm.action.ShowLauncherArgs {
      flags = 'FUZZY|WORKSPACES',
    },
  },
  
  -- その他便利機能
  {
    key = 'r',
    mods = 'CMD|SHIFT',
    action = wezterm.action.ReloadConfiguration,
  },
  {
    key = 'u',
    mods = 'CMD|SHIFT',
    action = wezterm.action.CharSelect {
      copy_on_select = true,
      copy_to = 'ClipboardAndPrimarySelection',
    },
  },
}

-- マウス設定
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CMD',
    action = wezterm.action.OpenLinkAtMouseCursor,
  },
  {
    event = { Down = { streak = 3, button = 'Left' } },
    action = wezterm.action.SelectTextAtMouseCursor 'Line',
  },
  {
    event = { Down = { streak = 1, button = 'Middle' } },
    action = wezterm.action.PasteFrom 'PrimarySelection',
  },
}

-- ワークスペース設定
config.default_workspace = "main"

-- 起動設定
config.default_prog = { '/bin/zsh', '-l' }

-- その他の高度な設定
config.scrollback_lines = 50000
config.enable_scroll_bar = false
config.check_for_updates = false
config.show_update_window = false
config.use_ime = true
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = true

-- パフォーマンス設定
config.max_fps = 60
config.animation_fps = 60
config.cursor_blink_rate = 800

-- ベルの設定 (Claude Code通知対応)
config.audible_bell = "SystemBeep"
config.visual_bell = {
  fade_in_function = 'EaseIn',
  fade_in_duration_ms = 150,
  fade_out_function = 'EaseOut',
  fade_out_duration_ms = 150,
}

-- 通知設定
config.notification_handling = "AlwaysShow"

-- コマンド完了通知 (bellイベントをトースト通知に変換)
wezterm.on('bell', function(window, pane)
  wezterm.log_info('Bell received - showing notification')
  window:toast_notification('WezTerm Notification', 'Command execution completed', nil, 4000)
end)

-- OSC 9 escape sequence handler for custom notifications
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name == 'notification' then
    window:toast_notification('Command Status', value, nil, 4000)
  end
end)

-- 起動時のイベント処理
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

-- ウィンドウタイトル設定
wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local zoomed = ''
  if tab.active_pane.is_zoomed then
    zoomed = '[Z] '
  end

  local index = ''
  if #tabs > 1 then
    index = string.format('[%d/%d] ', tab.tab_index + 1, #tabs)
  end

  return zoomed .. index .. tab.active_pane.title
end)

return config