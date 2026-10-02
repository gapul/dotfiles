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
  # open-webui and anythingllm were also dropped on 2026-08-20. They overlapped with the
  # macmini's AI panel and there was no reason to keep both. Together they used about 660MB.
  # Give /var/lib/homelab back to root. Right after the migration it was still uid 100000 (the
  # subuid from the old CT101 rootless-container days), and systemd-tmpfiles refuses to create
  # anything under it with "Detected unsafe path transition /var/lib/homelab (owned by 100000) →
  # .../romm (owned by root)". Existing stacks didn't notice because their directories existed
  # since the migration, but it first shows up when a new stack is added (RomM was that one).
  #
  # Leave the children owned by each stack. This is just the container, so root:0755 is right.
  # Same leftover as the one fixed in /srv/syncthing on 2026-08-16.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab 0755 root root -"
  ];

  imports = [
    ./ci-runner.nix
    ./blocky.nix
    ./anki.nix
    ./archivebox.nix
    ./attic.nix
    ./audiobookshelf.nix
    ./authelia.nix
    ./bambuddy.nix
    ./atuin.nix
    ./backup.nix
    ./calnode.nix
    ./cloudflared.nix
    ./cli.nix
    ./dawarich.nix
    ./dawarich-freshness.nix
    ./filestash.nix
    ./forgejo.nix
    ./formera.nix
    ./free-games-claimer.nix
    ./freebie-collector.nix
    ./gameyfin.nix
    ./git-annex.nix
    ./hauk.nix
    ./ledger.nix
    ./mail.nix
    ./terraria.nix
    ./health.nix
    ./homebox.nix
    ./homeassistant.nix
    ./homepage.nix
    ./jellyfin.nix
    ./kavita.nix
    ./lazy-http-services.nix
    ./container-auto-update.nix
    ./self-deploy.nix
    ./vulnix.nix
    ./journal-alert.nix
    ./matrix.nix
    ./matrix-bridges.nix
    ./matrix-line.nix
    ./matrix-bridges-v2.nix
    ./matrix-googlechat.nix
    ./matrix-hookshot.nix
    ./matrix-doublepuppet.nix
    ./matrix-lowpriority.nix
    ./matrix-imessage.nix
    ./matrix-bridge-secrets.nix
    ./memory-pressure-alert.nix
    ./mullvad-exit.nix
    ./site-watch.nix # site change monitoring (urlwatch → ntfy); targets are the jobs list in the file
    ./miniflux.nix
    ./navidrome.nix
    ./nostr-bunker.nix
    ./ntfy.nix
    ./obsidian-couchdb.nix
    ./paperless.nix
    ./ytdl-sub.nix
    ./pingvin-share.nix
    ./playit.nix
    ./radicale.nix
    ./rallly.nix
    ./readeck.nix
    ./restic-view.nix
    ./restore-drill.nix
    ./romm.nix
    ./rsshub.nix
    ./samba.nix
    ./secrets.nix
    ./social.nix
    ./spliit.nix
    ./searx.nix
    ./syncthing.nix
    ./unified-calendar.nix
    ./utas-classes.nix # personal UTAS class schedule → Radicale "授業"
    ./vault-git.nix
    ./vaultwarden.nix
    ./vpn-relay.nix
    ./webmail.nix
    ./wger.nix
  ];
}
