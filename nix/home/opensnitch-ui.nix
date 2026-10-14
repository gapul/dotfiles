{
  config,
  lib,
  pkgs,
  ...
}:
# OpenSnitch's tray UI, as a view of what connects where (the mac has LuLu for this). The
# daemon is system-side, in hosts/nixos-laptop.nix, and allows by default.
#
# The UI asks about each new connection, and when the popup times out it applies its own
# default action, which upstream sets to deny. That would quietly break nix, tailscale or a
# backup while nobody is at the keyboard, so the UI's default is pinned to allow, with a
# short timeout. The file is the UI's own QSettings file, which it rewrites, so the two keys
# are set on each switch rather than the file being owned by home-manager.
let
  settings = "${config.xdg.configHome}/opensnitch/settings.conf";
in
{
  services.opensnitch-ui.enable = true;

  home.activation.opensnitchUiDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$(dirname "${settings}")"
    run ${pkgs.crudini}/bin/crudini --set "${settings}" global default_action 1 # 1 = allow
    run ${pkgs.crudini}/bin/crudini --set "${settings}" global default_timeout 15
  '';
}
