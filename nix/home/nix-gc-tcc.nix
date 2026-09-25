{ lib, ... }:
{
  # Signed copy of `nix` at ~/.local/libexec/tcc/nix-collect-garbage for the root GC daemon in
  # hosts/darwin-common.nix. Same mechanism as restic-backup.nix: a stable path plus a self-signed
  # identity, so the Full Disk Access grant survives nix upgrades (the store path changes every
  # time; an ad-hoc signature would make each copy a different app to TCC).
  #
  # The source is the Determinate Nix profile, resolved to its store path so the stamp changes
  # (and the copy is refreshed) exactly when nix itself is upgraded. The multi-call binary
  # dispatches on argv[0], so the copy must keep the name nix-collect-garbage.
  home.activation.tccStableNixGc = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      "$(/usr/bin/readlink -f /nix/var/nix/profiles/default/bin/nix)" nix-collect-garbage || true
  '';
}
