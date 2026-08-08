{
  # The Docker stacks that used to live on CT101 under dockge, converted to
  # oci-containers with compose2nix. dockge itself does not come along: managing
  # compose files through a web UI is the thing being replaced.
  #
  # These stay containers rather than being rewritten onto native NixOS modules.
  # Several of them have one (services.forgejo, services.navidrome, ...), but
  # switching means moving data into a different layout, which buys nothing that
  # this file does not already give: the definition is in git either way.
  #
  # Still on the old host, deliberately not converted here:
  #   - archivebox and samba, whose compose files carry a plaintext password that
  #     cannot go into a public repo (see the migration notes)
  #   - attic, dawarich, matrix, miniflux, obsidian-couchdb, paperless, vaultwarden,
  #     which interpolate secrets into `environment` where an empty or default value
  #     would silently shadow the real one from environmentFiles
  #   - adguardhome and syncthing, which become native modules so their settings
  #     stop living in a web UI
  imports = [
    ./anisette.nix
    ./forgejo.nix
    ./homepage.nix
    ./jellyfin.nix
    ./navidrome.nix
    ./ntfy.nix
    ./radicale.nix
    ./rsshub.nix
  ];
}
