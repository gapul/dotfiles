# The few compositor commands that the niri and Hyprland sessions share (idle, power menu,
# xremap, wl-keyboard), dispatched to whichever one this session runs. niri is the default
# session on nixos-laptop (home/niri.nix); Hyprland stays selectable in the greeter.
#
# Decided by the live IPC socket rather than by the variable alone: the user manager keeps
# imported variables after a session ends, so a stale HYPRLAND_INSTANCE_SIGNATURE can still be
# set inside a niri session (and the other way round).
{ pkgs }:
pkgs.writeShellApplication {
  name = "wm-session";
  bashOptions = [
    "errexit"
    "nounset"
  ];
  text = ''
    current() {
      if [ -n "''${NIRI_SOCKET:-}" ] && [ -S "$NIRI_SOCKET" ]; then
        echo niri
      elif [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] &&
        [ -S "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
        echo hyprland
      else
        echo none
      fi
    }
    niri() { ${pkgs.niri}/bin/niri msg action "$@"; }
    hypr() { ${pkgs.hyprland}/bin/hyprctl dispatch "$@" >/dev/null; }
    # niri reads a bare number as an absolute size, so a relative step needs its sign.
    signed() { case "$1" in [+-]*) echo "$1" ;; *) echo "+$1" ;; esac; }

    case "''${1:-}" in
      current) current ;;
      is) [ "$(current)" = "''${2:?niri or hyprland}" ] ;;
      dpms) # on | off
        case "$(current)" in
          niri) niri "power-''${2:?on or off}-monitors" ;;
          hyprland) hypr dpms "''${2:?on or off}" ;;
        esac
        ;;
      exit)
        case "$(current)" in
          niri) niri quit --skip-confirmation ;;
          hyprland) hypr exit ;;
        esac
        ;;
      move) # l | r | u | d
        case "$(current)" in
          niri)
            case "''${2:?l, r, u or d}" in
              l) niri move-column-left ;;
              r) niri move-column-right ;;
              u) niri move-window-up ;;
              d) niri move-window-down ;;
            esac
            ;;
          hyprland) hypr movewindow "$2" ;;
        esac
        ;;
      resize) # dx dy, in logical pixels
        case "$(current)" in
          niri)
            [ "''${2:?dx}" = 0 ] || niri set-column-width "$(signed "$2")"
            [ "''${3:?dy}" = 0 ] || niri set-window-height "$(signed "$3")"
            ;;
          hyprland) hypr resizeactive "$2" "$3" ;;
        esac
        ;;
      submap) # Hyprland's modal keymaps; niri has no modes, so this does nothing there.
        if [ "$(current)" = hyprland ]; then hypr submap "''${2:?submap name}"; fi
        ;;
      *)
        echo "usage: wm-session current | is NAME | dpms on|off | exit | move l|r|u|d | resize DX DY | submap NAME" >&2
        exit 2
        ;;
    esac
  '';
}
