# Darwin chrome component (ECS: profile). Theme-dependent WM/bar/borders/sioyek/Obsidian.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  c = import ../../lib/theme.nix; # active theme palette (switch via active in nix/lib/theme.nix)
  rgb = import ../../lib/hex-rgb.nix { inherit lib; }; # hex → "r g b" 0-1 float (for sioyek)

  # Generate sketchybar colors.sh "palette-dependent exports" from palette p.
  # Embed both dark/light in colors.sh and branch on AppleInterfaceStyle to follow the OS.
  sbHex = p: ''
    # Faithfully map rose-pine role colors to sketchybar semantics.
    # (rose-pine has no pure green/orange, so success=foam / warm=rose)
    export BLACK=0xff${p.base}    # background (darkest/lightest)
    export WHITE=0xff${p.text}    # foreground / text
    export RED=0xff${p.love}      # error / critical
    export GREEN=0xff${p.foam}    # success / active (rose-pine positive)
    export BLUE=0xff${p.pine}     # info
    export YELLOW=0xff${p.gold}   # warning
    export ORANGE=0xff${p.rose}   # warm accent
    export MAGENTA=0xff${p.iris}  # primary accent (rose-pine signature)
    export GREY=0xff${p.muted}    # inactive / subtle
    export ACCENT=0xff${p.iris}   # accent for active elements
    # background pill: surface=opaque / overlay,hlMed raised to 0xcc so it stays visible even in light
    # The actually-visible bar background is the bracket pill = BG1. The bar itself is fully transparent in sketchybarrc.
    # alpha 0x99 (≈60%) on BG1/BG2 makes the pill translucent so the wallpaper shows through.
    export BG0=0xff${p.surface}
    export BG1=0x99${p.overlay}
    export BG2=0x99${p.hlMed}
    export BATTERY_1=0xff${p.foam}
    export BATTERY_2=0xff${p.gold}
    export BATTERY_3=0xff${p.rose}
    export BATTERY_4=0xff${p.love}
    export BATTERY_5=0xff${p.love}'';

  # Obsidian: map the theme.nix palette to CSS variables. To match Obsidian appearance = "system" (follows OS),
  # generate both .theme-dark / .theme-light (same idea as the sketchybar dark/light dual embed).
  obsidianVars = p: ''
    --background-primary:         #${p.base};
    --background-primary-alt:     #${p.surface};
    --background-secondary:       #${p.surface};
    --background-secondary-alt:   #${p.overlay};
    --text-normal:                #${p.text};
    --text-muted:                 #${p.subtle};
    --text-faint:                 #${p.muted};
    --text-accent:                #${p.iris};
    --text-accent-hover:          #${p.rose};
    --interactive-accent:         #${p.iris};
    --interactive-accent-hover:   #${p.rose};
    --background-modifier-border: #${p.hlMed};
    /* UI chrome (titlebar/ribbon/tab/status bar/nav/scrollbar) */
    --titlebar-background:         #${p.overlay};
    --titlebar-background-focused: #${p.overlay};
    --titlebar-text-color:         #${p.text};
    --ribbon-background:           #${p.overlay};
    --tab-container-background:     #${p.overlay};
    --tab-background-active:        #${p.hlMed};
    --tab-text-color-focused-active-current: #${p.text};
    --status-bar-background:        #${p.surface};
    --status-bar-text-color:        #${p.subtle};
    --divider-color:                #${p.hlMed};
    --scrollbar-thumb-bg:           #${p.hlMed};
    --scrollbar-active-thumb-bg:    #${p.muted};
    --nav-item-background-active:   #${p.overlay};'';
  # translucency: only when ON (.is-translucent), add alpha to the background so macOS vibrancy shows through.
  # alpha is the AA (hex) of #RRGGBBAA: cc≈80% / b3≈70% / 99≈60% / 80≈50%. Smaller = more transparent.
  translucentAlpha = "b3"; # body / sidebar (frosted translucency ≈70% that pairs well with vibrancy)
  chromeAlpha = "99"; # outer edges (titlebar/tab/ribbon) made a bit more transparent (≈60%)
  obsidianTranslucent = p: ''
    --background-primary:          #${p.base}${translucentAlpha};
    --background-primary-alt:      #${p.surface}${translucentAlpha};
    --background-secondary:        #${p.surface}${translucentAlpha};
    --background-secondary-alt:    #${p.overlay}${translucentAlpha};
    --titlebar-background:         #${p.overlay}${chromeAlpha};
    --titlebar-background-focused: #${p.overlay}${chromeAlpha};
    --ribbon-background:           #${p.overlay}${chromeAlpha};
    --tab-container-background:    #${p.overlay}${chromeAlpha};
    --status-bar-background:       #${p.surface}${translucentAlpha};'';
  # Obsidian only "reads" the snippet, so Nix ownership (generated) doesn't conflict with editing/sync.
  obsidianThemeCss = pkgs.writeText "nix-theme.css" ''
    /* ============================================================
       AUTO-GENERATED from nix/lib/theme.nix — do not edit by hand.
       To change theme, edit active in nix/lib/theme.nix and run `just rebuild`.
       ============================================================ */
    .theme-dark {
    ${obsidianVars c.dark}
    }
    .theme-light {
    ${obsidianVars c.light}
    }
    /* translucency (applies only when Settings→Appearance→Translucent is ON) */
    .theme-dark.is-translucent {
    ${obsidianTranslucent c.dark}
    }
    .theme-light.is-translucent {
    ${obsidianTranslucent c.light}
    }
    /* force tab/titlebar band to follow theme (guards against Minimal's black override, for when variables can't win) */
    .workspace-tab-header-container,
    .workspace-tabs .workspace-tab-header-container-inner,
    .titlebar,
    .workspace-ribbon.mod-left {
      background-color: var(--titlebar-background) !important;
    }
    /* typography: keep the font itself, fine-tune line height/margins/smoothing */
    body { -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
    .markdown-preview-view,
    .markdown-source-view.mod-cm6 .cm-content {
      --line-height-normal: 1.75;
      --p-spacing: 0.85em;
    }
    .markdown-rendered h1,
    .markdown-rendered h2,
    .markdown-rendered h3 { line-height: 1.3; }
  '';
in
{
  # aerospace: resolution-variable gaps/padding. config include is unsupported + nix symlink is read-only, so
  # generate ~/.config/aerospace/aerospace.toml via activation instead of a symlink.
  # scale gaps/accordion-padding from main display resolution → dry-run check → reload-config.
  # @DOTFILES@ in source expands to the current $HOME/.dotfiles at generation time.
  home.activation.aerospaceConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/bash ${../../../scripts/aerospace-config.sh} ${../../../configs/wm/aerospace/aerospace.toml}
  '';
  home.file.".config/sketchybar" = {
    source = ../../../configs/wm/sketchybar;
    recursive = true;
  };
  # sketchybar colors are generated from nix/lib/theme.nix (static colors.sh retired).
  # Other sketchybar scripts source this via $WHITE etc. as before.
  home.file.".config/sketchybar/colors.sh".text = ''
    #!/bin/bash
    # Rosé Pine — auto-select dark/light by macOS appearance (AppleInterfaceStyle).
    # Colors come from the dark/light palette in nix/lib/theme.nix (single source).
    # On appearance change, the theme-watch agent runs `sketchybar --reload` and this is re-evaluated.
    if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
    ${sbHex c.dark}
    else
    ${sbHex c.light}
    fi
    export TRANSPARENT=0x00000000

    # General bar colors (palette-independent, derived from the exports above)
    export BAR_COLOR=$BG0
    export BAR_BORDER_COLOR=$BG2
    export BACKGROUND_1=$BG1
    export BACKGROUND_2=$BG2
    export ICON_COLOR=$WHITE
    export LABEL_COLOR=$WHITE
    export POPUP_BACKGROUND_COLOR=$BAR_COLOR
    export POPUP_BORDER_COLOR=$WHITE
    export SHADOW_COLOR=$BLACK
  '';
  # borders is launched from AeroSpace via bare `borders` and runs bordersrc.
  # Without executable=true, borders can't run (single source of config).
  # Colors come from theme.nix dark/light. Branch active/inactive on macOS appearance to follow the OS.
  # On appearance change, the theme-watch agent re-runs bordersrc and it reflects into the running borders daemon.
  home.file.".config/borders/bordersrc" = {
    executable = true;
    text = ''
      #!/bin/bash
      # JankyBorders config = single source for the active window border. Colors come from the Rosé Pine palette.
      if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
        active=0xff${c.dark.iris}
        inactive=0xff${c.dark.muted}
      else
        active=0xff${c.light.iris}
        inactive=0xff${c.light.muted}
      fi
      options=(
        active_color=$active
        inactive_color=$inactive
        width=4.0
      )
      borders "''${options[@]}"
    '';
  };

  # theme-watch: watch for macOS appearance (light/dark) changes and re-apply shell-side chrome.
  # sketchybar/borders branch on AppleInterfaceStyle inside colors.sh/bordersrc,
  # so just reload/re-run on change to follow the OS. Polling approach, no external binary needed.
  home.file.".config/theme/theme-watch.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      # watch macOS appearance changes → sketchybar reload + borders re-apply (follows theme.nix category B)
      export PATH="/opt/homebrew/bin:$PATH"
      last=""
      while true; do
        cur="$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"
        if [ "$cur" != "$last" ]; then
          last="$cur"
          [ -x "$HOME/.config/borders/bordersrc" ] && "$HOME/.config/borders/bordersrc" >/dev/null 2>&1 &
          sketchybar --reload >/dev/null 2>&1
        fi
        sleep 2
      done
    '';
  };

  # Launch the watcher above as a resident launchd agent (at login + liveness monitoring).
  launchd.agents.theme-watch = {
    enable = true;
    config = {
      ProgramArguments = [ "${config.home.homeDirectory}/.config/theme/theme-watch.sh" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/theme-watch.err";
      StandardOutPath = "/tmp/theme-watch.out";
    };
  };

  # Resident watcher that recomputes the sketchybar display map (aerospace monitor -> sketchybar display index)
  # on display config changes and writes it to /tmp/sketchybar-aero-display.map.
  # Without it, the map is lost on restart and space.* breaks (needs a manual sketchybar-refresh).
  # Used to be a manual plist but broke due to hardcoded /Users/<old name>, so migrated to nix declaration.
  launchd.agents.sketchybar-displaywatch = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/.config/sketchybar/helpers/display_watch.sh"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      ThrottleInterval = 10;
      StandardErrorPath = "/tmp/sketchybar-displaywatch.err";
      StandardOutPath = "/tmp/sketchybar-displaywatch.log";
    };
  };

  # sioyek: colors are generated from nix/lib/theme.nix (hex→0-1 float via lib/hex-rgb.nix).
  # sioyek on macOS uses ~/Library/Application Support/sioyek/ as its config dir
  # (no XDG). prefs_user.config is the user override. sioyek itself writes auto.config/
  # db to the same dir, but prefs_user.config is read-only, so a store symlink is fine.
  home.file."Library/Application Support/sioyek/prefs_user.config".text = ''
    # Rosé Pine — generated from nix/lib/theme.nix
    # UI chrome
    background_color ${rgb c.base}
    status_bar_color ${rgb c.surface}
    status_bar_text_color ${rgb c.text}
    # blend page boundaries into the gutter (base)
    page_separator_width 2
    page_separator_color ${rgb c.hlMed}
    # highlights
    text_highlight_color ${rgb c.gold}
    search_highlight_color ${rgb c.love}
    link_highlight_color ${rgb c.foam}
    synctex_highlight_color ${rgb c.pine}
    visual_mark_color ${rgb c.iris} 0.3
    # custom color mode (page color for dark reading) / dark mode
    custom_background_color ${rgb c.base}
    custom_text_color ${rgb c.text}
    dark_mode_background_color ${rgb c.base}
    dark_mode_contrast 0.85
  '';

  # sioyek keybind override: assign custom color mode (read on a rose-pine background) to F7.
  # Distinct from F8=standard dark inversion (toggle_custom_color is unassigned by default).
  home.file."Library/Application Support/sioyek/keys_user.config".text = ''
    # Toggle Rosé Pine custom color mode with F7
    toggle_custom_color <f7>
  '';

  # Obsidian: place the theme.nix-derived color snippet in the vault (follows theme switches).
  # - The vault is the source of truth. Only this one generated snippet is Nix-owned (other .obsidian is untouched).
  # - Real copy, not symlink → propagates to phone via LiveSync/git. Overwritten each time to reflect changes.
  # - First time only, enable "Settings→Appearance→CSS snippets→nix-theme" in Obsidian (kept via sync afterward).
  home.activation.obsidianTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    obsidian_dir="${config.home.homeDirectory}/Documents/notes/.obsidian"
    if [ -d "$obsidian_dir" ]; then
      /bin/mkdir -p "$obsidian_dir/snippets"
      # Files Obsidian has opened get com.apple.macl (TCC), so without FDA
      #   install's rename fails with EPERM from activation. The vault is the source of truth for the snippet
      #   (propagated via LiveSync), so if it can't update, just warn and don't stop the whole switch.
      if ! /usr/bin/install -m 644 ${obsidianThemeCss} "$obsidian_dir/snippets/nix-theme.css" 2>/dev/null; then
        echo "warning: obsidianTheme: failed to update nix-theme.css (possibly an Obsidian TCC lock). The vault is the source of truth, so skipping." >&2
      fi
    fi
  '';
}
