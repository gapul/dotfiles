# Appservice for double puppeting. Puts a registration in Synapse that can send as
# @gapul:gapul.net itself.
#
# What it is for:
#   - Bridges: show messages I sent from LINE on the phone as @gapul's own messages in Matrix,
#     rather than relayed by the bot (the standard way of passing "as_token:<token>" to
#     mautrix's double_puppet.secrets)
#   - History import: Synapse only lets appservices override the send timestamp (?ts=).
#     Importing my old messages at their original times needs this registration
#
# The namespace is narrowed to @gapul:gapul.net only. mautrix's guide uses @.*:domain, but
# there is no reason to widen what this token can impersonate.
#
# The token is generated on first run and kept in /var/lib, never in the store. Synapse and
# the bridges read it via a group.
{ pkgs, ... }:
let
  dataDir = "/var/lib/matrix-doublepuppet";
  registrationFile = "${dataDir}/registration.yaml";
in
{
  users.groups.matrix-doublepuppet = { };

  systemd.services.matrix-doublepuppet-registration = {
    description = "Generate the double puppeting appservice registration";
    before = [ "matrix-synapse.service" ];
    requiredBy = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = baseNameOf dataDir;
      StateDirectoryMode = "0750";
      Group = "matrix-doublepuppet";
      UMask = "0027";
    };
    script = ''
      if [ ! -f '${registrationFile}' ]; then
        token() { ${pkgs.openssl}/bin/openssl rand -hex 32; }
        as_token=$(token)
        cat > '${registrationFile}.tmp' <<EOF
      id: doublepuppet
      url: null
      as_token: $as_token
      hs_token: $(token)
      sender_localpart: $(token)
      rate_limited: false
      namespaces:
        users:
          - regex: '@gapul:gapul\.net'
            exclusive: false
      EOF
        printf '%s' "$as_token" > '${dataDir}/as_token.tmp'
        mv '${dataDir}/as_token.tmp' '${dataDir}/as_token'
        mv '${registrationFile}.tmp' '${registrationFile}'
      fi
      chgrp matrix-doublepuppet '${dataDir}' '${registrationFile}' '${dataDir}/as_token'
    '';
  };

  services.matrix-synapse.settings.app_service_config_files = [ registrationFile ];
  systemd.services.matrix-synapse.serviceConfig.SupplementaryGroups = [ "matrix-doublepuppet" ];

  # Let the agent (gapul over ssh) read this token too, to send commands to bridge management
  # rooms as @gapul itself (e.g. discord's `guilds bridge`). Bridge commands act on the calling
  # user's login, so @claude cannot stand in.
  # Usage: call the Client-Server API with Authorization: Bearer <as_token> plus
  # ?user_id=@gapul:gapul.net (appservice masquerade). Does not apply to existing ssh sessions
  # (the group takes effect from the next login).
  users.users.gapul.extraGroups = [ "matrix-doublepuppet" ];
}
