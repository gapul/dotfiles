# matrix-hookshot: generic webhooks and RSS/Atom feeds into Matrix rooms.
#
# Webhooks are public at https://hooks.gapul.net/webhook/<id> through the
# Cloudflare tunnel (cloudflared.nix), so things outside the tailnet (a
# Cloudflare Email Worker, GitHub Actions, ...) can post. Each URL carries an
# unguessable id created per room; there is no other auth.
#
# Usage, in a room with @hookshot:gapul.net invited:
#   !hookshot webhook <name>   create a webhook; the bot DMs the URL
#   !hookshot feed <url>       follow an RSS/Atom feed
#
# Rooms must be unencrypted. Hookshot's E2EE needs Redis plus experimental
# appservice MSCs, which is not worth it for notification rooms.
#
# Not enabled: GitHub/GitLab/Jira. They need an app registered on that service
# (id, private key, webhook secret); add them here with those as secrets first.
{ pkgs, ... }:
let
  dataDir = "/var/lib/matrix-hookshot";
  registrationFile = "${dataDir}/registration.yaml";
  domain = "gapul.net";
  appservicePort = 9993;
  webhookPort = 9000;
in
{
  users.users.matrix-hookshot = {
    isSystemUser = true;
    group = "matrix-hookshot";
    home = dataDir;
  };
  users.groups.matrix-hookshot = { };

  # Tokens are generated once on the host and never enter the store. Done in a
  # oneshot before Synapse for the same reason as mk-matrix-bridgev2.nix: Synapse
  # refuses to start if a listed registration file does not exist yet.
  systemd.services.matrix-hookshot-registration = {
    description = "Generate the matrix-hookshot appservice registration";
    before = [ "matrix-synapse.service" ];
    requiredBy = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "matrix-hookshot";
      Group = "matrix-hookshot";
      StateDirectory = baseNameOf dataDir;
      StateDirectoryMode = "0750";
      UMask = "0027";
    };
    script = ''
      if [ ! -f '${registrationFile}' ]; then
        token() { ${pkgs.openssl}/bin/openssl rand -hex 32; }
        cat > '${registrationFile}.tmp' <<EOF
      id: matrix-hookshot
      url: http://127.0.0.1:${toString appservicePort}
      as_token: $(token)
      hs_token: $(token)
      sender_localpart: hookshot
      rate_limited: false
      namespaces:
        rooms: []
        aliases: []
        users:
          - regex: '@_webhooks_.*:gapul\.net'
            exclusive: true
      EOF
        mv '${registrationFile}.tmp' '${registrationFile}'
      fi
    '';
  };

  services.matrix-synapse.settings.app_service_config_files = [ registrationFile ];
  systemd.services.matrix-synapse.serviceConfig.SupplementaryGroups = [ "matrix-hookshot" ];

  services.matrix-hookshot = {
    enable = true;
    inherit registrationFile;
    settings = {
      bridge = {
        inherit domain;
        url = "http://127.0.0.1:8008";
        mediaUrl = "https://matrix.gapul.net";
        port = appservicePort;
        bindAddress = "127.0.0.1";
      };
      permissions = [
        {
          actor = "@gapul:${domain}";
          services = [
            {
              service = "*";
              level = "admin";
            }
          ];
        }
      ];
      listeners = [
        {
          port = webhookPort;
          bindAddress = "127.0.0.1";
          resources = [ "webhooks" ];
        }
      ];
      generic = {
        enabled = true;
        urlPrefix = "https://hooks.gapul.net/webhook/";
        userIdPrefix = "_webhooks_";
        # Transformation functions run user-supplied JS; senders format their own
        # messages instead.
        allowJsTransformationFunctions = false;
        waitForComplete = false;
      };
      feeds = {
        enabled = true;
        pollIntervalSeconds = 600;
      };
      logging.level = "info";
    };
  };

  # The module runs the bridge as root with no state directory; it is reachable
  # from the internet through the tunnel, so drop that.
  systemd.services.matrix-hookshot = {
    requires = [ "matrix-hookshot-registration.service" ];
    after = [ "matrix-hookshot-registration.service" ];
    serviceConfig = {
      User = "matrix-hookshot";
      Group = "matrix-hookshot";
      StateDirectory = baseNameOf dataDir;
      StateDirectoryMode = "0750";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
    };
  };
}
