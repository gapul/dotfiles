# Notify @gapul on room-wide mentions (@everyone / @here / @channel) from bridged networks.
#
# mautrix-discord and mautrix-slack turn these into m.mentions.room = true, but the spec's
# .m.rule.is_room_mention only fires when the sender's power level reaches
# notifications.room (default 50). Bridge ghosts sit at 0, so Synapse drops every one of
# them, and the muted channel portals (matrix-bridges.nix mute_channels_on_create,
# matrix-bridges-v2.nix mute_channels_by_default) end up silent even for @everyone
# (2026-10-18).
#
# This adds the same rule without the permission check as a user override rule. Override
# rules are evaluated before room rules, so it wins over the "mentions only" mute. On a
# single-user box the check guards against nothing anyway: every room-mention sender is a
# bridge ghost or someone already in the room on the other network.
#
# The rule is only written when missing or different. Synapse moves a re-PUT rule to the
# top of the override list, which would put it above mute rules added later by hand, and
# "enabled" is left alone so it can be switched off from a client.
#
# Runs as @gapul through the double puppeting appservice token (matrix-doublepuppet.nix).
{ pkgs, ... }:
let
  ruleId = "net.gapul.bridged_room_mention";
  rule = {
    conditions = [
      {
        kind = "event_property_is";
        key = "content.m\\.mentions.room";
        value = true;
      }
    ];
    actions = [
      "notify"
      {
        set_tweak = "sound";
        value = "default";
      }
      { set_tweak = "highlight"; }
    ];
  };
  ruleFile = pkgs.writeText "room-mention-rule.json" (builtins.toJSON rule);

  setter = pkgs.writeShellApplication {
    name = "matrix-room-mention-rule";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      url="http://127.0.0.1:8008/_matrix/client/v3/pushrules/global/override/${ruleId}?user_id=%40gapul%3Agapul.net"
      auth="Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/as_token")"
      want=$(jq -cS '{conditions, actions}' ${ruleFile})

      # 404 means the rule does not exist yet; anything else unexpected fails the unit.
      code=$(curl -sS --retry 5 --retry-connrefused --max-time 60 -H "$auth" \
        -o current.json -w '%{http_code}' "$url")
      case "$code" in
        200)
          have=$(jq -cS '{conditions, actions}' current.json)
          if [ "$have" = "$want" ]; then
            echo "push rule ${ruleId} already up to date"
            exit 0
          fi
          ;;
        404) ;;
        *)
          echo "unexpected HTTP $code reading ${ruleId}" >&2
          exit 1
          ;;
      esac

      curl -fsS --retry 5 --retry-connrefused --max-time 60 -H "$auth" \
        -X PUT -H 'Content-Type: application/json' --data-binary @${ruleFile} "$url" >/dev/null
      echo "wrote push rule ${ruleId}"
    '';
  };
in
{
  systemd.services.matrix-room-mention-rule = {
    description = "Notify @gapul on room mentions from bridge ghosts";
    wantedBy = [ "multi-user.target" ];
    after = [ "matrix-synapse.service" ];
    wants = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      DynamicUser = true;
      RuntimeDirectory = "matrix-room-mention-rule";
      WorkingDirectory = "/run/matrix-room-mention-rule";
      LoadCredential = [ "as_token:/var/lib/matrix-doublepuppet/as_token" ];
      ExecStart = "${setter}/bin/matrix-room-mention-rule";
      Restart = "on-failure";
      RestartSec = 30;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };
}
