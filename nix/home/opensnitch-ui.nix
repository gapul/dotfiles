{
  config,
  lib,
  pkgs,
  ...
}:
# OpenSnitch's tray UI, as a view of what connects where (the mac has LuLu for this). The
# daemon is system-side, in hosts/nixos-laptop.nix, and allows by default.
#
# Silent: no popup per new connection and no desktop notification, only the record. Open the
# tray icon to read it. Without this the UI asked about every new connection and, when a popup
# timed out, applied its own default action, which upstream sets to deny; that would quietly
# break nix, tailscale or a backup while nobody is at the keyboard.
#
# "Disable popups" in the UI's preferences is the same thing: disable_popups plus a timeout of 0,
# so each would-be popup resolves at once with default_action (1 = allow). The file is the UI's
# own QSettings file, which it rewrites, so the keys are set on each switch rather than the file
# being owned by home-manager.
let
  settings = "${config.xdg.configHome}/opensnitch/settings.conf";
  set = section: key: value: ''
    run ${pkgs.crudini}/bin/crudini --set "${settings}" ${section} ${key} ${value}
  '';
in
{
  services.opensnitch-ui.enable = true;

  home.activation.opensnitchUiDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$(dirname "${settings}")"
    ${set "global" "default_action" "1"}
    ${set "global" "disable_popups" "true"}
    ${set "global" "default_timeout" "0"}
    ${set "notifications" "enabled" "false"}
  '';
}
