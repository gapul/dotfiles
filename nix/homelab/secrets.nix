{ lib, ... }:
let
  # Live, non-regenerable files that used to be placed by hand. Encrypted
  # values live below `homeserver_files` in secrets/homelab.yaml. Backup
  # copies, one-time passwords and retired files deliberately stay out.
  managedFiles = [
    { rel = "acme-cloudflare.env"; }
    { rel = "anki-sync.password"; }
    { rel = "archivebox.env"; }
    { rel = "attic.env"; }
    { rel = "authelia/jwt"; }
    { rel = "authelia/session"; }
    { rel = "authelia/storage-encryption"; }
    {
      rel = "authelia/users.yml";
      group = "authelia-main";
      mode = "0440";
    }
    { rel = "calnode.env"; }
    { rel = "cloudflared-homeserver.json"; }
    { rel = "dawarich.env"; }
    { rel = "filestash-secret-key"; }
    { rel = "formera.env"; }
    { rel = "free-games-claimer.env"; }
    { rel = "gameyfin.env"; }
    { rel = "gatus.env"; }
    { rel = "github-runner-token"; }
    { rel = "homebox.env"; }
    { rel = "homelab-cli.env"; }
    { rel = "ledger-deploy.key"; }
    {
      rel = "ledger-deploy.key.pub";
      mode = "0444";
    }
    { rel = "miniflux.env"; }
    { rel = "mosquitto-ha.password"; }
    { rel = "mvrx/chap-secrets"; }
    { rel = "mvrx/conn.conf"; }
    { rel = "mvrx/ipsec.secrets"; }
    { rel = "mvrx/peer"; }
    { rel = "mvrx/ppp-options"; }
    { rel = "mvrx/probe-host"; }
    { rel = "mvrx/xl2tpd.conf"; }
    { rel = "nostr.env"; }
    { rel = "ntfy-alerts.token"; }
    { rel = "obsidian-couchdb.env"; }
    { rel = "paperless.env"; }
    { rel = "playit.env"; }
    { rel = "puls.env"; }
    { rel = "rallly.env"; }
    { rel = "rclone.conf"; }
    { rel = "restic.password"; }
    { rel = "romm.env"; }
    { rel = "searx.env"; }
    { rel = "spliit.env"; }
    {
      rel = "synapse-registration-secret";
      owner = "matrix-synapse";
    }
    { rel = "tailscale.key"; }
    { rel = "vaultwarden.env"; }
    { rel = "writefreely-admin.password"; }
    { rel = "zaim.cookie"; }
  ];

  mkSecret =
    file:
    let
      id = lib.replaceStrings [ "/" ] [ "--" ] file.rel;
    in
    lib.nameValuePair "homeserver-files/${id}" {
      key = "homeserver_files/${id}";
      path = "/var/lib/secrets/${file.rel}";
      owner = file.owner or "root";
      group = file.group or "root";
      mode = file.mode or "0400";
    };
in
{
  sops = {
    defaultSopsFile = ../../secrets/homelab.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = builtins.listToAttrs (map mkSecret managedFiles);
  };

  # Preserve the restrictive directory permissions required by Authelia and
  # the office VPN while sops-nix replaces each file atomically.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets 0700 root root -"
    "d /var/lib/secrets/authelia 0750 root authelia-main -"
    "d /var/lib/secrets/mvrx 0700 root root -"
  ];
}
