# ★★★ To switch the unified theme, just change "active" in configs/theme/palettes.json ★★★
#
#   Candidates:
#     "rose-pine"      … dark  (main)
#     "rose-pine-dawn" … light (dawn)
#
#   After changing it:
#     - Mac/Linux: `just rebuild` makes all nix-managed tools (zellij/sketchybar/borders/
#       lazygit/fzf/sioyek/atuin/bat/delta/ghostty/nvim …) follow at once
#     - Windows : `just win-theme` makes zebar/glazewm/WT/wezterm follow at once
#   Using palettes.json as the SSO means the same active is shared across
#   Mac/Linux/WSL/Windows (previously active was double-defined in theme.nix and palettes.json).
#
# The colors themselves are stored as palettes."<name>" in configs/theme/palettes.json.
let
  data = builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json);
  inherit (data) active palettes;
  # The dark/light pair used for OS-appearance following. Pinned, not derived from active:
  # palettes.json holds exactly one family, so there is nothing to derive from yet.
  # ADDING A SECOND FAMILY: these two lines do not follow active. Setting active to, say,
  # "catppuccin" would switch the flat colors while every appearance-following consumer
  # (sketchybar colors.sh, bordersrc, Obsidian's nix-theme.css, ghostty) stayed on rose-pine.
  # Give palettes.json a per-family dark/light map at that point and read it here.
  dark = palettes."rose-pine";
  light = palettes."rose-pine-dawn";
in
# Expand the active palette at top-level (keeping existing c.base etc.), while also
# making both dark/light referenceable via c.dark / c.light (used to generate macOS appearance following).
palettes.${active} // { inherit dark light active; }
