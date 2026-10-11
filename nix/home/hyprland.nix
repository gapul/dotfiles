{
  config,
  lib,
  pkgs,
  ...
}:
# Hyprland user config (Rick). Imported only on nixos-laptop.
# The system side (hosts/nixos-laptop.nix) provides PAM/session for
# programs.hyprland / hyprlock; this side manages appearance and keybinds.
# Colors are shared via configs/theme/palettes.json (rose-pine) as SSO ([[theme]]).
let
  # Hold a lock for the lifetime of drun so repeated gestures cannot stack windows.
  launcher = pkgs.writeShellScript "wofi-launcher" ''
    set -eu
    mode="''${1:-open}"
    pattern='^${pkgs.wofi}/bin/wofi --show drun$'
    case "$mode" in
      close)
        ${pkgs.procps}/bin/pkill -u "$UID" -f "$pattern" || true
        exit 0
        ;;
      toggle)
        if ${pkgs.procps}/bin/pkill -u "$UID" -f "$pattern"; then
          exit 0
        fi
        ;;
      open) ;;
      *) exit 2 ;;
    esac
    exec ${pkgs.util-linux}/bin/flock -n -E 0 "$XDG_RUNTIME_DIR/wofi-drun.lock" \
      ${pkgs.wofi}/bin/wofi --show drun
  '';
  c = import ../lib/theme.nix; # c.base / c.text / c.iris ... (hex without leading #)
  # An app icon for the bar: a sketchybar-app-font ligature, in that font (see the workspaces
  # module in programs.waybar below).
  appIcon = name: "<span font_family='sketchybar-app-font' size='large' rise='-3500'>${name}</span>";

  # The dark palette's wallpaper, for the lock screen (hyprlock's config is static, and a
  # dark lock screen is right at any hour).
  lockWallpaper = import ../lib/wallpaper.nix {
    inherit pkgs;
    p = (builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json)).palettes.rose-pine;
    name = "rose-pine";
  };

  # Hyper+/ : every keybind, searchable. Read from Hyprland itself (so it cannot go stale),
  # with the modifier mask turned back into names, plus the few things xremap adds that
  # Hyprland cannot see.
  cheatsheet = pkgs.writeShellScript "keys-cheatsheet" ''
    {
      printf '%s\n' \
        "Space (held)         Hyper" \
        "left Ctrl            Hyper" \
        "Copilot, then key    Hyper+key (within 1.5 s)" \
        "Copilot, G           game mode on/off (Hyper off on Space and left Ctrl)" \
        "Caps Lock            Ctrl" \
        ""
      ${pkgs.hyprland}/bin/hyprctl binds -j | ${pkgs.jq}/bin/jq -r '
        def mods: [
          (if .modmask / 64 % 2 >= 1 then "Super" else empty end),
          (if .modmask / 4 % 2 >= 1 then "Ctrl" else empty end),
          (if .modmask / 8 % 2 >= 1 then "Alt" else empty end),
          (if .modmask / 1 % 2 >= 1 then "Shift" else empty end)
        ];
        def modname: if (.modmask % 128 - .modmask % 1) >= 76 and (.modmask / 64 % 2 >= 1) and (.modmask / 4 % 2 >= 1) and (.modmask / 8 % 2 >= 1)
          then (["Hyper"] + (if .modmask % 2 == 1 then ["Shift"] else [] end)) else mods end;
        .[] | select(.key != "") |
        ((modname + [.key]) | join("+")) + "\t" + .dispatcher + (if .arg != "" then " " + .arg else "" end)
      ' | ${pkgs.coreutils}/bin/sort | ${pkgs.coreutils}/bin/expand -t 22
    } | ${pkgs.wofi}/bin/wofi --dmenu --prompt keys --width 760 --height 560 >/dev/null
  '';

  # The bar's own scripts (the items ported from the mac's sketchybar, configs/wm/sketchybar).
  # A TUI in a new ghostty window, as the mac's open_tui.sh does.
  tui = title: cmd: "${lib.getExe pkgs.ghostty} --title=${title} -e ${cmd}";
  # Input source: fcitx5 reports 2 when an input method is active (SKK here), 1 when the
  # keys go through as they are. SKK's own kana/latin mode is not visible from outside, so
  # this shows "▽あ" for SKK on and "A" for off, like the mac's ▽ marker.
  imeStatus = pkgs.writeShellScript "bar-ime" ''
    case "$(${pkgs.fcitx5}/bin/fcitx5-remote 2>/dev/null)" in
      2) printf '{"text":"▽あ","class":"skk","tooltip":"SKK"}\n' ;;
      *) printf '{"text":"A","class":"latin","tooltip":"direct input"}\n' ;;
    esac
  '';
  # Services that should always be running in the session (the mac's app_guard). A green
  # check when they are, a warning with the names when not; a click restarts the stopped ones.
  guardUnits = [
    "xremap"
    "hyprpaper"
    "hypridle"
    "mako"
    "darkman"
    "hyprpolkitagent"
    "ssh-tpm-agent.socket" # the service is socket-activated and idle between uses
  ];
  guard = pkgs.writeShellScript "bar-guard" ''
    units="${lib.concatStringsSep " " guardUnits}"
    down=""
    tip=""
    for u in $units; do
      state=$(${pkgs.systemd}/bin/systemctl --user is-active "$u" 2>/dev/null)
      if [ "$state" = active ]; then
        tip="$tip✓ $u"
      else
        tip="$tip✗ $u ($state)"
        down="$down $u"
        [ "$1" = fix ] && ${pkgs.systemd}/bin/systemctl --user restart "$u" 2>/dev/null
      fi
      tip="$tip
    "
    done
    # One line per unit in the tooltip: JSON wants the newlines as the two characters \n.
    tip=$(printf '%s' "$tip" | ${pkgs.gnused}/bin/sed -z 's/\n *$//; s/\n */\\n/g')
    if [ -z "$down" ]; then
      printf '{"text":"󰄬","class":"ok","tooltip":"%s"}\n' "$tip"
    else
      printf '{"text":"󰀦%s","class":"down","tooltip":"%s"}\n' "$down" "$tip"
    fi
  '';
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
  # Hyprland has no settings app of its own, so $mod+comma (Cmd+, on the mac) opens a picker
  # over the per-area GUI tools declared below. What they change lives outside the store
  # (NetworkManager profiles, PipeWire/WirePlumber state, BlueZ pairings, monitors.conf), so
  # it survives a rebuild instead of being overwritten by it. Anything under home-manager's
  # control (GTK theme, keybinds, fonts) stays in nix on purpose: a GUI writing there would
  # either hit a read-only symlink or be reverted on the next switch.
  settingsMenu = pkgs.writeShellScript "settings-menu" ''
    set -eu
    choice=$(printf '%s\n' Sound Wi-Fi Bluetooth Displays \
      | ${pkgs.wofi}/bin/wofi --dmenu --prompt Settings) || exit 0
    case "$choice" in
      Sound) exec ${pkgs.pavucontrol}/bin/pavucontrol ;;
      Wi-Fi) exec ${pkgs.networkmanagerapplet}/bin/nm-connection-editor ;;
      Bluetooth) exec blueman-manager ;; # system-side (services.blueman in hosts/nixos-laptop.nix)
      Displays) exec ${pkgs.nwg-displays}/bin/nwg-displays ;;
    esac
  '';
  # The bar itself (programs.waybar below adds the output and the width).
  bar = {
    layer = "top";
    position = "top";
    height = 30;
    margin-top = 6;
    spacing = 0;
    modules-left = [
      "custom/logo"
      "hyprland/workspaces"
      "hyprland/window"
    ];
    modules-center = [ "clock" ];
    # Right, in the mac bar's order where it has the same things: guard, sleep inhibit,
    # CPU, memory, (disk), what is playing, volume, input source, Bluetooth, Wi-Fi, battery.
    modules-right = [
      "custom/guard"
      "idle_inhibitor"
      "cpu"
      "memory"
      "disk"
      "mpris"
      "pulseaudio"
      "custom/ime"
      "bluetooth"
      "network"
      "battery"
    ];
    # The mac's apple logo: a menu of system monitor / settings / lock. Left click opens
    # the monitor, middle the display settings, right locks the screen.
    "custom/logo" = {
      # A custom module with nothing to run shows nothing, so the glyph is its output:
      # U+F313, the NixOS snowflake in the Nerd Font (written as a code point so it survives
      # editors and terminals that drop private-use characters).
      exec = "printf '\\uf313'";
      interval = "once";
      format = "{}";
      tooltip-format = "click: system monitor · middle: displays · right: lock";
      on-click = tui "System Monitor" (lib.getExe pkgs.bottom);
      on-click-middle = "nwg-displays";
      on-click-right = "${pkgs.systemd}/bin/loginctl lock-session";
    };
    "custom/ime" = {
      exec = imeStatus;
      return-type = "json";
      interval = 1;
      on-click = "${pkgs.fcitx5}/bin/fcitx5-configtool";
    };
    "custom/guard" = {
      exec = guard;
      return-type = "json";
      interval = 15;
      on-click = "${guard} fix";
    };
    # Keep the screen awake (the mac's nosleep): click to toggle; hypridle then neither
    # locks nor suspends while it is on.
    idle_inhibitor = {
      format = "{icon}";
      format-icons = {
        activated = "󰅶";
        deactivated = "󰾪";
      };
      tooltip-format-activated = "sleep inhibited";
      tooltip-format-deactivated = "sleep allowed";
    };
    "hyprland/workspaces" = {
      format = "{id} {windows}";
      format-window-separator = "";
      on-click = "activate";
      sort-by-number = true;
      # Only workspaces that exist (have windows or are active), and only this output's:
      # Hyprland's workspaces belong to a monitor, so each monitor's bar lists its own.
      all-outputs = false;
      # Each window on the workspace as its app's icon. The icons are the ligatures of
      # sketchybar-app-font (the font the SketchyBar rices use: ":firefox:" is the Firefox
      # icon), applied with a Pango span to the icon only. The font also carries a few digits
      # that are parts of ligatures, so it must not be the label's font. Keys are Hyprland
      # window classes (regex); anything unmatched gets the generic app glyph.
      window-rewrite-default = appIcon ":default:";
      window-rewrite = {
        "class<firefox.*>" = appIcon ":firefox:";
        "class<tor-browser.*>" = appIcon ":tor_browser:";
        "class<google-chrome.*|chromium.*>" = appIcon ":google_chrome:";
        "class<com.mitchellh.ghostty>" = appIcon ":ghostty:";
        "class<kitty>" = appIcon ":kitty:";
        "class<com.t3tools.T3Code>" = appIcon ":t3_code:";
        "class<[Cc]ode.*>" = appIcon ":code:";
        "class<steam.*>" = appIcon ":steam:";
        "class<discord.*>" = appIcon ":discord:";
        "class<obsidian>" = appIcon ":obsidian:";
        "class<Slack>" = appIcon ":slack:";
        "class<org.telegram.desktop>" = appIcon ":telegram:";
        "class<mpv>" = appIcon ":mpv:";
        "class<com.obsproject.Studio>" = appIcon ":obsstudio:";
        "class<Bitwarden>" = appIcon ":bit_warden:";
        "class<org.keepassxc.KeePassXC>" = appIcon ":kee_pass_x_c:";
        "class<org.pwmt.zathura>" = appIcon ":preview:";
        "class<calibre.*>" = appIcon ":calibre:";
        "class<thunar|org.gnome.Nautilus|yazi>" = appIcon ":finder:";
        "class<Bitwig.*>" = appIcon ":bitwig_studio:";
        "class<anki>" = appIcon ":anki:";
        "class<kicad.*>" = appIcon ":kicad:";
        "class<Godot.*>" = appIcon ":godot:";
        "class<mscore|MuseScore.*>" = appIcon ":musescore:";
        "class<zotero|Zotero>" = appIcon ":zotero:";
        "class<blender>" = appIcon ":blender:";
        "class<gimp.*>" = appIcon ":gimp:";
        "class<org.inkscape.Inkscape>" = appIcon ":inkscape:";
        "class<libreoffice.*>" = appIcon ":libreoffice:";
        "class<thunderbird>" = appIcon ":thunderbird:";
        "class<pavucontrol|nm-connection-editor|blueman-manager|nwg-displays>" = appIcon ":gear:";
      };
    };
    "hyprland/window" = {
      format = "{initialClass}";
      max-length = 32;
      separate-outputs = true;
      rewrite = {
        "com.mitchellh.ghostty" = "Ghostty";
        "firefox.*" = "Firefox";
        "com.t3tools.T3Code" = "T3 Code";
        "google-chrome.*" = "Chrome";
        "com.obsproject.Studio" = "OBS Studio";
      };
    };
    clock = {
      format = "{:%m/%d %H:%M}";
      tooltip-format = "{:%Y-%m-%d %A}";
      on-click = tui "Calendar" (lib.getExe' pkgs.calcurse "calcurse");
    };
    mpris = {
      # Previous / play-pause / next as in the reference; the buttons are one label, so the
      # clicks are: left play-pause, middle previous, right next.
      format = "󰒮 {status_icon} 󰒭  {dynamic}";
      dynamic-order = [ "title" "artist" ];
      dynamic-separator = " — ";
      dynamic-len = 32;
      status-icons = {
        playing = "󰏤";
        paused = "󰐊";
        stopped = "󰐊";
      };
      interval = 2;
      on-click = "play-pause";
      on-click-middle = "previous";
      on-click-right = "next";
    };
    cpu = {
      format = "󰻠 {usage}%";
      interval = 5;
      on-click = tui "System Monitor" (lib.getExe pkgs.bottom);
    };
    memory = {
      format = "󰍛 {percentage}%";
      tooltip-format = "{used:0.1f} GiB / {total:0.1f} GiB";
      interval = 10;
      on-click = tui "System Monitor" (lib.getExe pkgs.bottom);
    };
    disk = {
      format = "{used} ({percentage_used}%)";
      path = "/";
      interval = 60;
    };
    network = {
      format-wifi = "󰖩 {essid}";
      format-ethernet = "󰈀 {ifname}";
      format-disconnected = "󰖪";
      tooltip-format-wifi = "{essid} ({signalStrength}%)";
      tooltip-format-ethernet = "{ifname}";
      on-click = "nm-connection-editor";
    };
    battery = {
      format = "{icon} {capacity}%";
      format-charging = "󱐋 {capacity}%";
      format-icons = [
        "󰁻"
        "󰁽"
        "󰁿"
        "󰂁"
        "󰁹"
      ];
    };
    pulseaudio = {
      format = "{icon} {volume}%";
      format-muted = "󰖁";
      format-icons.default = [
        "󰕿"
        "󰖀"
        "󰕾"
      ];
      on-click = "pavucontrol";
    };
    bluetooth = {
      format = "󰂯";
      format-disabled = "󰂲";
      format-off = "󰂲";
      format-connected = "󰂱";
      tooltip-format-connected = "{device_enumerate}";
      tooltip-format-enumerate-connected = "{device_alias}";
      on-click = "blueman-manager";
    };
  };
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
    wofi-emoji # emoji picker ($mod+period)
    wl-clipboard # wl-copy / wl-paste, used by the cliphist pipeline
    wl-gammarelay-rs # night light dbus daemon
    brightnessctl # backlight keys
    playerctl # media keys
    wireplumber # wpctl, used by the volume keys
    # GUI settings, reachable from $mod+comma, the launcher, and the waybar modules.
    pavucontrol # audio devices / per-app volume
    networkmanagerapplet # nm-connection-editor (the tray applet is the service below)
    nwg-displays # monitor layout -> ~/.config/hypr/monitors.conf, sourced below
    sketchybar-app-font # the app icons in the bar's workspaces (programs.waybar below)
  ];

  # No tray applets for Wi-Fi and Bluetooth: their stock GTK icons sat next to the bar's
  # Nerd Font pills and looked out of place, and Wi-Fi was already shown twice. Both are
  # pills in waybar instead (network, bluetooth), which open the full tools on click.

  # nwg-displays writes its result here. The file is created empty on first activation so the
  # source line never points at nothing (Hyprland shows a config-error banner for that), and is
  # never overwritten afterwards. Rules for a named output win over the catch-all `monitor`
  # line in settings, so an empty file simply means "preferred, auto".
  home.activation.hyprMonitorsConf = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.xdg.configHome}/hypr"
    [ -e "${config.xdg.configHome}/hypr/monitors.conf" ] || run touch "${config.xdg.configHome}/hypr/monitors.conf"
  '';

  # package = null: use the system Hyprland, HM manages only the config.
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    # settings generated in hyprlang format (pinned explicitly since the default may switch to lua).
    configType = "hyprlang";
    # Appended after settings, so nwg-displays' per-output rules land after the catch-all.
    extraConfig = ''
      source = ${config.xdg.configHome}/hypr/monitors.conf
    '';
    settings = {
      # Hyper: Space held (and the Copilot key as a prefix), from xremap (home/xremap.nix). Not
      # plain Super, so Super+key stays free for the apps, as on the mac (configs/keyboard/karabiner).
      "$mod" = "SUPER CTRL ALT";
      "$terminal" = "ghostty";
      "$menu" = "${launcher} toggle";

      monitor = [
        ",preferred,auto,1"
        # The 4K monitor at 1.5: 2560x1440 logical, so text is the same size as on the panel.
        # nwg-displays' monitors.conf (sourced below) wins over this if it names the output.
        "DP-1,preferred,auto,1.5"
      ];

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
        # Caps Lock is Ctrl (also in hosts/nixos-laptop.nix for the console and greeter).
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
        "SUPER, space, exec, $menu" # Win+Space, like Cmd+Space on the mac
        "$mod, V, togglefloating"
        "$mod, F, fullscreen"
        "$mod, L, exec, hyprlock" # manual lock
        "$mod, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy" # paste from history
        "$mod, period, exec, wofi-emoji" # emoji picker, like Cmd+Ctrl+Space on the mac
        "$mod, slash, exec, ${cheatsheet}" # every keybind, searchable
        "$mod, Escape, exec, wlogout" # power menu
        "$mod, comma, exec, ${settingsMenu}" # settings picker (Cmd+, on the mac)
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
  xdg.configFile."wofi/launcher".source = launcher;
  programs.wofi = {
    enable = true;
    settings = {
      width = 640;
      height = 420;
      location = "center";
      allow_markup = true;
      insensitive = true;
      hide_scroll = true;
      prompt = "";
      allow_images = true; # app icons in the list
      image_size = 20;
    };
    # The same slab as the bar and the notifications: base at 92 %, a thin hlMed line, 12px
    # corners, the bar's font. Stylix's sheet had the colours but stock shapes.
    style = lib.mkForce ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
      }
      window {
        background-color: alpha(#${c.base}, 0.92);
        border: 1px solid alpha(#${c.hlMed}, 0.9);
        border-radius: 12px;
        color: #${c.text};
      }
      #outer-box { margin: 10px; }
      #input {
        background-color: alpha(#${c.surface}, 0.9);
        color: #${c.text};
        border: 1px solid alpha(#${c.hlMed}, 0.9);
        border-radius: 8px;
        padding: 6px 10px;
        margin-bottom: 8px;
      }
      #input:focus { border-color: #${c.iris}; }
      #entry {
        padding: 6px 10px;
        border-radius: 8px;
        color: #${c.subtle};
      }
      #entry:selected {
        background-color: alpha(#${c.overlay}, 0.9);
        color: #${c.text};
      }
      #entry:selected #text { color: #${c.text}; }
      #entry image { margin-right: 8px; }
    '';
  };

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
      # Fingerprint and password side by side: hyprlock asks fprintd directly (pam_fprintd is off
      # for hyprlock in hosts/nixos-laptop.nix), so touching the sensor unlocks while the password
      # field stays usable.
      auth.fingerprint = {
        enabled = true;
        ready_message = "指紋またはパスワード";
        present_message = "読み取り中…";
      };

      # The ASCII hands, as on the desktop, a touch darker so the clock reads.
      background = [
        {
          path = "${lockWallpaper}";
          brightness = "0.7";
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
        # What the fingerprint reader is doing (ready / reading / retry), under the field.
        {
          text = "$FPRINTPROMPT";
          font_size = 13;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(${c.muted})";
          position = "0, -100";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          # The bar's slab: 12px corners, thin hlMed line, iris when it has focus.
          size = "320, 44";
          rounding = 12;
          outline_thickness = 1;
          outer_color = "rgb(${c.hlMed})";
          inner_color = "rgba(${c.base}eb)";
          font_color = "rgb(${c.text})";
          font_family = "JetBrainsMono Nerd Font";
          check_color = "rgb(${c.foam})";
          fail_color = "rgb(${c.love})";
          capslock_color = "rgb(${c.gold})";
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
      # Same slab as the bar and the launcher; sits under the bar at the top right.
      font = "JetBrainsMono Nerd Font 12";
      background-color = "#${c.base}eb";
      text-color = "#${c.text}";
      border-color = "#${c.hlMed}e6";
      border-size = 1;
      border-radius = 12;
      padding = "10,14";
      margin = "8";
      width = 380;
      anchor = "top-right";
      outer-margin = "44,8,0,0"; # below the bar (6 + 30 + 8)
      default-timeout = 5000;
      icons = true;
      max-icon-size = 32;
      "urgency=high" = {
        border-color = "#${c.love}";
        default-timeout = 0;
      };
    };
  };

  # Icon theme for GTK apps (stylix's gtk target sets the widget theme but no icon theme,
  # so only hicolor was there and many apps had no icon).
  gtk.iconTheme = {
    name = "Papirus-Dark";
    package = pkgs.papirus-icon-theme;
  };

  # status bar
  # After the yabai/SketchyBar rice at reddit.com/r/unixporn/comments/1x2zwou: one rounded
  # bar floating a little below the top edge, about four fifths of the screen wide, with
  # three groups and air between them. Left: the workspaces, each as its number and the
  # icons of the windows on it, then the focused app's name. Centre: the clock. Right: what
  # is playing, CPU, memory, disk, Wi-Fi, battery. No tray: the only things that used it
  # (fcitx5, LibrePods) have their own item or launcher entry. Monochrome on
  # purpose: text and subtle from the palette, accents kept for warnings.
  #
  # `width` is in pixels, so there are two bars with the same content: mainBar for the
  # 1920-wide panel, and extBar, four fifths of the 4K monitor at scale 1.5, for anything else.
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.mainBar = bar // {
      output = [ "eDP-1" ];
      width = 1520;
    };
    settings.extBar = bar // {
      output = [
        "!eDP-1"
        "*" # star after the exclusions: every other output
      ];
      width = 2048; # four fifths of the 4K monitor's 2560 logical pixels (scale 1.5, above)
    };
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
        /* waybar draws a 1px halo on every widget unless this is cleared */
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      /* The bar window is the pill: fixed width (settings), rounded, slightly translucent. */
      window#waybar {
        background: alpha(#${c.base}, 0.92);
        border: 1px solid alpha(#${c.hlMed}, 0.9);
        border-radius: 12px;
        color: #${c.text};
      }
      .modules-left { padding-left: 10px; }
      .modules-right { padding-right: 14px; }

      #custom-logo,
      #workspaces,
      #window,
      #clock,
      #custom-guard,
      #idle_inhibitor,
      #mpris,
      #cpu,
      #memory,
      #disk,
      #network,
      #battery,
      #pulseaudio,
      #custom-ime,
      #bluetooth {
        padding: 0 9px;
      }

      #custom-logo {
        color: #${c.text};
        font-size: 15px;
        padding: 0 6px 0 2px;
      }

      /* "1 <icons>" per workspace, spaced out; the focused one is underlined. */
      #workspaces { padding: 0; }
      #workspaces button {
        color: #${c.subtle};
        padding: 0 9px;
        border-bottom: 2px solid transparent;
        transition: color 150ms ease, border-color 150ms ease;
      }
      #workspaces button.active {
        color: #${c.text};
        border-bottom: 2px solid #${c.text};
      }
      #workspaces button.empty { color: #${c.muted}; }
      #workspaces button:hover { color: #${c.text}; }
      #workspaces button.urgent { color: #${c.love}; }

      #window {
        color: #${c.text};
        padding-left: 14px;
      }
      window#waybar.empty #window { padding: 0; }

      #clock { color: #${c.text}; }

      /* Readings are quiet; accents are kept for the states worth noticing. */
      #mpris,
      #cpu,
      #memory,
      #disk,
      #network,
      #battery,
      #pulseaudio,
      #bluetooth { color: #${c.subtle}; }
      #mpris { color: #${c.muted}; }
      #mpris.playing { color: #${c.subtle}; }
      #battery.warning  { color: #${c.gold}; }
      #battery.critical { color: #${c.love}; }
      #battery.charging { color: #${c.foam}; }
      #network.disconnected { color: #${c.love}; }
      #bluetooth.off,
      #bluetooth.disabled { color: #${c.muted}; }

      /* The ported mac items. */
      #custom-ime { color: #${c.text}; }
      #custom-ime.latin { color: #${c.subtle}; }
      #idle_inhibitor { color: #${c.muted}; }
      #idle_inhibitor.activated { color: #${c.gold}; }
      #custom-guard.ok { color: #${c.pine}; }
      #custom-guard.down { color: #${c.love}; }

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
