# Connect iMessage to Matrix. A bridge only the macmini can host.
#
# The other bridges (discord / signal / meta) live on the homeserver. This one is here because
# iMessage has no API reachable from outside. The bridge reads ~/Library/Messages/chat.db and
# sends by driving Messages.app. In other words, "a Mac signed in to iMessage" is itself the
# connection, and it cannot live on Linux.
#
# ## The resident job and config live on the system side
#
# The launchd job and config.yaml generation are in nix/hosts/macmini-imessage.nix.
# home-manager's launchd.agents always wraps in /bin/sh, so on macOS 26 Full Disk Access is
# evaluated against /bin/sh and has no effect. The reasons and measurements are at the top of
# that file. What remains here is only building and placing it at a signed, stable location.
#
# ## Full Disk Access
#
# chat.db is protected by TCC, so it needs a grant. Writing the store path directly into launchd
# makes each bridge update look like a different binary and drops the grant. As with sunshine,
# sign it with a self-signed identity, place it in ~/.local/libexec/tcc/, and point there.
# The cdhash drops out of the signature requirement, so it is treated as the same even when its
# contents change.
#
# Granting itself needs a human once (System Settings > Privacy & Security
# > Full Disk Access: add ~/.local/libexec/tcc/mautrix-imessage).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # olm is marked insecure. Allowed on the same judgment as the homeserver side
  # (nix/homelab/matrix-bridges.nix): it is only used for the bridge's E2EE, which is not enabled.
  # nixpkgs is re-imported here because home-manager cannot reach the host's nixpkgs.config.
  # When turning on E2EE, reconsider both together.
  pkgsWithOlm = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.permittedInsecurePackages = [ "olm-3.2.16" ];
  };
  bridge = pkgsWithOlm.callPackage ../pkgs/mautrix-imessage.nix { };
in
{
  home.activation.tccStableIMessage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      ${bridge}/bin/mautrix-imessage mautrix-imessage || true
  '';
}
