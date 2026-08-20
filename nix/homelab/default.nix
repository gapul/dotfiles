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
  # Not containers at all: adguardhome, syncthing and samba are native modules, so
  # their settings stop living in a web UI or a command line, and backup.nix
  # declares the restic schedule that backrest used to own. Dropped outright:
  # dockge, wud, backrest, uptime-kuma, adguardhome-sync, stirling-pdf.
  #
  # open-webui と anythingllm も 2026-08-20 に落とした。macmini の AI パネルと
  # 用途が重なっていて、二重に持つ理由が無かった。合計で約 660MB 使っていた。
  imports = [
    ./blocky.nix
    ./anisette.nix
    ./anki.nix
    ./archivebox.nix
    ./attic.nix
    ./backup.nix
    ./calnode.nix
    ./cloudflared.nix
    ./dawarich.nix
    ./forgejo.nix
    ./free-games-claimer.nix
    ./homeassistant.nix
    ./homepage.nix
    ./jellyfin.nix
    ./matrix.nix
    ./miniflux.nix
    ./navidrome.nix
    ./ntfy.nix
    ./obsidian-couchdb.nix
    ./paperless.nix
    ./playit.nix
    ./radicale.nix
    ./readeck.nix
    ./restic-view.nix
    ./rsshub.nix
    ./samba.nix
    ./searx.nix
    ./syncthing.nix
    ./vaultwarden.nix
    ./vpn-relay.nix
  ];
}
