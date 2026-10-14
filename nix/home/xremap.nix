{
  lib,
  pkgs,
  ...
}:
# Keyboard tweaks on the NixOS laptop (HP EliteBook 8 G1i, JIS keyboard), done with xremap (a key
# remapper that sits between the keyboard and the compositor, reading evdev and writing to a uinput
# device). The keyboard is used as a US one (kb_layout us in home/hyprland.nix, so the symbol keys
# already read by US position) and the shortcuts are the apps' own Linux ones (Ctrl+C copies, ...).
# The modifiers sit where the mac has them (configs/keyboard/karabiner/karabiner.ts), so one hand
# shape works on both machines; the shortcuts stay the apps' own Linux ones. xremap does four things:
#
# 1. Lays out the bottom row by distance from Space, as on a MacBook (fn ctrl opt cmd [Space] cmd opt):
#
#      physical:  Ctrl  Fn  Win   Alt  無変換  [Space] 変換    カタカナひらがな  Alt  Copilot
#      logical:   Ctrl  Fn  Ctrl  Alt  Ctrl_R [Space] Ctrl_R  Alt             Alt  (Super prefix)
#      mac:             fn  ctrl  opt  cmd    [Space] cmd     opt
#
#    The keys next to Space are Ctrl, where the mac has Cmd, so Ctrl+C / Ctrl+V / Ctrl+T ... are
#    pressed with the same thumb as Cmd+C / Cmd+V / Cmd+T. They are the right Ctrl, which lets the
#    keymap below tell the thumb (Cmd) from the left Ctrl / Win (the mac's Control). ¥ (next to
#    Backspace) is backslash, where a US board has it; ろ (left of the right Shift) has no US
#    counterpart and is left as it is (xkb gives it no symbol). fcitx5's trigger is Ctrl+Space, on
#    Win+Space like the mac's Control+Space; SKK's own mode keys are letters.
#
# 2. Puts Super, the window manager's modifier (home/niri.nix, home/hyprland.nix), on Caps Lock, where
#    the mac has Hyper (Cmd+Ctrl+Opt) from Karabiner, so the window-manager keys match OmniWM's.
#
#      - Caps Lock is Super. Before, it was the physical left Ctrl, and before that Space held; a
#        dual-role Space turned every slow or overlapping Space into a window-manager shortcut.
#      - The Copilot key is a prefix: press it, then within copilotTimeout press a key, and Super+<key>
#        (or Super+Shift+<key>) is sent. The firmware sends Copilot as the chord LeftMeta+LeftShift+F23,
#        pressed and released in the same instant no matter how long the key is held (kernel 6.18
#        decodes the F23), so it cannot be a held modifier, only a prefix. Nothing happens if no key
#        follows.
#
# 3. Gives the thumb Ctrl the two mac meanings Linux has on another key:
#
#      - thumb+Space is Super+Space, the launcher, like Cmd+Space (a plain Ctrl+Space toggles fcitx5);
#      - in terminals, thumb+C / thumb+V copy and paste (Ctrl+Shift+C / V), like Cmd+C / Cmd+V, while
#        the left Ctrl still sends Ctrl+C (interrupt) and Ctrl+V (Neovim's block selection).
#
#    Nothing else is translated. An earlier version re-rolled every Cmd+key per application (and
#    Ctrl+A/E/... as text-editing keys outside terminals); that needed upkeep for each app and was
#    dropped. Cmd+arrow (line start / end) and Opt+arrow (word) are not carried over.
#
# 4. Keeps games playable: Caps Lock is a plain Ctrl (xkb's ctrl:nocaps, below) instead of Super
#
#      - in game windows (Steam games are the class steam_app_<id>; gamescope is the compositor they run
#        inside, also as the Steam Deck-style session), and
#      - in "game" mode, toggled by Copilot then G for games xremap cannot recognise, with a mako
#        notification each way. Copilot stays a Super prefix in game mode, so the window manager is
#        still reachable.
#
#    The bottom-row modmap stays on in both cases, so the row does not change meaning mid-game.
#
# Caps Lock as Ctrl where xremap does not run (greeter, TTYs, games) is xkb's job (ctrl:nocaps in
# home/hyprland.nix, home/niri.nix and hosts/nixos-laptop.nix); xremap reads the key before xkb.
let
  wmKey = "Super_L";

  # Keys that Copilot-then-key turns into Super+key: everything home/niri.nix binds on Mod, plus the
  # rest of the main block so a new bind does not need a change here.
  copilotKeys = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz0123456789" ++ [
    "enter"
    "esc"
    "tab"
    "backspace"
    "space"
    "left"
    "right"
    "up"
    "down"
    "minus"
    "equal"
    "comma"
    "dot"
    "slash"
    "semicolon"
    "apostrophe"
    "grave"
    "leftbrace"
    "rightbrace"
  ];

  # How long after pressing Copilot the next key is still taken as Super+key.
  copilotTimeout = 1500;

  # Terminal window classes, where Ctrl+C is an interrupt rather than copy.
  terminals = [ "com.mitchellh.ghostty" ];

  # Window classes where Caps Lock stays a plain Ctrl (xremap --list-windows prints the class).
  games = [
    "/^steam_app_/"
    "gamescope"
  ];

  notify = summary: body: [
    "${pkgs.libnotify}/bin/notify-send"
    "-a"
    "xremap"
    summary
    body
  ];

  # The Copilot prefix table; G toggles game mode instead of sending Super+G, so there is one table per
  # mode, differing only in what G does.
  copilotTable =
    nextMode: notice:
    lib.listToAttrs (
      lib.concatMap (k: [
        (lib.nameValuePair k "Super-${k}")
        (lib.nameValuePair "Shift-${k}" "Super-Shift-${k}")
      ]) copilotKeys
    )
    // {
      g = [
        { set_mode = nextMode; }
        { launch = notice; }
      ];
    };

  copilotPrefix = mode: nextMode: notice: {
    name = "Copilot, then key, is Super+key (${mode} mode)";
    inherit mode;
    exact_match = true;
    remap."C-Shift_L-F23" = {
      timeout_millis = copilotTimeout;
      remap = copilotTable nextMode notice;
    };
  };

  config = {
    default_mode = "default";

    modmap = [
      {
        name = "bottom row";
        remap = {
          Super_L = "Control_L";
          Muhenkan = "Control_R";
          Henkan = "Control_R";
          Katakanahiragana = "Alt_R";
          Yen = "backslash";
        };
      }
      {
        name = "Super on Caps Lock (not in games)";
        mode = "default";
        application.not = games;
        remap.CapsLock = wmKey;
      }
    ];

    keymap = [
      {
        name = "Thumb Ctrl+Space is the launcher, like Cmd+Space";
        remap."Ctrl_R-space" = "Super-space";
      }
      {
        name = "Thumb Ctrl+C / V copy and paste in terminals, like Cmd+C / V";
        application.only = terminals;
        remap = {
          "Ctrl_R-c" = "C-Shift-c";
          "Ctrl_R-v" = "C-Shift-v";
        };
      }
      # Copilot arrives as Meta+Shift_L+F23 (see the header); after the modmap the Meta is Ctrl. The
      # nested remap is xremap's prefix-key form: it stays armed for timeout_millis and applies to the
      # next key only. exact_match so that the entry is not also taken for F23 with other modifiers.
      (copilotPrefix "default" "game" (
        notify "Game mode on" "Caps Lock is a plain Ctrl. Copilot, G turns it off."
      ))
      (copilotPrefix "game" "default" (notify "Game mode off" "Caps Lock is Super again."))
    ];
  };

  configFile = (pkgs.formats.yaml { }).generate "xremap.yml" config;

  # The window-aware build for whichever compositor the session runs (lib/wm-session.nix): the
  # game-mode classes above are matched against the focused window, which only that
  # compositor's IPC can name. The unit starts after graphical-session.target, which niri only
  # reaches once NIRI_SOCKET is in the user manager's environment; anything else gets the
  # Hyprland build, as before niri.
  xremap = pkgs.writeShellScript "xremap-session" ''
    if ${import ../lib/wm-session.nix { inherit pkgs; }}/bin/wm-session is niri; then
      exec ${lib.getExe pkgs.xremap.niri} "$@"
    fi
    exec ${lib.getExe pkgs.xremap.hyprland} "$@"
  '';
in
{
  # Needs /dev/input/event* and /dev/uinput: the input and uinput groups (hosts/nixos-laptop.nix).
  # It runs in the session rather than as root so that it can ask niri / Hyprland which window is focused.
  systemd.user.services.xremap = {
    Unit = {
      Description = "xremap (mac-like bottom row; Super on Caps Lock and the Copilot key; game mode)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      # --watch=device picks up keyboards plugged in later.
      ExecStart = lib.escapeShellArgs [
        xremap
        "--watch=device"
        configFile
      ];
      # The window manager's modifier lives here, so it should not stay down.
      Restart = "always";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
