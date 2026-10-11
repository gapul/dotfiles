{
  lib,
  pkgs,
  ...
}:
# Keyboard tweaks on the NixOS laptop (HP EliteBook 8 G1i, JIS keyboard), done with xremap (a key
# remapper that sits between the keyboard and the compositor, reading evdev and writing to a uinput
# device). The keyboard is used as a US one (kb_layout us in home/hyprland.nix, so the symbol keys
# already read by US position) and the shortcuts are the apps' own Linux ones (Ctrl+C copies, ...).
# xremap does two things:
#
# 1. Lays out the bottom row. Left to right:
#
#      physical:  Ctrl   Fn  Win   Alt  無変換 [Space] 変換  カタカナひらがな  Alt   Copilot
#      logical:   Hyper  Fn  Ctrl  Win  Alt   [Space] Alt   Win             Ctrl  (Hyper prefix)
#
#    Ctrl / Win / Alt sit next to Space in the US order on both sides, with Hyper at the two ends. ¥
#    (next to Backspace) is backslash, where a US board has it; ろ (left of the right Shift) has no US
#    counterpart and is left as it is (xkb gives it no symbol). fcitx5 does not use any of these keys
#    (its trigger is Ctrl+Space); SKK's own mode keys are letters.
#
# 2. Adds Hyper, the window manager's modifier (home/hyprland.nix), the way Karabiner adds it on the mac
#    (configs/keyboard/karabiner/karabiner.ts):
#
#      - The physical left Ctrl is Hyper (Super+Ctrl+Alt).
#      - Space held is Hyper too; tapped, it is Space.
#      - The Copilot key is a prefix: press it, then within copilotTimeout press a key, and Hyper+<key>
#        (or Hyper+Shift+<key>) is sent. The firmware sends Copilot as the chord LeftMeta+LeftShift+F23,
#        pressed and released in the same instant no matter how long the key is held (kernel 6.18
#        decodes the F23), so it cannot be a held modifier, only a prefix. Nothing happens if no key
#        follows.
#
# 3. Keeps games playable. A game needs Space and left Ctrl held down (jump, crouch) and reacts to the
#    press at once, which the held/alone split above breaks: a held Space would reach the game as Hyper,
#    and a tapped one only on release. So the two Hyper modmaps are off
#
#      - in game windows (Steam games are the class steam_app_<id>; gamescope is the compositor they run
#        inside, also as the Steam Deck-style session), and
#      - in "game" mode, toggled by Copilot then G for games xremap cannot recognise, with a mako
#        notification each way. Copilot stays a Hyper prefix in game mode, so the window manager is
#        still reachable; only the held keys are plain.
#
#    The bottom-row modmap stays on in both cases, so the row does not change meaning mid-game.
#
# Caps Lock as Ctrl is xkb's job (ctrl:nocaps in home/hyprland.nix and hosts/nixos-laptop.nix).
#
# An earlier version re-rolled the modifier row mac-style (無変換/変換 as Cmd, Cmd+key sent as Ctrl+key,
# Ctrl+A/E/... as text-editing keys outside terminals). Linux apps have no Cmd/Ctrl split, so that
# translation had to be maintained per application; it was dropped in favour of the apps' own keys.
let
  hyper = [
    "Super_L"
    "Control_L"
    "Alt_L"
  ];

  # Keys that Copilot-then-key turns into Hyper+key: everything home/hyprland.nix binds on $mod, plus the
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

  # How long after pressing Copilot the next key is still taken as Hyper+key.
  copilotTimeout = 1500;

  # Window classes that get the plain Space and left Ctrl (xremap --list-windows prints the class).
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

  # The Copilot prefix table; G toggles game mode instead of sending Hyper+G, so there is one table per
  # mode, differing only in what G does.
  copilotTable =
    nextMode: notice:
    lib.listToAttrs (
      lib.concatMap (k: [
        (lib.nameValuePair k "Super-C-Alt-${k}")
        (lib.nameValuePair "Shift-${k}" "Super-C-Alt-Shift-${k}")
      ]) copilotKeys
    )
    // {
      g = [
        { set_mode = nextMode; }
        { launch = notice; }
      ];
    };

  copilotPrefix = mode: nextMode: notice: {
    name = "Copilot, then key, is Hyper+key (${mode} mode)";
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
          Alt_L = "Super_L";
          Muhenkan = "Alt_L";
          Henkan = "Alt_R";
          Katakanahiragana = "Super_R";
          Alt_R = "Control_R";
          Yen = "backslash";
        };
      }
      {
        name = "Hyper on left Ctrl and Space held (not in games)";
        mode = "default";
        application.not = games;
        remap = {
          Control_L = hyper;
          Space = {
            held = hyper;
            alone = "Space";
          };
        };
      }
    ];

    keymap = [
      # Copilot arrives as Meta+Shift_L+F23 (see the header); after the modmap the Meta is Ctrl. The
      # nested remap is xremap's prefix-key form: it stays armed for timeout_millis and applies to the
      # next key only. exact_match so that the entry is not also taken for F23 with other modifiers.
      (copilotPrefix "default" "game" (
        notify "Game mode on" "Space and left Ctrl are plain keys. Copilot, G turns it off."
      ))
      (copilotPrefix "game" "default" (
        notify "Game mode off" "Space held and left Ctrl are Hyper again."
      ))
    ];
  };

  configFile = (pkgs.formats.yaml { }).generate "xremap.yml" config;
in
{
  # Needs /dev/input/event* and /dev/uinput: the input and uinput groups (hosts/nixos-laptop.nix).
  # It runs in the session rather than as root so that it can ask Hyprland which window is focused.
  systemd.user.services.xremap = {
    Unit = {
      Description = "xremap (bottom row layout; Hyper on left Ctrl, Space held and the Copilot key; game mode)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      # --watch=device picks up keyboards plugged in later.
      ExecStart = lib.escapeShellArgs [
        (lib.getExe pkgs.xremap.hyprland)
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
