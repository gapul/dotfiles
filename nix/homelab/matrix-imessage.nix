# appservice registration for the iMessage bridge. The bridge itself is not here.
#
# All other mautrix bridges run on this box, but iMessage alone needs chat.db and Messages.app, so
# it runs on macmini (nix/home/macmini-imessage.nix). To Synapse it is "an appservice across the
# tailnet", and only the registration file lives on this box.
#
# Token flow: other bridges run --generate-registration on the same box and hand it to Synapse, but
# here the machines differ, so as_token / hs_token live in secrets/matrix-imessage.yaml, openable
# by both hosts' keys (.sops.yaml). This box injects the same values into the registration file and
# macmini into the bridge config. Regenerating the tokens changes both at once.
#
# url is macmini's tailnet address; Synapse pushes events there. That is why the macmini-side
# firewall (socketfilterfw in hosts/macmini.nix) needs a hole.
{ config, ... }:
let
  domain = "gapul.net";
  macmini = "100.105.135.49";
  port = 29332;
  registration = "matrix-imessage-registration.yaml";
in
{
  sops.secrets = {
    "matrix_imessage/as_token".sopsFile = ../../secrets/matrix-imessage.yaml;
    "matrix_imessage/hs_token".sopsFile = ../../secrets/matrix-imessage.yaml;
  };

  # The namespaces match what the bridge emits with --generate-registration (generated on the real
  # machine and copied on 2026-09-28). It claims bot and imessage_* exclusively. msc2409's
  # push_ephemeral is needed to forward read receipts and typing (paired with appservice.ephemeral_events
  # in the config). The bare `push_ephemeral` the bridge emits alongside is not read by Synapse, so it isn't copied.
  sops.templates.${registration} = {
    owner = "matrix-synapse";
    mode = "0400";
    restartUnits = [ "matrix-synapse.service" ];
    content = ''
      id: imessage
      url: http://${macmini}:${toString port}
      as_token: ${config.sops.placeholder."matrix_imessage/as_token"}
      hs_token: ${config.sops.placeholder."matrix_imessage/hs_token"}
      sender_localpart: imessagebot
      rate_limited: false
      namespaces:
        users:
          - regex: '^@imessagebot:${builtins.replaceStrings [ "." ] [ "\\." ] domain}$'
            exclusive: true
          - regex: '^@imessage_.*:${builtins.replaceStrings [ "." ] [ "\\." ] domain}$'
            exclusive: true
      de.sorunome.msc2409.push_ephemeral: true
    '';
  };

  services.matrix-synapse.settings.app_service_config_files = [
    config.sops.templates.${registration}.path
  ];
}
