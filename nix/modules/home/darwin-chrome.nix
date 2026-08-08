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

  # JankyBorders config = single source for the active window border. Colors come from the Rosé Pine palette.
  # Also the agent's Program: running it a second time while the daemon is up acts as a client and
  # restyles the running instance, which is what theme-watch does on an appearance change.
  # launchd starts with a bare PATH, so resolve the brew-installed borders explicitly.
  bordersrc = pkgs.writeShellScript "bordersrc" ''
    export PATH="/opt/homebrew/bin:$PATH"
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

  # Watch macOS appearance (light/dark) changes and re-apply shell-side chrome. sketchybar/borders
  # branch on AppleInterfaceStyle inside colors.sh/bordersrc, so re-running them is enough to follow
  # the OS. Polling, so no extra binary is needed.
  # tmux is on the nix profile PATH; include it so the tmux re-source below is found.
  themeWatch = pkgs.writeShellScript "theme-watch" ''
    export PATH="/opt/homebrew/bin:$HOME/.local/state/nix/profile/bin:$PATH"
    last=""
    while true; do
      cur="$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"
      if [ "$cur" != "$last" ]; then
        last="$cur"
        ${bordersrc} >/dev/null 2>&1 &
        sketchybar --reload >/dev/null 2>&1
        # tmux: re-source theme.conf so the running server re-picks rose-pine / rose-pine-dawn
        # by the new appearance. No-op if no tmux server is running.
        command -v tmux >/dev/null 2>&1 && tmux source-file "$HOME/.config/tmux/theme.conf" >/dev/null 2>&1
      fi
      sleep 2
    done
  '';
in
{
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
  # borders / theme-watch live in the store (bordersrc, themeWatch in the let block above) and the
  # agents exec the store path, so the running daemon belongs to a generation: a rollback takes the
  # watcher with it, and a half-saved edit can't take out the agent at the next login.
  # The ~/.config copies stay for manual invocation — same derivation, so they can't drift.
  # (The sketchybar helpers deliberately stay out of the store: the whole config dir is an
  #  mkOutOfStoreSymlink into the checkout because the bar is tuned live.)
  home.file.".config/borders/bordersrc".source = bordersrc;
  home.file.".config/theme/theme-watch.sh".source = themeWatch;

  # Launch the watcher above as a resident launchd agent (at login + liveness monitoring).
  launchd.agents.theme-watch = {
    enable = true;
    config = {
      ProgramArguments = [ "${themeWatch}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/theme-watch.err";
      StandardOutPath = "/tmp/theme-watch.out";
    };
  };

  # Resident watcher that recomputes the sketchybar display map (WM monitor -> sketchybar display index)
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

  # borders (JankyBorders) resident agent. Used to be launched from aerospace's
  # after-startup-command; OmniWM has no exec action, so launchd owns the daemon now.
  # A hand-written com.felixkratz.borders plist (hardcoded colors) predates this —
  # it is booted out and removed by the activation below to avoid a double daemon.
  launchd.agents.borders = {
    enable = true;
    config = {
      ProgramArguments = [ "${bordersrc}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardErrorPath = "/tmp/borders.err";
      StandardOutPath = "/tmp/borders.log";
    };
  };

  # (The brew service that used to start sketchybar is retired in darwin-apps.nix's
  #  retiredLaunchAgents list, together with every other pre-nix plist.)

  # sketchybar itself. The formula was declared but its start was not: the bar only ran because
  # `brew services start sketchybar` had been typed once on this machine, so a fresh mac rebuilt
  # from this repo came up with no bar. Own the daemon here like borders, and retire the brew
  # service in the activation below.
  # PATH mirrors what the brew plist exported — sketchybarrc and the plugins call brew-installed
  # binaries (sketchybar, media-control, displayplacer, jq) and launchd starts with a bare PATH.
  launchd.agents.sketchybar = {
    enable = true;
    config = {
      ProgramArguments = [ "/opt/homebrew/bin/sketchybar" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      EnvironmentVariables = {
        PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
        LANG = "en_US.UTF-8";
      };
      StandardErrorPath = "/tmp/sketchybar.err";
      StandardOutPath = "/tmp/sketchybar.log";
    };
  };

  # One-shot migration: stop the brew service so it doesn't race the agent above at login.
  # `brew services stop` unloads it and removes homebrew.mxcl.sketchybar.plist, so this is a no-op
  # from the second rebuild on.
  home.activation.sketchybarBrewService = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    legacy_plist="$HOME/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist"
    if [ -f "$legacy_plist" ]; then
      run /opt/homebrew/bin/brew services stop sketchybar 2>/dev/null || true
      run rm -f "$legacy_plist"
    fi
  '';

  # Bridge OmniWM IPC events to the sketchybar workspace-change event.
  # aerospace used to fire aerospace_workspace_change itself via exec-and-forget, but omniwm
  # has no exec action, so this resident agent converts `omniwmctl watch` events into
  # the same event + env vars (the sketchybar event name is kept for compatibility).
  launchd.agents.omniwm-bridge = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/.config/sketchybar/helpers/omniwm-bridge.sh"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      ThrottleInterval = 10;
      StandardErrorPath = "/tmp/omniwm-bridge.err";
      StandardOutPath = "/tmp/omniwm-bridge.log";
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

  # keebmouse (self-made, gapul/keebmouse): keyboard-driven pointer, Hyper+Shift+G to toggle.
  # The app itself is a local self-build (see docs/self-build-software.md) so it stays outside
  # nix/brew for now, but its resident agent belongs here — it used to be a hand-written
  # ~/Library/LaunchAgents/net.gapul.keebmouse.plist, i.e. a login-time daemon nothing declared.
  # Same KeepAlive shape as that plist, so behaviour is unchanged.
  launchd.agents.keebmouse = {
    enable = true;
    config = {
      ProgramArguments = [ "/Applications/keebmouse.app/Contents/MacOS/keebmouse" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardErrorPath = "/tmp/keebmouse.err";
      StandardOutPath = "/tmp/keebmouse.log";
    };
  };

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
