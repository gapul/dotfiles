{ pkgs, ... }:
# Hyprland user config (Rick). Imported only on nixos-laptop.
# The system side (hosts/nixos-laptop.nix) provides PAM/session for
# programs.hyprland / hyprlock; this side manages appearance and keybinds.
# Colors are shared via configs/theme/palettes.json (rose-pine) as SSO ([[theme]]).
let
  c = import ../lib/theme.nix; # c.base / c.text / c.iris ... (hex without leading #)
  # Idle actions that only make sense in front of the machine. With the lid shut it is being
  # used over ssh, and locking or suspending there is what made it look dead: the session
  # goes to hyprlock nobody can dismiss, then hypridle suspends it off the network entirely.
  # Closing the lid on AC already does nothing (HandleLidSwitchExternalPower = ignore in
  # hosts/nixos-laptop.nix); this is the idle timer catching it a few minutes later instead.
  # grep by store path, not by name: if it were missing from hypridle's PATH the guard would
  # fail closed and the machine would simply never lock again, which is the failure you do
  # not notice.
  whenLidOpen = cmd: "${pkgs.gnugrep}/bin/grep -q open /proc/acpi/button/lid/LID/state && ${cmd}";
  # Region -> clipboard, which `hyprshot -m region --clipboard-only` did until Escape: hyprshot
  # 1.3.0 never checks that slurp was cancelled, so it fed grim an empty geometry, copied the
  # empty result over whatever was on the clipboard, and still announced "Screenshot saved".
  # Doing the three steps here lets a cancelled selection simply stop. The window bind keeps
  # hyprshot: that path writes a file, and a cancel makes grim fail before anything is saved.
  screenshotRegion = pkgs.writeShellScript "screenshot-region" ''
    set -euo pipefail
    geometry=$(${pkgs.slurp}/bin/slurp -d) || exit 0
    ${pkgs.grim}/bin/grim -g "$geometry" - | ${pkgs.wl-clipboard}/bin/wl-copy --type image/png
    ${pkgs.libnotify}/bin/notify-send -a Hyprshot "Screenshot copied" "Image copied to the clipboard"
  '';
in
{
  # Binaries referenced by the keybinds / exec-once below. Without these the rice
  # is inert: $mod+Return execs a ghostty that is not in the closure, and the
  # night-light / screenshot / clipboard binds silently do nothing.
  home.packages = with pkgs; [
    ghostty # $terminal
    # wofi is not listed here: it is declared through programs.wofi below, because stylix
    # only themes what home-manager knows it manages. As a bare package it kept rendering
    # its stock white sheet in the middle of a dark desktop.
    hyprpolkitagent # polkit agent (started by its own unit, see below)
    hyprshot # screenshots
    hyprpicker # color picker
    # wlogout is declared through programs.wlogout below, which also writes its stylesheet.
    cliphist # clipboard history
    wl-clipboard # wl-copy / wl-paste, used by the cliphist pipeline
    wl-gammarelay-rs # night light dbus daemon
    brightnessctl # backlight keys
    playerctl # media keys
    wireplumber # wpctl, used by the volume keys
  ];

  # package = null: use the system Hyprland, HM manages only the config.
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    # settings generated in hyprlang format (pinned explicitly since the default may switch to lua).
    configType = "hyprlang";
    settings = {
      # Hyper: Space held, from xremap (home/xremap.nix). Super alone is Cmd there, so the
      # window manager cannot use it without taking Cmd+Q, Cmd+C, ... away from the apps.
      "$mod" = "SUPER CTRL ALT";
      "$terminal" = "ghostty";
      "$menu" = "wofi --show drun";

      monitor = ",preferred,auto,1";

      # Only things that have no systemd user unit of their own. hypridle / waybar /
      # mako are started by their home-manager services below; listing them here as
      # well launches a second copy of each (two bars stacked on the screen).
      # Hyprland's stock background is a near-white gradient with its own logo on it, and
      # the terminal sits on top of it at background-opacity 0.5 — the text came out
      # unreadable, so both are off below. hyprpaper used to be exec-once'd with no
      # hyprpaper.conf and painted nothing, which is why this was a flat colour for a while;
      # it now has a config, written by stylix from the generated wallpaper (home/stylix.nix).
      # background_color stays as the colour behind it, which is what shows in the moment
      # between the compositor starting and hyprpaper painting.
      misc = {
        background_color = "rgb(${c.base})";
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        # If hyprlock dies while the session is locked, the compositor keeps holding the lock
        # and the screen stays black: a replacement hyprlock is refused, and the documented
        # recovery (`hyprctl eval 'hl.clear_crashed_lockscreen()'`) needs the lua config
        # manager, which this build does not have. The session is then only recoverable by
        # logging out. With this on, a fresh hyprlock takes the orphaned lock over instead.
        # Seen for real: a rebuild restarted the session's units out from under a running
        # hyprlock and left the machine unusable except over ssh.
        allow_session_lock_restore = true;
      };

      exec-once = [
        "wl-paste --watch cliphist store" # accumulate clipboard history
        "wl-gammarelay-rs" # dbus daemon for night light
        # Input method (SKK). The package's autostart entry is never read here: Hyprland does not
        # run XDG autostart. fcitx5 comes from i18n.inputMethod (hosts/nixos-laptop.nix).
        "fcitx5 -d --replace"
      ];

      input = {
        kb_layout = "us"; # use "jp" for a JIS layout
        # Caps Lock is Ctrl. xremap (home/xremap.nix) already sends it as Ctrl; this covers the
        # time it is not running.
        kb_options = "ctrl:nocaps";
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgb(${c.iris}) rgb(${c.foam}) 45deg";
        "col.inactive_border" = "rgb(${c.overlay})";
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
        blur = {
          enabled = true;
          size = 6;
          passes = 2;
        };
      };

      animations.enabled = true;

      bind = [
        "$mod, Return, exec, $terminal"
        "$mod, Q, killactive"
        "$mod SHIFT, M, exit" # quit Hyprland
        "$mod, E, exec, $terminal -e yazi" # file manager (yazi)
        "$mod, R, exec, $menu"
        "$mod, V, togglefloating"
        "$mod, F, fullscreen"
        "$mod, L, exec, hyprlock" # manual lock
        "$mod, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy" # paste from history
        "$mod, Escape, exec, wlogout" # power menu
        # screenshot / color picker
        "$mod, P, exec, ${screenshotRegion}" # region -> clipboard
        "$mod SHIFT, P, exec, hyprshot -m window" # window -> save
        "$mod SHIFT, C, exec, hyprpicker -a" # pick a color and copy
        # night light (switch color temperature 4000K / 6500K)
        "$mod SHIFT, N, exec, busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 4000"
        "$mod SHIFT, D, exec, busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 6500"
        # move focus
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
      ]
      ++ builtins.concatLists (
        builtins.genList (
          i:
          let
            n = toString (i + 1);
            key = toString (if i + 1 == 10 then 0 else i + 1); # workspace 10 maps to the 0 key
          in
          [
            "$mod, ${key}, workspace, ${n}"
            "$mod SHIFT, ${key}, movetoworkspace, ${n}"
          ]
        ) 10
      );

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # volume / brightness (supports key-repeat while held)
      bindel = [
        ",XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86MonBrightnessUp, exec, brightnessctl set 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];
      bindl = [
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioPlay, exec, playerctl play-pause"
        ",XF86AudioNext, exec, playerctl next"
        ",XF86AudioPrev, exec, playerctl previous"
      ];
    };
  };

  # lock screen appearance
  # The launcher ($menu, and the cliphist picker). Declared through programs.* rather than
  # home.packages so stylix can write its stylesheet — see home/stylix.nix.
  programs.wofi.enable = true;

  # hyprpaper paints the wallpaper stylix generates from the palette. It needs to be declared
  # through services.* rather than home.packages, or stylix cannot see it and writes no config
  # — which is exactly how it ended up running with an empty screen before.
  services.hyprpaper.enable = true;

  # Power menu ($mod+Escape). With no style.css of its own it fell back to the package's
  # stock sheet — near-black tiles with a #3700B3 highlight, the one screen off the palette.
  # Only the style is written: the stock layout (actions and l/e/u/h/s/r keys) is kept, and
  # the icons still come from the package, as the stock sheet had them.
  programs.wlogout = {
    enable = true;
    style =
      let
        icon = name: "${pkgs.wlogout}/share/wlogout/icons/${name}.png";
      in
      ''
        * {
          background-image: none;
          box-shadow: none;
          font-family: "JetBrainsMono Nerd Font";
        }
        window {
          background-color: alpha(#${c.base}, 0.85);
        }
        button {
          margin: 8px;
          border-radius: 8px;
          border: 2px solid #${c.overlay};
          color: #${c.text};
          background-color: #${c.surface};
          background-repeat: no-repeat;
          background-position: center;
          background-size: 25%;
        }
        button:focus, button:active, button:hover {
          border-color: #${c.iris};
          background-color: #${c.overlay};
          outline-style: none;
        }
        #shutdown:focus, #shutdown:hover, #reboot:focus, #reboot:hover {
          border-color: #${c.love};
        }
        #lock { background-image: image(url("${icon "lock"}")); }
        #logout { background-image: image(url("${icon "logout"}")); }
        #suspend { background-image: image(url("${icon "suspend"}")); }
        #hibernate { background-image: image(url("${icon "hibernate"}")); }
        #shutdown { background-image: image(url("${icon "shutdown"}")); }
        #reboot { background-image: image(url("${icon "reboot"}")); }
      '';
  };

  # The lock screen used to be a flat base colour with a bare input box on it: correct, but it
  # looked like a prompt rather than part of the desk. It now blurs the wallpaper behind a
  # clock, so a locked machine still reads as this machine.
  programs.hyprlock = {
    enable = true;
    settings = {
      background = [
        {
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
          brightness = "0.6";
        }
      ];

      label = [
        # Time, large and centred above the input. font_family has to name a font that is
        # actually in the closure; JetBrainsMono Nerd Font comes in through home.packages.
        {
          text = "$TIME";
          font_size = 92;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(${c.text})";
          position = "0, 180";
          halign = "center";
          valign = "center";
        }
        {
          text = "cmd[update:43200000] date +\"%A, %d %B\"";
          font_size = 20;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(${c.subtle})";
          position = "0, 90";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          size = "300, 52";
          rounding = 26;
          outline_thickness = 2;
          outer_color = "rgb(${c.iris})";
          inner_color = "rgb(${c.surface})";
          font_color = "rgb(${c.text})";
          check_color = "rgb(${c.foam})";
          fail_color = "rgb(${c.love})";
          placeholder_text = "";
          fade_on_empty = false;
          position = "0, -40";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # idle control (started as an HM user service; the system-side services.hypridle is disabled)
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300; # lock after 5 minutes (only with the lid open, see whenLidOpen)
          on-timeout = whenLidOpen "loginctl lock-session";
        }
        {
          timeout = 360; # turn off screen after 6 minutes
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 900; # suspend after 15 minutes (battery protection, lid open and on battery)
          # Suspending takes the machine off the network, and this one is administered over
          # ssh, so only do it when there is a battery to protect. That matches what the lid
          # already does (HandleLidSwitchExternalPower = ignore); until now the idle timer was
          # the one path that still suspended a plugged-in laptop out from under a session.
          # systemd-ac-power exits 0 on mains. Every clause is &&: with `a && b || c` the shell
          # would run c whenever a failed, i.e. suspend as soon as the lid was shut.
          on-timeout = whenLidOpen "! ${pkgs.systemd}/bin/systemd-ac-power && systemctl suspend";
        }
      ];
    };
  };

  # polkit agent and notification daemon. Neither gets started on its own: hyprpolkitagent
  # puts no binary in bin/ at all (the executable lives in libexec/), so the exec-once that
  # named it was spawning a command that does not exist, and home-manager's mako module only
  # writes the config file — it defines no unit, and the one inside the package is installed
  # but never enabled.
  #
  # These must carry a full Service section. `systemd.user.services.<name>` writes a complete
  # unit into ~/.config/systemd/user, which takes priority over the one in the package, so
  # setting only Unit/Install does not extend the packaged unit — it replaces it with a file
  # that has no ExecStart. systemd then refuses the unit with BadUnitSetting, and home-manager
  # activation fails with it, which is how both of these ended up inactive.
  systemd.user.services.hyprpolkitagent = {
    Unit = {
      Description = "Hyprland polkit authentication agent";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notification daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  services.mako = {
    enable = true;
    settings = {
      background-color = "#${c.surface}";
      text-color = "#${c.text}";
      border-color = "#${c.iris}";
      border-radius = 8;
      default-timeout = 5000;
    };
  };

  # status bar
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      modules-left = [
        "hyprland/workspaces"
        "hyprland/window"
      ];
      modules-center = [ "clock" ];
      modules-right = [
        "pulseaudio"
        "backlight"
        "battery"
        "network"
        "tray"
      ];
      clock.format = "{:%Y-%m-%d %H:%M}";
      battery = {
        format = "{capacity}% {icon}";
        format-icons = [
          "󰁻"
          "󰁽"
          "󰁿"
          "󰂁"
          "󰁹"
        ];
      };
      network.format-wifi = "{essid} ";
      pulseaudio.format = "{volume}% {icon}";
      backlight.format = "{percent}% ";
    };
    # The bar was a flat strip with the modules butted together and no way to tell one
    # reading from the next. It is now transparent, with each group sitting on its own
    # rounded slab, so the eye can separate them. Accents come from the palette rather
    # than from a second colour list kept here.
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
        /* waybar draws a 1px halo on every widget unless this is cleared */
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      /* Transparent bar: the slabs below are what is visible, so the wallpaper shows
         between them and the bar stops reading as a black band across the screen. */
      window#waybar {
        background: transparent;
        color: #${c.text};
      }

      /* Shared slab. margin gives the floating look; the top margin is what lifts it
         off the screen edge. */
      #workspaces,
      #window,
      #clock,
      #pulseaudio,
      #backlight,
      #battery,
      #network,
      #tray {
        background: alpha(#${c.surface}, 0.85);
        border-radius: 10px;
        margin: 6px 3px 0 3px;
        padding: 2px 12px;
      }

      /* Workspaces read as a row of pills rather than a slab of numbers. */
      #workspaces { padding: 2px 4px; }
      #workspaces button {
        color: #${c.muted};
        padding: 0 8px;
        border-radius: 8px;
        transition: background 150ms ease, color 150ms ease;
      }
      #workspaces button.active {
        color: #${c.base};
        background: #${c.iris};
      }
      #workspaces button:hover {
        color: #${c.text};
        background: alpha(#${c.overlay}, 0.9);
      }
      #workspaces button.urgent {
        color: #${c.base};
        background: #${c.love};
      }

      /* The focused window's title is context, not a reading — keep it quiet, and let it
         disappear entirely rather than leave an empty slab when nothing is focused. */
      #window { color: #${c.subtle}; }
      window#waybar.empty #window {
        background: transparent;
        padding: 0;
        margin: 0;
      }

      #clock {
        color: #${c.text};
        padding: 2px 16px;
      }

      /* One accent per reading, so a glance lands on the right number. */
      #pulseaudio { color: #${c.foam}; }
      #backlight  { color: #${c.gold}; }
      #battery    { color: #${c.pine}; }
      #network    { color: #${c.iris}; }

      /* States worth interrupting for. */
      #battery.warning  { color: #${c.gold}; }
      #battery.critical {
        color: #${c.base};
        background: #${c.love};
      }
      #battery.charging { color: #${c.foam}; }
      #network.disconnected {
        color: #${c.base};
        background: #${c.love};
      }

      #tray { padding: 2px 10px; }
      #tray menu { background: #${c.surface}; color: #${c.text}; }
    '';
  };

  # ghostty config from dotfiles (reuses the same configs/terminals/ghostty as darwin).
  home.file.".config/ghostty".source = ../../configs/terminals/ghostty;

  # The shared config is written for macOS, where ghostty is a login item:
  # `initial-window = false` plus `quit-after-last-window-closed = false` keep it resident
  # with no window until one is asked for. On Linux that combination means
  # `$mod+Return` spawns a process that never maps a window, so the terminal looks broken
  # while stray ghostty processes pile up. Undo just those two here; the shared config
  # includes this file last, so these win.
  home.file.".config/ghostty.local/platform.conf".text = ''
    initial-window = true
    quit-after-last-window-closed = true
  '';
}
