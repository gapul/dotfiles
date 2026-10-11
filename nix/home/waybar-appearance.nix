{
  config,
  lib,
  pkgs,
  ...
}:
let
  c = import ../lib/theme.nix;
  colors = [
    "base"
    "surface"
    "overlay"
    "muted"
    "subtle"
    "text"
    "love"
    "gold"
    "rose"
    "pine"
    "foam"
    "iris"
    "hlMed"
  ];
  cssFor =
    mode: palette:
    pkgs.writeText "waybar-${mode}.css" (
      lib.replaceStrings (map (name: "#${c.${name}}") colors) (map (
        name: "#${palette.${name}}"
      ) colors) config.programs.waybar.style
    );
  stateDir = "${config.xdg.stateHome}/waybar";
  apply = pkgs.writeShellApplication {
    name = "waybar-appearance";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.darkman
      pkgs.systemd
    ];
    text = ''
      mode="''${1:-$(darkman get 2>/dev/null || echo dark)}"
      case "$mode" in
        light) style=${cssFor "light" c.light} ;;
        dark) style=${cssFor "dark" c.dark} ;;
        *) echo "usage: waybar-appearance [light|dark]" >&2; exit 2 ;;
      esac
      mkdir -p ${lib.escapeShellArg stateDir}
      ln -sfn "$style" ${lib.escapeShellArg "${stateDir}/style.css"}
      # ExecStartPre also calls this: do not reload a service that is starting.
      if systemctl --user is-active --quiet waybar.service; then
        systemctl --user reload waybar.service
      fi
    '';
  };
in
{
  home.packages = [ apply ];
  services.darkman.lightModeScripts.waybar = "${lib.getExe apply} light";
  services.darkman.darkModeScripts.waybar = "${lib.getExe apply} dark";
  # Keep HM's source CSS immutable; only the selected stylesheet link is runtime state.
  systemd.user.services.waybar.Service = {
    ExecStartPre = [ (lib.getExe apply) ];
    ExecStart = lib.mkForce "${lib.getExe config.programs.waybar.package} --style ${stateDir}/style.css";
  };
}
