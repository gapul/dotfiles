# Matrix homeserver. Switched from Conduit to Synapse on 2026-08-31.
#
# Why switch: we decided to grow the bridges from 2 (Discord/Telegram) to around 10, and
# Conduit is not a good place to carry that scale:
#
#   - Upstream Conduit has stalled. The lineage is Conduit -> conduwuit (archived) ->
#     continuwuity, and what we ran was 0.10.12. On top of that, mid-2026 continuwuity fixed
#     "encrypted bridges can't start" and "users aren't created with the requested localpart,
#     so mautrix-telegram crashes". That is exactly where we were headed.
#   - Moving to continuwuity isn't straightforward either. The RocksDB schema has diverged
#     since the fork, and migration is one-way.
#   - The deciding factor was registration. Conduit keeps appservice registrations in RocksDB
#     and they can only be changed through the admin room. That is why this file used to say
#     "bridges can't be declared" and kept them as containers. Synapse reads registrations
#     from config files, which removes that obstacle. In practice the nixpkgs
#     services.mautrix-* modules become usable.
#
# The migration cost was zero. Nobody uses it yet (RocksDB is 4MB, no rooms, no history).
# The same call can't be made once it's in use, so switch now.
#
# server_name stays gapul.net. well-known (gapul.net/.well-known/matrix/server ->
# matrix.gapul.net:443) and the Cloudflare CNAME already work with it, so leave them alone.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.matrix-synapse = {
    enable = true;

    settings = {
      server_name = "gapul.net";
      public_baseurl = "https://matrix.gapul.net/";

      # Federation goes through here only. cloudflared hands it over as
      # matrix.gapul.net -> 127.0.0.1:8008.
      #
      # Listens on 0.0.0.0 because the bridges call in from the podman network side.
      # Same exposure as with Conduit (8008 is opened in the firewall below).
      listeners = [
        {
          port = 8008;
          bind_addresses = [ "0.0.0.0" ];
          type = "http";
          tls = false;
          # cloudflared sits in front, so take the source from X-Forwarded-For.
          x_forwarded = true;
          resources = [
            {
              names = [
                "client"
                "federation"
              ];
              compress = false;
            }
          ];
        }
      ];

      enable_registration = false;
      # Don't let anyone register without an invite. Users are created with register_new_matrix_user.
      registration_shared_secret_path = "/var/lib/secrets/synapse-registration-secret";

      database = {
        name = "psycopg2";
        args = {
          # Connects over the UNIX socket, so no host. Peer auth lets it through.
          database = "matrix-synapse";
          user = "matrix-synapse";
          cp_min = 5;
          cp_max = 10;
        };
      };

      # A single-user box, so room creation and media fetching can be lenient.
      # Bridges push lots of events in a short time and clog on the default rate limits.
      rc_message = {
        per_second = 100;
        burst_count = 500;
      };
      rc_joins.local = {
        per_second = 100;
        burst_count = 500;
      };
      # Bridge bots create users one after another, so without loosening this too the first sync stalls.
      rc_registration = {
        per_second = 100;
        burst_count = 500;
      };

      trusted_key_servers = [ { server_name = "matrix.org"; } ];
      suppress_key_server_warning = true;

      max_upload_size = "50M";

      # Auto-accept invites to rooms the bridges create. Accepting portals for 10 bridges by hand
      # isn't realistic (the iMessage history sync created 36 rooms at once, 2026-09-29).
      # Senders are limited to users on our own server (= bridge ghosts); invites over federation
      # are still accepted by hand. Not limited to DMs so that group rooms are covered too.
      auto_accept_invites = {
        enabled = true;
        only_for_direct_messages = false;
        only_from_local_users = true;
      };
    };
  };

  # Shared secret for registration. With enable_registration = false nobody can sign up from
  # outside, but register_new_matrix_user needs this to create our own accounts. Synapse won't
  # start without the file, so create it if missing. Never change the contents once created
  # (changing it breaks invites already handed out).
  systemd.services.matrix-synapse-registration-secret = {
    description = "Synapse の登録共有秘密を用意する";
    wantedBy = [ "matrix-synapse.service" ];
    before = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl ];
    script = ''
      f=/var/lib/secrets/synapse-registration-secret
      # /var/lib/secrets は secrets.nix の tmpfiles が 0711 で管理する。ここで
      # install -d すると既存ディレクトリのモードまで書き換わる (kavita.nix 参照)。
      if [ ! -s "$f" ]; then
        openssl rand -hex 32 > "$f"
        chmod 0400 "$f"
      fi
      chown matrix-synapse "$f" || true
    '';
  };

  # Synapse is strict about collation. It refuses to start if it finds a DB created with
  # anything other than C (allow_unsafe_locale silences it, but search breaks later).
  #
  # This cluster was spun up by atuin via services.atuin's database.createLocally = true,
  # and its default collation is ja_JP.UTF-8, so ensureDatabases can't create it.
  # initialScript only runs when the cluster is first created, so that's out too.
  # Create it ourselves. It's idempotent, so running every time is fine.
  systemd.services.matrix-synapse-db-init = {
    description = "Synapse の DB を C ロケールで用意する";
    wantedBy = [ "matrix-synapse.service" ];
    before = [ "matrix-synapse.service" ];
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };
    path = [ config.services.postgresql.package ];
    script = ''
      psql -tAc "select 1 from pg_roles where rolname='matrix-synapse'" | grep -q 1 \
        || psql -c "CREATE ROLE \"matrix-synapse\" WITH LOGIN"
      psql -tAc "select 1 from pg_database where datname='matrix-synapse'" | grep -q 1 \
        || psql -c "CREATE DATABASE \"matrix-synapse\" WITH OWNER \"matrix-synapse\" \
             TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C'"
    '';
  };

  # cloudflared, and from here on the bridges on the podman side, need to reach it. When closed
  # it's a DROP, so you get a timeout rather than connection refused, and the bridge only says
  # "can't reach the homeserver". Same exposure as Conduit opening 6167.
  networking.firewall.allowedTCPPorts = [ 8008 ];
}
