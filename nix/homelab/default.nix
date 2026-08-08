{
  # The Docker stacks that used to live on CT101 under dockge, converted to
  # oci-containers with compose2nix. dockge itself does not come along: managing
  # compose files through a web UI is the thing being replaced.
  #
  # These stay containers rather than being rewritten onto native NixOS modules.
  # Several of them have one (services.forgejo, services.navidrome, ...), but
  # switching means relocating data for no gain the definition in git does not
  # already provide. samba is the exception, and only because its container took a
  # password on the command line.
  #
  # Secrets are never in this tree. Anything a stack interpolated from its .env is
  # dropped from `environment` and supplied by environmentFiles at runtime; see
  # README.md for what each /var/lib/secrets/<stack>.env has to define.
  #
  # Still on the old host, deliberately: adguardhome and syncthing, which become
  # native modules so their settings stop living in a web UI, and the containers
  # being dropped outright (dockge, wud, backrest, uptime-kuma, adguardhome-sync,
  # stirling-pdf).
  imports = [
    ./anisette.nix
    ./archivebox.nix
    ./attic.nix
    ./dawarich.nix
    ./forgejo.nix
    ./homepage.nix
    ./jellyfin.nix
    ./matrix.nix
    ./miniflux.nix
    ./navidrome.nix
    ./ntfy.nix
    ./obsidian-couchdb.nix
    ./paperless.nix
    ./radicale.nix
    ./rsshub.nix
    ./samba.nix
    ./vaultwarden.nix
  ];
}
