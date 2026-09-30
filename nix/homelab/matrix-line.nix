# LINE bridge. nixpkgs has neither a services.mautrix-* module nor a package for it, so the
# package is pkgs/matrix-line.nix and the module is built with mk-matrix-bridgev2.nix.
#
# Log in from the Matrix side by DMing @linebot:gapul.net and sending `login`. It behaves as
# LINE's Chrome extension, so logging in disconnects the Chrome extension version of LINE.
#
# This bridge cannot fetch past history. bridgev2's FetchMessages implementation only returns
# the latest few dozen messages (upstream pkg/connector/sync.go), and LINE's servers do not
# keep old history either. Raising the backfill values does not fetch any more. Deep history
# is imported separately from a device backup.
import ./mk-matrix-bridgev2.nix {
  name = "matrix-line";
  id = "line";
  title = "LINE";
  package = pkgs: pkgs.callPackage ../pkgs/matrix-line.nix { };
  port = 29340;
}
