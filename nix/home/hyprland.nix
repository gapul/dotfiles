{
  config,
  lib,
  pkgs,
  ...
}:
# Hyprland user config (Rick). Imported only on nixos-laptop.
# The system side (hosts/nixos-laptop.nix) provides PAM/session for
# programs.hyprland / hyprlock; this side manages appearance and keybinds.
# niri is the default session now (home/niri.nix, imported below); Hyprland stays selectable
# in the greeter. Everything here except wayland.windowManager.hyprland serves both sessions,
# and the compositor-specific commands go through wm-session (lib/wm-session.nix).
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
  wmSession = "${import ../lib/wm-session.nix { inherit pkgs; }}/bin/wm-session";
  # An app icon for the bar: a sketchybar-app-font ligature, in that font (see the workspaces
  # module in programs.waybar below).
  appIcon = name: "<span font_family='sketchybar-app-font' size='large' rise='-3500'>${name}</span>";

  # The power menu's icons: Nerd Font glyphs drawn into PNGs in the palette's text colour
  # (code points, so the private-use characters survive any editor; the UTF-8 locale is
  # needed because the build sandbox's C locale makes bash print the escape literally).
  wlogoutIcons =
    let
      glyphs = {
        lock = "f033e";
        suspend = "f04b2";
        logout = "f0343";
        reboot = "f0709";
        shutdown = "f0425";
        hibernate = "f02ca";
      };
      font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf";
    in
    pkgs.runCommand "wlogout-icons" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
      mkdir -p $out
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: cp:
          "magick -background none -fill '#${c.text}' -font ${font} -pointsize 320 label:\"$(LC_ALL=C.UTF-8 printf '\\U000${cp}')\" -trim +repage -gravity center -extent 400x400 PNG32:$out/${name}.png"
        ) glyphs
      )}
    '';

  # The hands, cropped from the wallpaper, as the terminal greeting's picture.
  fastfetchLogo =
    pkgs.runCommand "fastfetch-logo.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        magick ${lockWallpaper} -gravity center -crop 2600x1100+0+0 +repage -resize 880x -quality 92 PNG24:$out
      '';

  # The dark palette's wallpaper, for the lock screen (hyprlock's config is static, and a
  # dark lock screen is right at any hour).
  lockWallpaper = import ../lib/wallpaper.nix {
    inherit pkgs;
    p = (builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json)).palettes.rose-pine;
    name = "rose-pine";
  };

  # Super+/ : every keybind, searchable. Read from Hyprland itself (so it cannot go stale),
  # with the modifier mask turned back into names, plus the few things xremap adds that
  # Hyprland cannot see.
  cheatsheet = pkgs.writeShellScript "keys-cheatsheet" ''
    {
      printf '%s\n' \
        "left Ctrl            Super" \
        "Copilot, then key    Super+key (within 1.5 s)" \
        "Copilot, G           game mode on/off (left Ctrl back to Ctrl)" \
        "Caps Lock            Ctrl" \
        ""
      ${pkgs.hyprland}/bin/hyprctl binds -j | ${pkgs.jq}/bin/jq -r '
        def mods: [
          (if .modmask / 64 % 2 >= 1 then "Super" else empty end),
          (if .modmask / 4 % 2 >= 1 then "Ctrl" else empty end),
          (if .modmask / 8 % 2 >= 1 then "Alt" else empty end),
          (if .modmask / 1 % 2 >= 1 then "Shift" else empty end)
        ];
        .[] | select(.key != "") |
        ((mods + [.key]) | join("+")) + "\t" + .dispatcher + (if .arg != "" then " " + .arg else "" end)
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
    "awww"
    "fcitx5"
    "azoo-key-skkserv"
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
  # The region goes to satty for arrows, boxes and blur; Enter (or the copy button) puts the
  # result on the clipboard and closes it, Ctrl+S also saves it under ~/Pictures/Screenshots.
  screenshotRegion = pkgs.writeShellScript "screenshot-region" ''
    set -euo pipefail
    geometry=$(${pkgs.slurp}/bin/slurp -d) || exit 0
    ${pkgs.grim}/bin/grim -g "$geometry" - | ${pkgs.satty}/bin/satty --filename - \
      --copy-command "${pkgs.wl-clipboard}/bin/wl-copy --type image/png" --early-exit \
      --init-tool arrow --output-filename "$HOME/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png"
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
    # Both compositors' modules: waybar disables the ones whose compositor is not running.
    modules-left = [
      "custom/logo"
      "hyprland/workspaces"
      "niri/workspaces"
      "hyprland/window"
      "niri/window"
    ];
    modules-center = [ "clock" ];
    # Right, in the mac bar's order where it has the same things: guard, sleep inhibit,
    # CPU, memory, (disk), what is playing, volume, input source, Bluetooth, Wi-Fi, battery.
    modules-right = [
      "custom/guard"
      "cpu"
      "memory"
      "disk"
      "mpris"
      "pulseaudio"
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
    # niri's workspaces are per output and dynamic (there is always one empty one at the end),
    # and the module cannot list the windows on each, so it is the number alone.
    "niri/workspaces" = {
      format = "{index}";
    };
    "niri/window" = {
      format = "{app_id}";
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
      dynamic-order = [
        "title"
        "artist"
      ];
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
      format-wifi = "󰖩";
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
  imports = [
    ./niri.nix
    ./wl-keyboard.nix
    ./waybar-appearance.nix
    ./desktop-appearance.nix
  ];
  # For home/niri.nix, which binds the same scripts.
  _module.args.desktopScripts = { inherit launcher settingsMenu screenshotRegion; };

  # Binaries referenced by the keybinds / exec-once below. Without these the rice
  # is inert: $mod+Return execs a ghostty that is not in the closure, and the
  # night-light / screenshot / clipboard binds silently do nothing.
  home.packages = with pkgs; [
    ghostty # $terminal
    # wofi is not listed here: it is declared through programs.wofi below, because stylix
    # only themes what home-manager knows it manages. As a bare package it kept rendering
    # its stock white sheet in the middle of a dark desktop.
    # hyprpolkitagent is not listed: its unit below runs it from the package directly, and
    # the system's copy (hosts/nixos-laptop.nix) already ships the D-Bus service file; a
    # second copy here made dbus-broker log a duplicate name at every login.
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
    # Hyprland 0.55+ reads a Lua config (hyprland.lua); the hyprlang .conf is deprecated and
    # goes away in 0.57. home-manager renders `settings` as hl.<name>(...) calls: attribute
    # values with `_args` are multi-argument calls, `_var` entries become locals, and
    # mkLuaInline values are raw Lua. Hyprland's API reference: the `hl.meta.lua` stubs in
    # the package (share/hypr/stubs) and https://wiki.hypr.land/Configuring/Start/.
    configType = "lua";
    # Curves before the animations that name them, options before the binds that use them.
    importantPrefixes = [
      "curve"
      "config"
      "monitor"
      "gesture"
      "on"
    ];
    # The overview plugin stays off (its touchpad hooks broke two-finger scrolling,
    # 2026-10-11). To try again: plugins = [ pkgs.hyprlandPlugins.hyprtasking ]; and a bind
    # to hl.dsp "hyprtasking:toggle", then log in afresh and test scrolling.
    settings =
      let
        inherit (lib.generators) mkLuaInline;
        # Super, which xremap also sends for left Ctrl and Copilot-then-key
        # (home/xremap.nix). The same key as niri's Mod (home/niri.nix).
        key = k: mkLuaInline ''mod .. " + ${k}"'';
        shiftKey = k: mkLuaInline ''mod .. " + SHIFT + ${k}"'';
        exec = cmd: mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON cmd})";
        bind = k: dsp: {
          _args = [
            k
            dsp
          ];
        };
        bindOpts = k: dsp: opts: {
          _args = [
            k
            dsp
            opts
          ];
        };
      in
      {
        mod._var = "SUPER";
        terminal._var = "ghostty";
        menu._var = "${launcher} toggle";

        monitor = [
          {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = 1;
          }
          # The 4K monitor at 1.5: 2560x1440 logical, so text is the same size as on the panel.
          # nwg-displays' monitors.conf (read in extraConfig below) wins over this if it names
          # the output.
          {
            output = "DP-1";
            mode = "preferred";
            position = "auto";
            scale = 1.5;
          }
        ];

        config = {
          # Hyprland's stock background (its logo on a gradient) and the splash one-liner are
          # off; background_color is what shows between the compositor starting and awww
          # painting the wallpaper.
          misc = {
            background_color = "rgb(${c.base})";
            force_default_wallpaper = 0;
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            # If hyprlock dies while the session is locked, the compositor keeps holding the
            # lock and the screen stays black; with this on, a fresh hyprlock takes the
            # orphaned lock over. Seen for real: a rebuild restarted the session's units out
            # from under a running hyprlock and left the machine unusable except over ssh.
            allow_session_lock_restore = true;
          };
          input = {
            kb_layout = "us"; # use "jp" for a JIS layout
            # Caps Lock is Ctrl (also in hosts/nixos-laptop.nix for the console and greeter).
            kb_options = "ctrl:nocaps";
            follow_mouse = 1;
            touchpad = {
              natural_scroll = true;
              tap_to_click = true;
            };
          };
          general = {
            gaps_in = 5;
            gaps_out = 10;
            border_size = 2;
            col = {
              active_border = {
                colors = [
                  "rgb(${c.iris})"
                  "rgb(${c.foam})"
                ];
                angle = 45;
              };
              inactive_border = "rgb(${c.overlay})";
            };
            layout = "dwindle";
          };
          decoration = {
            rounding = 8;
            blur = {
              enabled = true;
              size = 6;
              passes = 2;
            };
            # Unfocused windows a shade darker, and a soft shadow under every window, so the
            # focused one reads at a glance.
            dim_inactive = true;
            dim_strength = 0.12;
            shadow = {
              enabled = true;
              range = 24;
              render_power = 3;
              color = "rgba(${c.base}cc)";
            };
          };
          animations.enabled = true;
        };

        curve = [
          # ease-out, for things settling
          {
            _args = [
              "ease"
              {
                type = "bezier";
                points = [
                  [
                    0.16
                    1
                  ]
                  [
                    0.3
                    1
                  ]
                ];
              }
            ];
          }
          # a touch of overshoot, for things appearing
          {
            _args = [
              "snap"
              {
                type = "bezier";
                points = [
                  [
                    0.2
                    0.9
                  ]
                  [
                    0.1
                    1.05
                  ]
                ];
              }
            ];
          }
        ];
        animation = [
          {
            leaf = "windows";
            enabled = true;
            speed = 5;
            bezier = "snap";
            style = "popin 85%";
          }
          {
            leaf = "windowsOut";
            enabled = true;
            speed = 4;
            bezier = "ease";
            style = "popin 85%";
          }
          {
            leaf = "fade";
            enabled = true;
            speed = 6;
            bezier = "ease";
          }
          {
            leaf = "layers";
            enabled = true;
            speed = 4;
            bezier = "ease";
            style = "fade";
          }
          {
            leaf = "border";
            enabled = true;
            speed = 8;
            bezier = "ease";
          }
          {
            leaf = "workspaces";
            enabled = true;
            speed = 5;
            bezier = "ease";
            style = "slide";
          }
        ];

        # Touchpad: three fingers sideways switch workspaces. Four fingers belong to fusuma
        # (home/linux-gui.nix).
        gesture = {
          fingers = 3;
          direction = "horizontal";
          action = "workspace";
        };

        # Only things that have no systemd user unit of their own: hypridle / waybar / mako /
        # awww / fcitx5 are started by their home-manager services (fcitx5's unit is in
        # home/fcitx5-skk.nix, ordered after the skkserv); listing them here as well would
        # launch a second copy of each.
        on = {
          _args = [
            "hyprland.start"
            (mkLuaInline ''
              function()
                hl.exec_cmd("wl-paste --watch cliphist store") -- clipboard history
                hl.exec_cmd("wl-gammarelay-rs") -- dbus daemon for night light
              end'')
          ];
        };

        bind = [
          (bind (key "Return") (mkLuaInline "hl.dsp.exec_cmd(terminal)"))
          (bind (key "Q") (mkLuaInline "hl.dsp.window.close()"))
          (bind (shiftKey "M") (mkLuaInline "hl.dsp.exit()")) # quit Hyprland
          (bind (key "E") (mkLuaInline ''hl.dsp.exec_cmd(terminal .. " -e yazi")'')) # file manager
          (bind (key "R") (mkLuaInline "hl.dsp.exec_cmd(menu)"))
          (bind "SUPER + space" (mkLuaInline "hl.dsp.exec_cmd(menu)")) # Win+Space, like Cmd+Space
          (bind (key "V") (mkLuaInline ''hl.dsp.window.float({ action = "toggle" })''))
          (bind (key "F") (mkLuaInline "hl.dsp.window.fullscreen()"))
          (bind (key "L") (exec "hyprlock")) # manual lock
          (bind (key "C") (exec "cliphist list | wofi --dmenu | cliphist decode | wl-copy")) # paste from history
          (bind (key "period") (exec "wofi-emoji")) # emoji picker, like Cmd+Ctrl+Space on the mac
          (bind (key "slash") (exec "${cheatsheet}")) # every keybind, searchable
          # Power menu. Three tiles a row with a wide margin, so the tiles are not the whole screen.
          (bind (key "Escape") (
            exec "wlogout --buttons-per-row 3 --margin 240 --column-spacing 16 --row-spacing 16"
          ))
          (bind (key "comma") (exec "${settingsMenu}")) # settings picker (Cmd+, on the mac)
          # screenshot / color picker
          (bind (key "P") (exec "${screenshotRegion}")) # region -> satty -> clipboard
          (bind (shiftKey "P") (exec "hyprshot -m window -o ${config.xdg.userDirs.pictures}/Screenshots")) # window -> save
          (bind (shiftKey "C") (exec "hyprpicker -a")) # pick a color and copy
          # night light (switch color temperature 4000K / 6500K)
          (bind (shiftKey "N") (
            exec "busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 4000"
          ))
          (bind (shiftKey "D") (
            exec "busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 6500"
          ))
          # move focus
          (bind (key "left") (mkLuaInline ''hl.dsp.focus({ direction = "left" })''))
          (bind (key "right") (mkLuaInline ''hl.dsp.focus({ direction = "right" })''))
          (bind (key "up") (mkLuaInline ''hl.dsp.focus({ direction = "up" })''))
          (bind (key "down") (mkLuaInline ''hl.dsp.focus({ direction = "down" })''))
          # move / resize windows with the mouse
          (bindOpts (key "mouse:272") (mkLuaInline "hl.dsp.window.drag()") { mouse = true; })
          (bindOpts (key "mouse:273") (mkLuaInline "hl.dsp.window.resize()") { mouse = true; })
          # volume / brightness (work while locked, repeat while held)
          (bindOpts "XF86AudioRaiseVolume" (exec "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+") {
            locked = true;
            repeating = true;
          })
          (bindOpts "XF86AudioLowerVolume" (exec "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") {
            locked = true;
            repeating = true;
          })
          (bindOpts "XF86MonBrightnessUp" (exec "brightnessctl set 5%+") {
            locked = true;
            repeating = true;
          })
          (bindOpts "XF86MonBrightnessDown" (exec "brightnessctl set 5%-") {
            locked = true;
            repeating = true;
          })
          (bindOpts "XF86AudioMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") { locked = true; })
          (bindOpts "XF86AudioPlay" (exec "playerctl play-pause") { locked = true; })
          (bindOpts "XF86AudioNext" (exec "playerctl next") { locked = true; })
          (bindOpts "XF86AudioPrev" (exec "playerctl previous") { locked = true; })
        ]
        # Super+1..9,0 switch to workspaces 1..10; with Shift, move the window there.
        ++ builtins.concatLists (
          builtins.genList (
            i:
            let
              n = toString (i + 1);
              k = toString (if i + 1 == 10 then 0 else i + 1);
            in
            [
              (bind (key k) (mkLuaInline "hl.dsp.focus({ workspace = ${n} })"))
              (bind (shiftKey k) (mkLuaInline "hl.dsp.window.move({ workspace = ${n} })"))
            ]
          ) 10
        );
      };
    # nwg-displays writes its result as hyprlang ("monitor=NAME,MODE,POSITION,SCALE[,...]"),
    # which the Lua config cannot `source`; read it here and hand each line to hl.monitor, so
    # a named output still wins over the catch-all above. (The file is created empty on
    # first activation, see home.activation.hyprMonitorsConf.)
    extraConfig = ''
      do
        local path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/monitors.conf"
        local f = io.open(path)
        if f then
          for line in f:lines() do
            local spec = line:match("^%s*monitor%s*=%s*(.-)%s*$")
            if spec and spec ~= "" then
              local parts = {}
              for part in (spec .. ","):gmatch("%s*([^,]*)%s*,") do parts[#parts + 1] = part end
              if parts[2] == "disable" then
                hl.monitor({ output = parts[1], disabled = true })
              else
                hl.monitor({
                  output = parts[1],
                  mode = (parts[2] ~= "" and parts[2]) or "preferred",
                  position = (parts[3] ~= "" and parts[3]) or "auto",
                  scale = (parts[4] ~= "" and parts[4]) or "auto",
                })
              end
            end
          end
          f:close()
        end
      end
    '';
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

  # The wallpaper is painted by awww (home/darkman.nix), which can cross-fade between the
  # day and night images; hyprpaper only swapped them.
  services.hyprpaper.enable = false;

  # Power menu ($mod+Escape). With no style.css of its own it fell back to the package's
  # stock sheet — near-black tiles with a #3700B3 highlight, the one screen off the palette.
  # Only the style is written: the stock layout (actions and l/e/u/h/s/r keys) is kept, and
  # the icons still come from the package, as the stock sheet had them.
  programs.wlogout = {
    enable = true;
    # Six tiles: a big glyph (rendered from the bar's font into an image at build time, since
    # a GTK label cannot size its icon apart from its word) and a word under it, in the
    # palette: the same slab as the bar.
    layout =
      let
        tile = label: text: action: keybind: {
          inherit
            label
            text
            action
            keybind
            ;
        };
      in
      [
        (tile "lock" "Lock" "loginctl lock-session" "l")
        (tile "suspend" "Suspend" "systemctl suspend" "u")
        (tile "logout" "Log out" "${wmSession} exit" "e")
        (tile "reboot" "Reboot" "systemctl reboot" "r")
        (tile "shutdown" "Shut down" "systemctl poweroff" "s")
        (tile "hibernate" "Hibernate" "systemctl hibernate" "h")
      ];
    style =
      let
        icon = name: "image(url(\"${wlogoutIcons}/${name}.png\"))";
      in
      ''
        * {
          background-image: none;
          box-shadow: none;
          font-family: "JetBrainsMono Nerd Font";
          font-size: 22px;
        }
        window { background-color: alpha(#${c.base}, 0.75); }
        button {
          margin: 10px;
          border-radius: 12px;
          border: 1px solid alpha(#${c.hlMed}, 0.9);
          color: #${c.subtle};
          background-color: alpha(#${c.base}, 0.92);
          background-repeat: no-repeat;
          background-position: center 32%;
          background-size: 38%;
          transition: all 150ms ease;
        }
        button:focus, button:active, button:hover {
          color: #${c.text};
          border-color: #${c.iris};
          background-color: alpha(#${c.overlay}, 0.9);
          outline-style: none;
        }
        #shutdown:focus, #shutdown:hover, #reboot:focus, #reboot:hover { border-color: #${c.love}; }
        #lock { background-image: ${icon "lock"}; }
        #suspend { background-image: ${icon "suspend"}; }
        #logout { background-image: ${icon "logout"}; }
        #reboot { background-image: ${icon "reboot"}; }
        #shutdown { background-image: ${icon "shutdown"}; }
        #hibernate { background-image: ${icon "hibernate"}; }
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
        ready_message = "Fingerprint or password";
        present_message = "Reading…";
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
        # The wallpaper daemon came back from suspend without its buffers (bare screen until
        # something repainted); starting it afresh repaints within a second.
        after_sleep_cmd = "${wmSession} dpms on; systemctl --user try-restart awww.service";
      };
      listener = [
        {
          timeout = 300; # lock after 5 minutes (only with the lid open, see whenLidOpen)
          on-timeout = whenLidOpen "loginctl lock-session";
        }
        {
          timeout = 360; # turn off screen after 6 minutes
          on-timeout = "${wmSession} dpms off";
          on-resume = "${wmSession} dpms on";
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

  # Cursor: Rosé Pine's, through GTK, X and Hyprland (home-manager exports the XCURSOR
  # variables into the session). The greeter uses the same one (hosts/nixos-laptop.nix).
  home.pointerCursor = {
    enable = true;
    package = pkgs.rose-pine-cursor;
    name = "BreezeX-RosePine-Linux";
    size = 24;
    gtk.enable = true;
    # The theme still reaches every toolkit through XDG_DATA_DIRS / XCURSOR_PATH; only the
    # legacy ~/.icons copy is dropped.
    dotIcons.enable = false;
  };

  # A new terminal opens on the machine's card: the hands, and the few facts worth a glance,
  # in the palette. Only in ghostty and not inside tmux, so scripts and ssh sessions stay quiet.
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = fastfetchLogo;
        type = "kitty-direct";
        width = 44;
        height = 14;
        padding = {
          top = 1;
          right = 3;
        };
      };
      display = {
        separator = "  ";
        color = {
          keys = "magenta";
          title = "blue";
        };
      };
      modules = [
        "title"
        "separator"
        {
          type = "os";
          key = "󰣇 os";
        }
        {
          type = "kernel";
          key = "󰌽 kernel";
        }
        {
          type = "wm";
          key = "󰖲 wm";
        }
        {
          type = "uptime";
          key = "󰔟 up";
        }
        {
          type = "packages";
          key = "󰏖 pkgs";
        }
        {
          type = "cpu";
          key = "󰻠 cpu";
        }
        {
          type = "memory";
          key = "󰍛 mem";
        }
        {
          type = "disk";
          key = "󰋊 disk";
        }
        {
          type = "battery";
          key = "󰁹 bat";
        }
        "break"
        "colors"
      ];
    };
  };
  programs.zsh.initContent = lib.mkOrder 1500 ''
    if [[ -o interactive && -z "$TMUX" && "$TERM_PROGRAM" == ghostty && -z "$SSH_CONNECTION" ]]; then
      ${lib.getExe pkgs.fastfetch}
    fi
  '';

  # Scrolling with the mac's feel, where the toolkit allows it. Wayland has no system-wide
  # inertia (libinput reports finger motion, each app decides what to do after the fingers
  # lift): GTK apps coast on their own, Firefox coasts through its own physics (set a little
  # lower friction here, and the mac-like curve for wheel steps), Electron/Chromium apps do
  # not coast on Linux at all.
  programs.firefox.profiles.dev.settings = {
    "apz.gtk.kinetic_scroll.enabled" = true;
    # The coast after the fingers lift: friction well under the default 0.002, so a flick
    # carries on the way it does on the mac, and a lower stop threshold so it tails off
    # instead of halting.
    "apz.fling_friction" = "0.001";
    "apz.fling_stopped_threshold" = "0.005";
    "apz.fling_min_velocity_threshold" = "0.3";
    # Wheel/step scrolling on a spring-damper curve tuned towards the mac's: quick start,
    # long settle.
    "general.smoothScroll" = true;
    "general.smoothScroll.msdPhysics.enabled" = true;
    "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 120;
    "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 1250;
    "general.smoothScroll.msdPhysics.regularSpringConstant" = 1000;
    "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 12;
    "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = "1.3";
    "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 2000;
    "general.smoothScroll.currentVelocityWeighting" = "0.15";
    "general.smoothScroll.stopDecelerationWeighting" = "0.6";
    "mousewheel.min_line_scroll_amount" = 10;

    # Japanese on pages whose web font has no kana or kanji: Firefox on Linux falls back to
    # its *serif* default for ja (Spotify's track names came out in a mincho), where the
    # mac's default is the gothic. The families themselves are modules/home/firefox.nix's.
    "font.default.ja" = "sans-serif";
    "font.name.monospace.ja" = "Noto Sans Mono CJK JP";
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
