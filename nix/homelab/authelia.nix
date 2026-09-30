# Authelia. SSO placed in front of each homeserver service.
#
# ## Why not Authentik
#
# Authentik keeps its config in a database and edits it in a web UI flow editor. It can't be
# declared. That's the same shape as the reason uptime-kuma was dropped (the monitor list lived
# in SQLite that nobody could review), and I don't want to build that again here. Authelia is
# self-contained: config is one YAML file, users are a file, secrets live under /var/lib/secrets.
# Diffs show up in git, and a blank box comes back to the same shape.
#
# ## What it protects
#
# It applies only to entries with `auth = true` in `sites` in hosts/homeserver.nix. That table
# mixes UIs viewed in a browser with endpoints machines call, so applying it across the board
# would silently stop iPhone location logging (track), Obsidian sync (obsidian), the build
# cache (cache), and notifications (ntfy). The decision is written on the table's side.
#
# Vaultwarden (vault) is deliberately excluded. Putting the password vault behind SSO creates a
# loop: if you can't remember the SSO password, you can't open the vault.
#
# ## Two-factor
#
# `two_factor` is the default. The judgment is not to treat being inside the tailnet as proof of
# identity, since that premise weakens as more devices join the tailnet. To relax it, set the
# policy in access_control below to one_factor (one place).
#
# The notifier is file-based, so the initial registration link lands in a file on the server,
# not in email:
#   ssh homeserver sudo cat /var/lib/authelia-main/notification.txt
{
  config,
  lib,
  ...
}:
let
  port = 9092;
  domain = "gapul.net";
in
{
  services.authelia.instances.main = {
    enable = true;

    # Secrets are handled like the rest of homelab. sops-nix doesn't have a key on this box yet
    # (see homelab/README.md), so these are root:0400 files placed by hand at install time.
    secrets = {
      jwtSecretFile = "/var/lib/secrets/authelia/jwt";
      sessionSecretFile = "/var/lib/secrets/authelia/session";
      storageEncryptionKeyFile = "/var/lib/secrets/authelia/storage-encryption";
    };

    settings = {
      theme = "auto";
      server.address = "tcp://127.0.0.1:${toString port}";

      log = {
        level = "info";
        format = "text"; # journald picks it up, so not JSON
      };

      # One user. No reason to stand up LDAP.
      # The file's contents follow the format in the README table; passwords are argon2id hashes.
      authentication_backend = {
        password_reset.disable = true; # the only notification path is a file, so don't open this door
        file = {
          path = "/var/lib/secrets/authelia/users.yml";
          watch = false;
        };
      };

      # Default is deny. Only vhosts with forward_auth on the Caddy side get through, so a
      # single rule "let every gapul.net subdomain through with two_factor" is enough here.
      # To vary the strength per service, stack individual rules above this one.
      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = "*.${domain}";
            policy = "two_factor";
          }
        ];
      };

      session = {
        name = "authelia_session";
        # Putting it on the parent domain means one login covers all subdomains.
        # This is what SSO actually is.
        cookies = [
          {
            inherit domain;
            authelia_url = "https://auth.${domain}";
            default_redirection_url = "https://dash.${domain}";
            expiration = "12h";
            inactivity = "2h";
            remember_me = "1M";
          }
        ];
      };

      regulation = {
        max_retries = 4;
        find_time = "2m";
        ban_time = "10m";
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      # No SMTP. TOTP registration links land in a file.
      notifier = {
        disable_startup_check = true;
        filesystem.filename = "/var/lib/authelia-main/notification.txt";
      };

      totp = {
        issuer = domain;
        algorithm = "sha1"; # widest authenticator app compatibility
        period = 30;
      };
    };
  };
}
