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
in
{
  # Binaries referenced by the keybinds / exec-once below. Without these the rice
  # is inert: $mod+Return execs a ghostty that is not in the closure, and the
  # night-light / screenshot / clipboard binds silently do nothing.
  home.packages = with pkgs; [
    ghostty # $terminal
    wofi # $menu, and the cliphist picker
    hyprpolkitagent # polkit agent (started by its own unit, see below)
    hyprshot # screenshots
    hyprpicker # color picker
    wlogout # power menu
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
      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$menu" = "wofi --show drun";

      monitor = ",preferred,auto,1";

      # Only things that have no systemd user unit of their own. hypridle / waybar /
      # mako are started by their home-manager services below; listing them here as
      # well launches a second copy of each (two bars stacked on the screen).
      # Hyprland's stock background is a near-white gradient with its own logo on it, and
      # the terminal sits on top of it at background-opacity 0.5 — the text came out
      # unreadable. hyprpaper was in the closure and exec-once'd but never given a
      # hyprpaper.conf, so it started and painted nothing. Rather than carry a daemon and a
      # wallpaper image for a flat colour, let Hyprland paint the theme base itself.
      # background_color alone is not enough: the stock wallpaper is drawn over it, so it
      # has to be turned off as well before the colour is visible.
      misc = {
        background_color = "rgb(${c.base})";
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
      };

      exec-once = [
        "wl-paste --watch cliphist store" # accumulate clipboard history
        "wl-gammarelay-rs" # dbus daemon for night light
      ];

      input = {
        kb_layout = "us"; # use "jp" for a JIS layout
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
        # screenshot (hyprshot) / color picker
        "$mod, P, exec, hyprshot -m region --clipboard-only" # region -> clipboard
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
  programs.hyprlock = {
    enable = true;
    settings = {
      background = [ { color = "rgb(${c.base})"; } ];
      input-field = [
        {
          size = "260, 50";
          outline_thickness = 2;
          outer_color = "rgb(${c.iris})";
          inner_color = "rgb(${c.surface})";
          font_color = "rgb(${c.text})";
          placeholder_text = "password";
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
          timeout = 900; # suspend after 15 minutes (battery protection, lid open only)
          on-timeout = whenLidOpen "systemctl suspend";
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
    style = ''
      * { font-family: "JetBrainsMono Nerd Font"; font-size: 13px; }
      window#waybar { background: #${c.base}; color: #${c.text}; }
      #workspaces button.active { color: #${c.iris}; }
      #battery, #network, #pulseaudio, #backlight, #clock { padding: 0 8px; }
    '';
  };

  # ghostty config from dotfiles (reuses the same configs/terminals/ghostty as darwin).
  home.file.".config/ghostty".source = ../../configs/terminals/ghostty;

  # The shared config is written for macOS, where ghostty lives as a Quick Terminal:
  # `initial-window = false` plus `quit-after-last-window-closed = false` keep it resident
  # with no window until cmd+space summons one. On Linux that combination means
  # `$mod+Return` spawns a process that never maps a window, so the terminal looks broken
  # while stray ghostty processes pile up. Undo just those two here; the shared config
  # includes this file last, so these win.
  home.file.".config/ghostty.local/platform.conf".text = ''
    initial-window = true
    quit-after-last-window-closed = true
  '';
}
