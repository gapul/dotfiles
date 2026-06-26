-- WezTerm 設定 (Ghostty config を移植)
-- 配置先:
--   Windows: %USERPROFILE%\.wezterm.lua    (bootstrap.ps1 で symlink)
--   macOS  : ~/.wezterm.lua                (Mac でも兼用したい場合は home.nix から symlink)
-- WezTerm は ~/.wezterm.lua > ~/.config/wezterm/wezterm.lua の順で探す。
--
-- 設計: Ghostty (macOS/Linux のみ) の代わりに Windows native のメインターミナルとして
-- 採用。クロスプラットフォームなので macOS/Linux でも同じ設定で起動可能。
-- 元 config: configs/terminals/ghostty/config

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local is_windows = wezterm.target_triple:find('windows') ~= nil
local is_macos = wezterm.target_triple:find('darwin') ~= nil

-- ─── Font (Ghostty: font-family = "HackGen Console NF") ───
config.font = wezterm.font 'HackGen Console NF'
config.font_size = 13.0

-- ─── Theme (Ghostty: theme = Rose Pine) ───
config.color_scheme = 'rose-pine'

-- ─── 閉じる確認なし (Ghostty: confirm-close-surface = false) ───
config.window_close_confirmation = 'NeverPrompt'

-- ─── 背景 (Ghostty: background-opacity = 0.88 / background-blur-radius = 30) ───
config.window_background_opacity = 0.88
if is_macos then
  config.macos_window_background_blur = 30
elseif is_windows then
  config.win32_system_backdrop = 'Acrylic'
end

-- ─── タイトルバー (Ghostty: macos-titlebar-style = hidden) ───
if is_macos then
  config.window_decorations = 'RESIZE'
end

-- ─── タブバー: 1 タブ時は非表示 ───
config.hide_tab_bar_if_only_one_tab = true

-- ─── キーバインド ───
-- Ghostty: cmd+c=copy_to_clipboard (Mac) — TUI 内で Ctrl+C が割り込みになる思想を踏襲。
-- Windows native: Ctrl+C は常に SIGINT、コピーは Ctrl+Shift+C。
config.keys = {
  { key = 'c', mods = 'CTRL',       action = wezterm.action.SendKey { key = 'c', mods = 'CTRL' } },
  { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.CopyTo 'Clipboard' },
}
if is_macos then
  table.insert(config.keys, { key = 'c', mods = 'CMD', action = wezterm.action.CopyTo 'Clipboard' })
end

-- ─── 未移植 (WezTerm に等価機能なし or OS 制約) ───
-- Ghostty: initial-window=false / quit-after-last-window-closed=false /
--          keybind=global:super+space=toggle_quick_terminal (Spotlight 代替)
-- → Quick Terminal 相当の global hotkey 機能は OS 側 (PowerToys / AutoHotkey 等) で対応

return config
