{
  config,
  lib,
  pkgs,
  desktopScripts,
  wlKeyboard,
  ...
}:
# niri, the default session on nixos-laptop (greetd starts niri-session, hosts/nixos-laptop.nix).
# Imported from home/hyprland.nix, which stays as the fallback session in the greeter and still
# owns everything the two sessions share: the bar, hyprlock/hypridle, mako, the launcher, the
# power menu. Only the compositor's own config is here; desktopScripts (hyprland.nix) and
# wlKeyboard (wl-keyboard.nix) are the scripts those modules build, passed in as module args.
#
# The keys follow the Hyprland rice: Hyper (Super+Ctrl+Alt, from xremap) drives the window
# manager so Super+key stays free for the apps, as on the mac. What changes is the layout:
# windows are columns on a strip that scrolls sideways, and workspaces stack vertically.
let
  c = import ../lib/theme.nix; # hex without the leading #
  hyper = "Super+Ctrl+Alt";
  # A KDL string literal (JSON's escaping is a subset of KDL's).
  str = builtins.toJSON;
  # One bind. `title` is what the hotkey overlay (Hyper+/) shows instead of the raw command.
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

  binds = [
    (bind {
      key = "${hyper}+Return";
      action = spawn [ "ghostty" ];
      title = "Terminal";
    })
    (bind {
      key = "${hyper}+Q";
      opts = " repeat=false";
      action = "close-window";
    })
    (bind {
      key = "${hyper}+Shift+M";
      action = "quit";
    })
    (bind {
      key = "${hyper}+E";
      action = spawn [
        "ghostty"
        "-e"
        "yazi"
      ];
      title = "Files (yazi)";
    })
    (bind {
      key = "${hyper}+R";
      action = spawn [
        "${desktopScripts.launcher}"
        "toggle"
      ];
      title = "Launcher";
    })
    # Win+Space, like Cmd+Space
    (bind {
      key = "Super+Space";
      action = spawn [
        "${desktopScripts.launcher}"
        "toggle"
      ];
      title = "Launcher";
    })
    (bind {
      key = "${hyper}+V";
      action = "toggle-window-floating";
    })
    (bind {
      key = "${hyper}+F";
      action = "fullscreen-window";
    })
    (bind {
      key = "${hyper}+Shift+F";
      action = "maximize-column";
    })
    (bind {
      key = "${hyper}+L";
      action = spawn [ "hyprlock" ];
      title = "Lock";
    })
    (bind {
      key = "${hyper}+C";
      action = spawnSh "cliphist list | wofi --dmenu | cliphist decode | wl-copy";
      title = "Clipboard history";
    })
    (bind {
      key = "${hyper}+Period";
      action = spawn [ "wofi-emoji" ];
      title = "Emoji";
    })
    (bind {
      key = "${hyper}+Slash";
      action = "show-hotkey-overlay";
    })
    # Power menu. Three tiles a row with a wide margin, so the tiles are not the whole screen.
    (bind {
      key = "${hyper}+Escape";
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
      key = "${hyper}+Comma";
      action = spawn [ "${desktopScripts.settingsMenu}" ];
      title = "Settings";
    })
    (bind {
      key = "${hyper}+P";
      action = spawn [ "${desktopScripts.screenshotRegion}" ];
      title = "Screenshot a region (satty, clipboard)";
    })
    # Saved under screenshot-path below and copied, like Hyprland's hyprshot -m window.
    (bind {
      key = "${hyper}+Shift+P";
      action = "screenshot-window";
    })
    (bind {
      key = "${hyper}+Shift+C";
      action = spawn [
        "hyprpicker"
        "-a"
      ];
      title = "Pick a colour";
    })
    (bind {
      key = "${hyper}+Shift+N";
      action = spawnSh "busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 4000";
      title = "Night light on";
    })
    (bind {
      key = "${hyper}+Shift+D";
      action = spawnSh "busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 6500";
      title = "Night light off";
    })
    # wl-keyboard.nix: pointer by labels, and the which-key menu.
    (bind {
      key = "${hyper}+I";
      action = spawn [ "${wlKeyboard.grid}" ];
      title = "Pointer: grid";
    })
    (bind {
      key = "${hyper}+K";
      action = spawn [ "${wlKeyboard.menu}" ];
      title = "Menu (wlr-which-key)";
    })
    (bind {
      key = "${hyper}+O";
      opts = " repeat=false";
      action = "toggle-overview";
    })

    # Focus: sideways through the columns, up and down through a column's windows and on into
    # the next workspace.
    (bind {
      key = "${hyper}+Left";
      action = "focus-column-left";
    })
    (bind {
      key = "${hyper}+Right";
      action = "focus-column-right";
    })
    (bind {
      key = "${hyper}+Up";
      action = "focus-window-or-workspace-up";
    })
    (bind {
      key = "${hyper}+Down";
      action = "focus-window-or-workspace-down";
    })
    (bind {
      key = "${hyper}+Shift+Left";
      action = "move-column-left";
    })
    (bind {
      key = "${hyper}+Shift+Right";
      action = "move-column-right";
    })
    (bind {
      key = "${hyper}+Shift+Up";
      action = "move-window-up-or-to-workspace-up";
    })
    (bind {
      key = "${hyper}+Shift+Down";
      action = "move-window-down-or-to-workspace-down";
    })
    # Column width, and taking a window into / out of the neighbouring column.
    (bind {
      key = "${hyper}+Minus";
      action = ''set-column-width "-10%"'';
    })
    (bind {
      key = "${hyper}+Equal";
      action = ''set-column-width "+10%"'';
    })
    (bind {
      key = "${hyper}+BracketLeft";
      action = "consume-or-expel-window-left";
    })
    (bind {
      key = "${hyper}+BracketRight";
      action = "consume-or-expel-window-right";
    })
    (bind {
      key = "${hyper}+WheelScrollDown";
      opts = " cooldown-ms=150";
      action = "focus-workspace-down";
    })
    (bind {
      key = "${hyper}+WheelScrollUp";
      opts = " cooldown-ms=150";
      action = "focus-workspace-up";
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
  # Hyper+1..9,0 go to workspaces 1..10; with Shift, the focused column moves there.
  ++ builtins.concatLists (
    builtins.genList (
      i:
      let
        n = toString (i + 1);
        k = toString (if i + 1 == 10 then 0 else i + 1);
      in
      [
        (bind {
          key = "${hyper}+${k}";
          action = "focus-workspace ${n}";
        })
        (bind {
          key = "${hyper}+Shift+${k}";
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
        touchpad {
            tap
            natural-scroll
        }
        focus-follows-mouse
    }

    // The panel at 1, as under Hyprland; the 4K monitor at 1.5, i.e. 2560x1440 logical.
    output "eDP-1" {
        scale 1
    }
    output "DP-1" {
        scale 1.5
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
        match app-id=r#"^nwg-displays$"#
        open-floating true
    }
    window-rule {
        match app-id=r#"firefox"# title="^Picture-in-Picture$"
        open-floating true
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
in
{
  xdg.configFile."niri/config.kdl".source = validated;
}
