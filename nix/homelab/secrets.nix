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
    { rel = "duo-remind.env"; }
    { rel = "filestash-secret-key"; }
    { rel = "formera.env"; }
    { rel = "free-games-claimer.env"; }
    { rel = "gameyfin.env"; }
    { rel = "gatus.env"; }
    { rel = "github-runner-token"; }
    { rel = "homebox.env"; }
    { rel = "homelab-cli.env"; }
    { rel = "ledger-deploy.key"; }
    { rel = "mail/admin.password"; }
    {
      rel = "mail/gmail.password";
      sopsFile = ../../secrets/mail.yaml;
      key = "stalwart/gmail";
    }
    {
      rel = "mail/sean.password";
      sopsFile = ../../secrets/mail.yaml;
      key = "stalwart/sean";
    }
    {
      rel = "mail/school.password";
      sopsFile = ../../secrets/mail.yaml;
      key = "stalwart/school";
    }
    { rel = "mail/gmail.address"; }
    { rel = "mail/gmail.app-password"; }
    { rel = "mail/sean.address"; }
    { rel = "mail/sean.app-password"; }
    { rel = "mail/school.address"; }
    { rel = "mail/school.app-password"; }
    {
      rel = "ledger-deploy.key.pub";
      mode = "0444";
    }
    { rel = "miniflux.env"; }
    { rel = "mosquitto-ha.password"; }
    {
      rel = "mullvad-exit.conf";
      restartUnits = [ "container@mullvad-exit.service" ];
    }
    {
      rel = "mullvad-host.key";
      restartUnits = [ "wg-quick-mullvad.service" ];
    }
    { rel = "l2tp/chap-secrets"; }
    { rel = "l2tp/conn.conf"; }
    { rel = "l2tp/ipsec.secrets"; }
    { rel = "l2tp/peer"; }
    { rel = "l2tp/ppp-options"; }
    { rel = "l2tp/probe-host"; }
    { rel = "l2tp/xl2tpd.conf"; }
    { rel = "nostr.env"; }
    { rel = "ntfy-alerts.token"; }
    { rel = "obsidian-couchdb.env"; }
    { rel = "paperless.env"; }
    { rel = "playit.env"; }
    { rel = "puls.env"; }
    {
      rel = "rallly.env";
      restartUnits = [ "podman-rallly.service" ];
    }
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
    {
      rel = "unified-calendar.env";
      owner = "unified-calendar";
    }
    # The calendar URLs themselves are secret (shared .ics that anyone who knows them can
    # read). Put the whole config in sops and pass it to the generator script as a file.
    {
      rel = "unified-calendar.yaml";
      owner = "unified-calendar";
    }
    # UTAS_ICS_URL (secret personal .ics) + Radicale credentials for utas-classes.nix.
    # DynamicUser can't own it, so it stays root-only and systemd reads it as EnvironmentFile.
    { rel = "utas-classes.env"; }
    { rel = "vault-deploy.key"; }
    { rel = "vaultwarden.env"; }
    {
      rel = "webdav.env";
      restartUnits = [ "webdav.service" ];
    }
    { rel = "wger.env"; }
    { rel = "zipline.env"; }
    { rel = "writefreely-admin.password"; }
    { rel = "zaim.cookie"; }
    { rel = "wise.token"; }
  ];

  mkSecret =
    file:
    let
      id = lib.replaceStrings [ "/" ] [ "--" ] file.rel;
    in
    lib.nameValuePair "homeserver-files/${id}" {
      # Most files live under homeserver_files in homelab.yaml. A file that other hosts also read
      # (the Stalwart login passwords, which every mail client holds) lives in its own sops file
      # instead, so its value has one home rather than a copy per recipient set.
      key = file.key or "homeserver_files/${id}";
      sopsFile = file.sopsFile or ../../secrets/homelab.yaml;
      path = "/var/lib/secrets/${file.rel}";
      owner = file.owner or "root";
      group = file.group or "root";
      mode = file.mode or "0400";
      restartUnits = file.restartUnits or [ ];
    };
in
{
  sops = {
    defaultSopsFile = ../../secrets/homelab.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = builtins.listToAttrs (map mkSecret managedFiles);
  };

  # Preserve the restrictive directory permissions required by Authelia and
  # the L2TP tunnel while sops-nix replaces each file atomically.
  #
  # The top directory is 0711, not 0700: the files are symlinks into /run/secrets
  # and some are opened by the service's own user (matrix-synapse reads
  # synapse-registration-secret, authelia-main reads authelia/users.yml), which
  # needs traverse permission on this directory. With 0700 Synapse died in
  # ExecStartPre with "Permission denied" on os.stat and restart-looped 1,270
  # times on 2026-09-26. Listing stays root-only.
  #
  # The `z` line fixes the mode of the already existing directory. Another unit was
  # resetting this to 0700 via `install -d -m 0700` (kavita.nix, 2026-09-27); that was
  # removed, but tmpfiles only reruns on switch when the rule text changes. With `d`
  # alone an already broken directory isn't fixed until reboot, so keep the intent as a line.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets 0711 root root -"
    "z /var/lib/secrets 0711 root root -"
    "d /var/lib/secrets/authelia 0750 root authelia-main -"
    "d /var/lib/secrets/l2tp 0700 root root -"
  ];
}
