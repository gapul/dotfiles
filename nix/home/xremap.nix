{
  lib,
  pkgs,
  ...
}:
# Mac-style modifiers on the NixOS laptop, done with xremap (a key remapper that sits between the
# keyboard and the compositor, reading evdev and writing to a uinput device):
#
#   - The key next to Space is Cmd: left Alt and left Super are swapped, so the row reads
#     Ctrl Fn Alt(=Opt) Super(=Cmd) Space as on a mac, and Super+key is sent to apps as Ctrl+key
#     (Super+C copies, Super+W closes the tab, ...).
#   - Ctrl (Caps Lock, or the real one) is the Emacs/Cocoa text keys in GUI apps: Ctrl+A/E/F/B/N/P/
#     H/D/K move and delete as in a macOS text field. Any other Ctrl combo goes through as Ctrl.
#   - Space held is Hyper (Super+Ctrl+Alt), the window manager's modifier, as Karabiner does on the
#     mac (configs/keyboard/karabiner/karabiner.ts); tapped, it is Space.
#
# Ghostty is a terminal, so Ctrl stays the real Ctrl there (Ctrl+C is SIGINT, Ctrl+A is the shell's
# line start) and Cmd is translated to Ghostty's own Linux bindings (Ctrl+Shift+C copies, ...).
#
# This has to be xremap rather than xkb options: xremap sits under xkb, so it sees physical keys,
# and an xkb swap of Alt/Super would be applied a second time on top of its output. Caps Lock as Ctrl
# is also set in xkb (home/hyprland.nix, hosts/nixos-laptop.nix) for when xremap is not running.
#
# Every keymap is exact_match: with xremap's default inexact matching, Hyper+F (Super+Ctrl+Alt+F)
# would hit the Ctrl+F rule and reach Hyprland as Super+Alt+Right instead of its own bind.
let
  ghostty = "com.mitchellh.ghostty";

  # Keys that Cmd+key passes through as Ctrl+key (and Cmd+Shift+key as Ctrl+Shift+key).
  cmdKeys = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz0123456789" ++ [
    "minus"
    "equal"
    "comma"
    "dot"
    "slash"
    "semicolon"
    "apostrophe"
    "grave"
    "enter"
  ];

  config = {
    modmap = [
      {
        name = "mac modifiers";
        remap = {
          CapsLock = "Control_L";
          Alt_L = "Super_L";
          Super_L = "Alt_L";
          Space = {
            held = [
              "Super_L"
              "Control_L"
              "Alt_L"
            ];
            alone = "Space";
          };
        };
      }
    ];

    keymap = [
      {
        name = "Cmd in Ghostty";
        exact_match = true;
        application.only = ghostty;
        remap = {
          Super-c = "C-Shift-c";
          Super-v = "C-Shift-v";
          Super-a = "C-Shift-a";
          Super-f = "C-Shift-f";
          Super-t = "C-Shift-t";
          Super-w = "C-Shift-w";
          Super-n = "C-Shift-n";
          Super-q = "C-Shift-q";
          Super-equal = "C-equal";
          Super-minus = "C-minus";
          Super-0 = "C-0";
          Super-Shift-leftbrace = "C-pageup";
          Super-Shift-rightbrace = "C-pagedown";
        };
      }
      {
        name = "Cmd in GUI apps";
        exact_match = true;
        application.not = ghostty;
        remap =
          lib.listToAttrs (
            lib.concatMap (k: [
              (lib.nameValuePair "Super-${k}" "C-${k}")
              (lib.nameValuePair "Super-Shift-${k}" "C-Shift-${k}")
            ]) cmdKeys
          )
          // {
            # Cmd+arrows go to the line or document ends, Cmd+Delete deletes to the line start.
            Super-left = "home";
            Super-right = "end";
            Super-up = "C-home";
            Super-down = "C-end";
            Super-Shift-left = "Shift-home";
            Super-Shift-right = "Shift-end";
            Super-Shift-up = "C-Shift-home";
            Super-Shift-down = "C-Shift-end";
            Super-backspace = [
              "Shift-home"
              "backspace"
            ];
            # Previous / next tab, as Cmd+Shift+[ and ] are on the mac.
            Super-Shift-leftbrace = "C-pageup";
            Super-Shift-rightbrace = "C-pagedown";
          };
      }
      {
        name = "Emacs keys in GUI apps";
        exact_match = true;
        application.not = ghostty;
        remap = {
          C-a = "home";
          C-e = "end";
          C-f = "right";
          C-b = "left";
          C-n = "down";
          C-p = "up";
          C-h = "backspace";
          C-d = "delete";
          C-k = [
            "Shift-end"
            "delete"
          ];
        };
      }
    ];
  };

  configFile = (pkgs.formats.yaml { }).generate "xremap.yml" config;
in
{
  # Needs /dev/input/event* and /dev/uinput: the input and uinput groups (hosts/nixos-laptop.nix).
  # It runs in the session rather than as root so that it can ask Hyprland which window is focused.
  systemd.user.services.xremap = {
    Unit = {
      Description = "xremap (mac-style Cmd / Ctrl / Hyper)";
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
