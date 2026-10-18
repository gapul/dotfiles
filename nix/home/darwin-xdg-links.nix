{ config, lib, ... }:
# Non-XDG tools whose real data lives under XDG, with the default path kept as a symlink (same
# approach as terminfo). Classification: credentials/long-term data = data, telemetry state = state.
#
# Shared by both Macs. These were in home/darwin.nix only, which the macmini role does not import;
# the mini had them once (from the workstation config, 2026-08-09) and kept the links after that
# generation was collected, dangling, while configs/macmini/bin/macmini-compile-worker still relies
# on ~/.dart-tool.
{
  home.file.".appstoreconnect".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/appstoreconnect";
  home.file.".cloudflared".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/cloudflared";
  home.file.".dart-tool".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/dart-tool";
  # Ensure the entity exists first, else tool writes fail with ENOENT when the symlink target is missing
  home.activation.xdgSymlinkTargets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.xdg.dataHome}/appstoreconnect" \
      "${config.xdg.dataHome}/cloudflared" \
      "${config.xdg.stateHome}/dart-tool"
  '';
}
