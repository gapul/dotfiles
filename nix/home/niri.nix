{
  config,
  lib,
  pkgs,
  desktopScripts,
  wlKeyboard,
  wallpaperScripts,
  ...
}:
# niri, the default session on nixos-laptop (greetd starts niri-session, hosts/nixos-laptop.nix).
# Imported from home/hyprland.nix, which stays as the fallback session in the greeter and still
# owns everything the two sessions share: the bar, hyprlock/hypridle, mako, the launcher, the
# power menu. Only the compositor's own config is here; desktopScripts (hyprland.nix) and
# wlKeyboard (wl-keyboard.nix) are the scripts those modules build, passed in as module args.
#
# The keys follow OmniWM on the mac (configs/wm/omniwm/settings.toml), on Super: Mod is niri's
# mod-key, Super by default, which xremap sends for Caps Lock and Copilot-then-key
# (home/xremap.nix), and which drags and resizes windows with the mouse. What changes from Hyprland is the layout: windows
# are columns on a strip that scrolls sideways, and workspaces stack vertically.
let
  c = import ../lib/theme.nix; # hex without the leading #
  mod = "Mod";
  # A KDL string literal (JSON's escaping is a subset of KDL's).
  str = builtins.toJSON;
  # One bind. `title` is what the hotkey overlay (Super+/) shows instead of the raw command.
  bind =
    {
      key,
      action,
      title ? null,
      opts ? "",
    }:
    "${key}${opts}${
      lib.optionalString (title != null) " hotkey-overlay-title=${str title}"
    } { ${action}; }";
  spawn = args: "spawn ${lib.concatMapStringsSep " " str args}";
  spawnSh = cmd: "spawn-sh ${str cmd}";
  locked = " allow-when-locked=true";

  # Like vim-anywhere: the focused text field opens in nvim, and :wq types it back. For apps
  # with no editor of their own, such as T3 Code's prompt box. Ctrl+V and not Shift+Insert,
  # which Electron's fields don't bind; the sleep lets niri hand focus back before the paste,
  # and the clipboard keeps the text in case the paste misses. Recipe from
  # tecosaur/emacs-everywhere#50 (its niri comment) and abdubanna/nvim-wl-anywhere.
  editField = pkgs.writeShellScript "edit-field" ''
    set -eu
    wtype=${pkgs.wtype}/bin/wtype
    wlcopy=${pkgs.wl-clipboard}/bin/wl-copy
    wlpaste=${pkgs.wl-clipboard}/bin/wl-paste
    f=$(mktemp --suffix=.md)
    trap 'rm -f "$f"' EXIT

    # Take what the field already holds: select all, copy, read it back.
    $wlcopy --clear
    $wtype -M ctrl -k a -m ctrl
    sleep 0.05
    $wtype -M ctrl -k c -m ctrl
    sleep 0.1
    $wlpaste --no-newline >"$f" 2>/dev/null || true
    before=$(cat "$f")

    ${pkgs.ghostty}/bin/ghostty --class=net.gapul.editfield --title=edit-field \
      -e nvim +'normal! G$' "$f"

    after=$(cat "$f")
    [ "$after" = "$before" ] && exit 0
    sleep 0.15
    if [ -z "$after" ]; then
      $wtype -M ctrl -k a -m ctrl
      $wtype -k BackSpace
    else
      $wlcopy <"$f"
      $wtype -M ctrl -k a -m ctrl
      $wtype -M ctrl -k v -m ctrl
    fi
  '';

  binds = [
    (bind {
      key = "${mod}+Return";
      action = spawn [ "ghostty" ];
      title = "Terminal";
    })
    (bind {
      key = "${mod}+Q";
      opts = " repeat=false";
      action = "close-window";
    })
    (bind {
      key = "${mod}+E";
      action = spawn [
        "ghostty"
        "-e"
        "yazi"
      ];
      title = "Files (yazi)";
    })
    (bind {
      key = "${mod}+W";
      action = spawn [ "${editField}" ];
      title = "Edit the focused text field in nvim";
    })
    # Super+Space, and thumb Ctrl+Space through xremap, like Cmd+Space on the mac.
    (bind {
      key = "Super+Space";
      action = spawn [
        "${desktopScripts.launcher}"
        "toggle"
      ];
      title = "Launcher";
    })
    (bind {
      key = "${mod}+V";
      action = "toggle-window-floating";
    })
    (bind {
      key = "${mod}+F";
      action = "maximize-column";
    })
    (bind {
      key = "${mod}+Shift+F";
      action = "fullscreen-window";
    })
    (bind {
      key = "${mod}+Shift+Escape";
      action = spawn [ "hyprlock" ];
      title = "Lock";
    })
    (bind {
      key = "${mod}+C";
      action = spawnSh "cliphist list | wofi --dmenu | cliphist decode | wl-copy";
      title = "Clipboard history";
    })
    (bind {
      key = "${mod}+Period";
      action = spawn [ "wofi-emoji" ];
      title = "Emoji";
    })
    (bind {
      key = "${mod}+Slash";
      action = "show-hotkey-overlay";
    })
    # Power menu. Three tiles a row with a wide margin, so the tiles are not the whole screen.
    (bind {
      key = "${mod}+Escape";
      action = spawn [
        "wlogout"
        "--buttons-per-row"
        "3"
        "--margin"
        "240"
        "--column-spacing"
        "16"
        "--row-spacing"
        "16"
      ];
      title = "Power menu";
    })
    (bind {
      key = "${mod}+Comma";
      action = spawn [ "${desktopScripts.settingsMenu}" ];
      title = "Settings";
    })
    (bind {
      key = "${mod}+P";
      action = spawn [ "${desktopScripts.screenshotRegion}" ];
      title = "Screenshot a region (satty, clipboard)";
    })
    # Saved under screenshot-path below and copied, like Hyprland's hyprshot -m window.
    (bind {
      key = "${mod}+Shift+P";
      action = "screenshot-window";
    })
    (bind {
      key = "${mod}+Shift+C";
      action = spawn [
        "hyprpicker"
        "-a"
      ];
      title = "Pick a colour";
    })
    (bind {
      key = "${mod}+Alt+N";
      action = spawnSh "busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 4000";
      title = "Night light on";
    })
    (bind {
      key = "${mod}+Alt+D";
      action = spawnSh "busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 6500";
      title = "Night light off";
    })
    # wl-keyboard.nix: pointer by labels, and the which-key menu.
    (bind {
      key = "${mod}+G";
      action = spawn [ "${wlKeyboard.grid}" ];
      title = "Pointer: grid";
    })
    (bind {
      key = "${mod}+Semicolon";
      action = spawn [ "${wlKeyboard.menu}" ];
      title = "Menu (wlr-which-key)";
    })
    (bind {
      key = "${mod}+O";
      opts = " repeat=false";
      action = "toggle-overview";
    })

    # The same on H/J/K/L, as OmniWM has them on the mac (configs/wm/omniwm/settings.toml).
    (bind {
      key = "${mod}+H";
      action = "focus-column-left";
    })
    (bind {
      key = "${mod}+Shift+H";
      action = "move-column-left";
    })
    (bind {
      key = "${mod}+L";
      action = "focus-column-right";
    })
    (bind {
      key = "${mod}+Shift+L";
      action = "move-column-right";
    })
    (bind {
      key = "${mod}+K";
      action = "focus-window-up";
    })
    (bind {
      key = "${mod}+Shift+K";
      action = "move-window-up";
    })
    (bind {
      key = "${mod}+J";
      action = "focus-window-down";
    })
    (bind {
      key = "${mod}+Shift+J";
      action = "move-window-down";
    })
    # Also as on the mac: column widths, tabbed column, previous workspace, monitors.
    (bind {
      key = "${mod}+R";
      action = "switch-preset-column-width";
    })
    (bind {
      key = "${mod}+Shift+R";
      action = "switch-preset-column-width-back";
    })
    (bind {
      key = "${mod}+T";
      action = "toggle-column-tabbed-display";
    })
    (bind {
      key = "${mod}+Tab";
      action = "focus-workspace-previous";
    })
    (bind {
      key = "${mod}+N";
      action = "focus-monitor-previous";
    })
    (bind {
      key = "${mod}+M";
      action = "focus-monitor-next";
    })
    (bind {
      key = "${mod}+Shift+N";
      action = "move-workspace-to-monitor-left";
    })
    (bind {
      key = "${mod}+Shift+M";
      action = "move-workspace-to-monitor-right";
    })
    # Focus: sideways through the columns, up and down through a column's windows.
    (bind {
      key = "${mod}+Left";
      action = "focus-column-left";
    })
    (bind {
      key = "${mod}+Right";
      action = "focus-column-right";
    })
    (bind {
      key = "${mod}+Up";
      action = "focus-window-up";
    })
    (bind {
      key = "${mod}+Down";
      action = "focus-window-down";
    })
    (bind {
      key = "${mod}+Shift+Left";
      action = "move-column-left";
    })
    (bind {
      key = "${mod}+Shift+Right";
      action = "move-column-right";
    })
    (bind {
      key = "${mod}+Shift+Up";
      action = "move-window-up";
    })
    (bind {
      key = "${mod}+Shift+Down";
      action = "move-window-down";
    })
    # Column width, and taking a window into / out of the neighbouring column.
    (bind {
      key = "${mod}+Minus";
      action = ''set-column-width "-10%"'';
    })
    (bind {
      key = "${mod}+Equal";
      action = ''set-column-width "+10%"'';
    })
    (bind {
      key = "${mod}+BracketLeft";
      action = "consume-or-expel-window-left";
    })
    (bind {
      key = "${mod}+BracketRight";
      action = "consume-or-expel-window-right";
    })
    (bind {
      key = "${mod}+WheelScrollDown";
      opts = " cooldown-ms=150";
      action = "focus-workspace-down";
    })
    (bind {
      key = "${mod}+WheelScrollUp";
      opts = " cooldown-ms=150";
      action = "focus-workspace-up";
    })

    # From niri's default config, on keys the binds above leave free. Where the default moves
    # with Ctrl, Shift moves here (as on H/J/K/L and the digits), and Ctrl moves the workspace.
    (bind {
      key = "${mod}+U";
      action = "focus-workspace-down";
    })
    (bind {
      key = "${mod}+I";
      action = "focus-workspace-up";
    })
    (bind {
      key = "${mod}+Page_Down";
      action = "focus-workspace-down";
    })
    (bind {
      key = "${mod}+Page_Up";
      action = "focus-workspace-up";
    })
    (bind {
      key = "${mod}+Shift+U";
      action = "move-column-to-workspace-down";
    })
    (bind {
      key = "${mod}+Shift+I";
      action = "move-column-to-workspace-up";
    })
    (bind {
      key = "${mod}+Shift+Page_Down";
      action = "move-column-to-workspace-down";
    })
    (bind {
      key = "${mod}+Shift+Page_Up";
      action = "move-column-to-workspace-up";
    })
    (bind {
      key = "${mod}+Ctrl+U";
      action = "move-workspace-down";
    })
    (bind {
      key = "${mod}+Ctrl+I";
      action = "move-workspace-up";
    })
    (bind {
      key = "${mod}+Ctrl+Page_Down";
      action = "move-workspace-down";
    })
    (bind {
      key = "${mod}+Ctrl+Page_Up";
      action = "move-workspace-up";
    })
    (bind {
      key = "${mod}+Home";
      action = "focus-column-first";
    })
    (bind {
      key = "${mod}+End";
      action = "focus-column-last";
    })
    (bind {
      key = "${mod}+Shift+Home";
      action = "move-column-to-first";
    })
    (bind {
      key = "${mod}+Shift+End";
      action = "move-column-to-last";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+H";
      action = "move-column-to-monitor-left";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+J";
      action = "move-column-to-monitor-down";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+K";
      action = "move-column-to-monitor-up";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+L";
      action = "move-column-to-monitor-right";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+Left";
      action = "move-column-to-monitor-left";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+Down";
      action = "move-column-to-monitor-down";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+Up";
      action = "move-column-to-monitor-up";
    })
    (bind {
      key = "${mod}+Shift+Ctrl+Right";
      action = "move-column-to-monitor-right";
    })
    # Window height within a column, and the rest of the column-width actions.
    (bind {
      key = "${mod}+Shift+Minus";
      action = ''set-window-height "-10%"'';
    })
    (bind {
      key = "${mod}+Shift+Equal";
      action = ''set-window-height "+10%"'';
    })
    (bind {
      key = "${mod}+Ctrl+Shift+R";
      action = "switch-preset-window-height";
    })
    (bind {
      key = "${mod}+Ctrl+R";
      action = "reset-window-height";
    })
    (bind {
      key = "${mod}+Ctrl+F";
      action = "expand-column-to-available-width";
    })
    (bind {
      key = "${mod}+Ctrl+C";
      action = "center-visible-columns";
    })
    (bind {
      key = "${mod}+Shift+V";
      action = "switch-focus-between-floating-and-tiling";
    })
    # Mouse wheels: with Ctrl the column goes along; Shift turns the vertical wheel sideways.
    (bind {
      key = "${mod}+Ctrl+WheelScrollDown";
      opts = " cooldown-ms=150";
      action = "move-column-to-workspace-down";
    })
    (bind {
      key = "${mod}+Ctrl+WheelScrollUp";
      opts = " cooldown-ms=150";
      action = "move-column-to-workspace-up";
    })
    (bind {
      key = "${mod}+WheelScrollRight";
      action = "focus-column-right";
    })
    (bind {
      key = "${mod}+WheelScrollLeft";
      action = "focus-column-left";
    })
    (bind {
      key = "${mod}+Ctrl+WheelScrollRight";
      action = "move-column-right";
    })
    (bind {
      key = "${mod}+Ctrl+WheelScrollLeft";
      action = "move-column-left";
    })
    (bind {
      key = "${mod}+Shift+WheelScrollDown";
      action = "focus-column-right";
    })
    (bind {
      key = "${mod}+Shift+WheelScrollUp";
      action = "focus-column-left";
    })
    (bind {
      key = "${mod}+Ctrl+Shift+WheelScrollDown";
      action = "move-column-right";
    })
    (bind {
      key = "${mod}+Ctrl+Shift+WheelScrollUp";
      action = "move-column-left";
    })
    (bind {
      key = "Super+Alt+L";
      action = spawn [ "hyprlock" ];
      title = "Lock";
    })
    # Leaving niri asks for confirmation first.
    (bind {
      key = "${mod}+Shift+E";
      action = "quit";
    })
    (bind {
      key = "Ctrl+Alt+Delete";
      action = "quit";
    })
    (bind {
      key = "Print";
      action = "screenshot";
    })
    (bind {
      key = "Ctrl+Print";
      action = "screenshot-screen";
    })
    (bind {
      key = "Alt+Print";
      action = "screenshot-window";
    })

    # Volume / brightness / media (work while locked; held keys repeat by default).
    (bind {
      key = "XF86AudioRaiseVolume";
      opts = locked;
      action = spawnSh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
    })
    (bind {
      key = "XF86AudioLowerVolume";
      opts = locked;
      action = spawnSh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
    })
    (bind {
      key = "XF86AudioMute";
      opts = locked;
      action = spawnSh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
    })
    (bind {
      key = "XF86AudioMicMute";
      opts = locked;
      action = spawnSh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
    })
    (bind {
      key = "XF86AudioStop";
      opts = locked;
      action = spawn [
        "playerctl"
        "stop"
      ];
    })
    (bind {
      key = "XF86MonBrightnessUp";
      opts = locked;
      action = spawn [
        "brightnessctl"
        "set"
        "5%+"
      ];
    })
    (bind {
      key = "XF86MonBrightnessDown";
      opts = locked;
      action = spawn [
        "brightnessctl"
        "set"
        "5%-"
      ];
    })
    (bind {
      key = "XF86AudioPlay";
      opts = locked;
      action = spawn [
        "playerctl"
        "play-pause"
      ];
    })
    (bind {
      key = "XF86AudioNext";
      opts = locked;
      action = spawn [
        "playerctl"
        "next"
      ];
    })
    (bind {
      key = "XF86AudioPrev";
      opts = locked;
      action = spawn [
        "playerctl"
        "previous"
      ];
    })
  ]
  # Super+1..9,0 go to workspaces 1..10; with Shift, the focused column moves there.
  ++ builtins.concatLists (
    builtins.genList (
      i:
      let
        n = toString (i + 1);
        k = toString (if i + 1 == 10 then 0 else i + 1);
      in
      [
        (bind {
          key = "${mod}+${k}";
          action = "focus-workspace ${n}";
        })
        (bind {
          key = "${mod}+Shift+${k}";
          action = "move-column-to-workspace ${n}";
        })
      ]
    ) 10
  );

  # desktop-appearance.nix swaps the palette's colours in this file for the light/dark mode,
  # by rewriting each #rrggbb it finds, so colours have to be written as #hex here.
  kdl = pkgs.writeText "niri-config.kdl" ''
    input {
        keyboard {
            xkb {
                layout "us"
                // Caps Lock is Ctrl (also in hosts/nixos-laptop.nix for the console and greeter).
                options "ctrl:nocaps"
            }
        }
        // No tap-to-click: palm taps while typing moved the caret and committed SKK preedits.
        // As on the mac: a two-finger press is the right click, three fingers the middle
        // (which pastes the primary selection), and the pad ignores the palm while typing.
        touchpad {
            natural-scroll
            click-method "clickfinger"
            dwt
        }
        // Hovering a window focuses it. max-scroll-amount 0% keeps that to windows already on
        // screen: brushing the sliver of a column at the edge would otherwise scroll the strip
        // over to it.
        focus-follows-mouse max-scroll-amount="0%"
    }

    // The panel at 1, as under Hyprland; the 4K monitor at 1.5, i.e. 2560x1440 logical.
    // The 32" 1080p Dell looks oversized at 1, so 0.8 (2400x1350 logical).
    output "eDP-1" {
        scale 1
    }
    output "DP-1" {
        scale 1.5
    }
    output "Dell Inc. DELL S3222HS 8K9LQD3" {
        scale 0.8
    }

    cursor {
        xcursor-theme "${config.home.pointerCursor.name}"
        xcursor-size ${toString config.home.pointerCursor.size}
    }

    layout {
        gaps 10
        background-color "#${c.base}"
        center-focused-column "never"
        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }
        default-column-width { proportion 0.5; }
        focus-ring {
            off
        }
        // The Hyprland rice's border: an iris-to-foam gradient on the focused window.
        border {
            width 2
            active-gradient from="#${c.iris}" to="#${c.foam}" angle=45
            inactive-color "#${c.overlay}"
            urgent-color "#${c.love}"
        }
        shadow {
            on
            softness 24
            spread 4
            offset x=0 y=4
            color "#${c.base}cc"
        }
    }

    // Apps draw no title bars of their own; the border and the bar are enough.
    prefer-no-csd

    hotkey-overlay {
        skip-at-startup
    }

    // greetd starts the session with XDG_SESSION_TYPE=tty and niri passes its own environment
    // to everything it spawns, so apps saw "tty" under Wayland. Libraries that branch on it
    // break: bindbc-opengl (nijiexpose) then looks for a GLX context, finds none next to the
    // EGL one SDL made, and the app crashes at start.
    environment {
        XDG_SESSION_TYPE "wayland"
    }

    screenshot-path "${config.xdg.userDirs.pictures}/Screenshots/%Y-%m-%d_%H-%M-%S.png"

    // Things with no systemd user unit of their own (the bar, idle, notifications, wallpaper and
    // fcitx5 are started by their units on graphical-session.target, as under Hyprland).
    spawn-at-startup "${pkgs.wl-clipboard}/bin/wl-paste" "--watch" "${pkgs.cliphist}/bin/cliphist" "store"
    spawn-at-startup "${pkgs.wl-gammarelay-rs}/bin/wl-gammarelay-rs"

    window-rule {
        geometry-corner-radius 8
        clip-to-geometry true
    }
    // The settings tools ($mod+comma) are small dialogs, not columns.
    window-rule {
        match app-id=r#"^(org\.pulseaudio\.)?pavucontrol$"#
        match app-id=r#"^nm-connection-editor$"#
        match app-id=r#"^blueman-manager$"#
        match app-id=r#"^net\.gapul\.settings$"#
        match app-id=r#"^nwg-displays$"#
        open-floating true
    }
    window-rule {
        match app-id=r#"firefox"# title="^Picture-in-Picture$"
        open-floating true
    }
    // File pickers: yazi in ghostty, opened by termfilechooser (home/linux-gui.nix).
    window-rule {
        match app-id=r#"^net\.gapul\.termfilechooser$"#
        open-floating true
        default-column-width { proportion 0.6; }
        default-window-height { proportion 0.7; }
    }
    // nvim for the focused text field ($mod+W, editField above).
    window-rule {
        match app-id=r#"^net\.gapul\.editfield$"#
        open-floating true
        default-column-width { proportion 0.5; }
        default-window-height { proportion 0.5; }
    }
    // Blacked out in screen shares and recordings (screenshots still show them):
    // passwords, messages and mail.
    window-rule {
        match app-id=r#"(?i)^(bitwarden|org\.keepassxc\.keepassxc|keepassxc)$"#
        match app-id=r#"(?i)^(beeper|signal|element|chat-simplex|chat\.simplex)"#
        match app-id=r#"(?i)^thunderbird"#
        block-out-from "screencast"
    }

    binds {
    ${lib.concatMapStrings (b: "    ${b}\n") binds}}
  '';

  # Checked at build time, so a typo fails the rebuild rather than leaving niri on its last
  # good config with an error banner.
  validated = pkgs.runCommand "niri-config.kdl" { nativeBuildInputs = [ pkgs.niri ]; } ''
    HOME=$TMPDIR niri validate -c ${kdl}
    cp ${kdl} $out
  '';
  # Reacts to niri's event stream, for what the config file cannot say:
  #   - a terminal taking focus turns SKK off (nvim there has skkeleton);
  #   - a workspace switch repaints that output's wallpaper (home/darkman.nix);
  #   - while a screen cast runs, mako holds notifications back (its do-not-disturb mode).
  niriEvents = pkgs.writers.writePython3 "niri-events" { flakeIgnore = [ "E501" ]; } ''
    import json
    import subprocess
    import time

    NIRI = "${pkgs.niri}/bin/niri"
    TERMINALS = {"com.mitchellh.ghostty", "net.gapul.editfield"}


    def run(*args):
        subprocess.run(args, check=False)


    def refresh_bar():
        # custom/niri-ws-N in the bar (home/hyprland.nix) rerun on SIGRTMIN+9.
        # nixpkgs wraps waybar, so the process is .waybar-wrapped; -x with the exact pattern so the
        # signal (fatal to anything not expecting it) reaches waybar alone.
        run("${pkgs.procps}/bin/pkill", "-RTMIN+9", "-x", r"\.?waybar(-wrapped)?")


    windows = {}
    placed = {}  # window id -> (app_id, workspace_id), what the bar shows
    outputs = {}  # workspace id -> output name
    casting = False
    events = subprocess.Popen([NIRI, "msg", "--json", "event-stream"], stdout=subprocess.PIPE, text=True)
    for line in events.stdout:
        [(kind, body)] = json.loads(line).items()
        if kind == "WorkspacesChanged":
            outputs = {w["id"]: w.get("output") or "" for w in body["workspaces"]}
            refresh_bar()
        elif kind == "WindowsChanged":
            windows = {w["id"]: w.get("app_id") for w in body["windows"]}
            placed = {w["id"]: (w.get("app_id"), w.get("workspace_id")) for w in body["windows"]}
            refresh_bar()
        elif kind == "WindowOpenedOrChanged":
            w = body["window"]
            windows[w["id"]] = w.get("app_id")
            # Also sent for every title change; only a new window or a move matters to the bar.
            if placed.get(w["id"]) != (w.get("app_id"), w.get("workspace_id")):
                placed[w["id"]] = (w.get("app_id"), w.get("workspace_id"))
                refresh_bar()
        elif kind == "WindowClosed":
            windows.pop(body["id"], None)
            placed.pop(body["id"], None)
            refresh_bar()
        elif kind in ("WindowLayoutsChanged", "WorkspaceUrgencyChanged"):
            refresh_bar()
        elif kind == "WindowFocusChanged":
            if windows.get(body["id"]) in TERMINALS:
                # Give fcitx5 a moment to see the new focus, or this turns off the old window.
                time.sleep(0.15)
                run("${pkgs.fcitx5}/bin/fcitx5-remote", "-c")
        elif kind == "WorkspaceActivated":
            refresh_bar()
            run("${wallpaperScripts.setWallpaper}", "", "0.5", outputs.get(body["id"], ""))
        elif kind == "CastsChanged":
            now = bool(body["casts"])
            if now != casting:
                casting = now
                run("${pkgs.mako}/bin/makoctl", "mode", "-a" if now else "-r", "do-not-disturb")
    raise SystemExit(events.wait() or 1)
  '';
in
{
  xdg.configFile."niri/config.kdl".source = validated;

  systemd.user.services.niri-events = {
    Unit = {
      Description = "React to niri events (SKK off in terminals, per-workspace wallpaper, quiet casts)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      # Only under niri; Hyprland, the fallback session, has no NIRI_SOCKET.
      ExecCondition = "${pkgs.runtimeShell} -c '[ -n \"$NIRI_SOCKET\" ]'";
      ExecStart = "${niriEvents}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
