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
  # /var/lib/homelab の所有者を root に戻す。移行直後は uid 100000 (旧 CT101 の
  # rootless コンテナ時代の subuid) のままで、systemd-tmpfiles が
  # 「Detected unsafe path transition /var/lib/homelab (owned by 100000) →
  # .../romm (owned by root)」として配下の作成を拒否する。既存のスタックは
  # ディレクトリが移行時から在るので気付かれなかったが、新しいスタックを足すと
  # そこで初めて出る (RomM がそれ)。
  #
  # 配下は各スタックの所有のまま触らない。ここは入れ物なので root:0755 が正しい。
  # /srv/syncthing で 2026-08-16 に直したのと同じ残骸。
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab 0755 root root -"
  ];

  imports = [
    ./blocky.nix
    ./anisette.nix
    ./anki.nix
    ./archivebox.nix
    ./attic.nix
    ./atuin.nix
    ./backup.nix
    ./calnode.nix
    ./cloudflared.nix
    ./dawarich.nix
    ./dawarich-freshness.nix
    ./fava.nix
    ./forgejo.nix
    ./free-games-claimer.nix
    ./gameyfin.nix
    ./git-annex.nix
    ./hauk.nix
    ./homeassistant.nix
    ./homepage.nix
    ./jellyfin.nix
    ./container-auto-update.nix
    ./self-deploy.nix
    ./journal-alert.nix
    ./matrix.nix
    ./matrix-bridges.nix
    ./miniflux.nix
    ./navidrome.nix
    ./ntfy.nix
    ./obsidian-couchdb.nix
    ./paperless.nix
    ./pinchflat.nix
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
    ./spliit.nix
    ./searx.nix
    ./syncthing.nix
    ./vaultwarden.nix
    ./vpn-relay.nix
  ];
}
