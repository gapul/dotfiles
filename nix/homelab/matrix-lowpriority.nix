# Tag muted Discord guild channels and Slack channels as low priority for @gapul.
#
# The bridges already mute new channel portals (discord mute_channels_on_create, slack
# mute_channels_by_default), so they stop notifying, but Element still floats them to the
# top on activity. m.lowpriority is what keeps them out of the way: Element X iOS hides
# them from the main list (developer option "Low priority filter") and Element Web sinks
# them in recency order. Neither bridge can set room tags, so this timer does it.
#
# Each muted room is looked at once and remembered in the state file, so a tag removed by
# hand stays removed. A room muted by hand in another network is left alone because only
# discordgo guild portals (m.bridge has a network) and slackgo portals are tagged.
#
# Runs as @gapul through the double puppeting appservice token (matrix-doublepuppet.nix).
{ pkgs, ... }:
let
  tagger = pkgs.writeShellApplication {
    name = "matrix-lowpriority-tagger";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      hs=http://127.0.0.1:8008/_matrix/client/v3
      me='%40gapul%3Agapul.net'
      q="user_id=$me"
      seen="$STATE_DIRECTORY/seen"
      touch "$seen"
      auth="Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/as_token")"
      api() { curl -fsS --retry 3 --max-time 60 -H "$auth" "$@"; }

      # Room-level push rules with no actions (or dont_notify) are what "mentions only"
      # and the bridges' mute both write.
      muted=$(api "$hs/pushrules/?$q" | jq -r '
        .global.room[]
        | select((.actions | length) == 0 or .actions == ["dont_notify"])
        | .rule_id')

      tagged=0
      checked=0
      while IFS= read -r room; do
        [ -n "$room" ] || continue
        grep -qxF "$room" "$seen" && continue
        checked=$((checked + 1))
        enc=$(jq -rn --arg r "$room" '$r | @uri')
        # A room we have left still has its push rule; skip it rather than fail the run.
        if state=$(api "$hs/rooms/$enc/state?$q"); then
          target=$(jq -r '
            [.[] | select(.type == "m.bridge") | .content
              | select(.protocol.id == "slackgo"
                       or (.protocol.id == "discordgo" and .network != null))]
            | length > 0' <<<"$state")
          if [ "$target" = true ]; then
            has=$(api "$hs/user/$me/rooms/$enc/tags?$q" | jq '.tags | has("m.lowpriority")')
            if [ "$has" != true ]; then
              api -X PUT -H 'Content-Type: application/json' -d '{}' \
                "$hs/user/$me/rooms/$enc/tags/m.lowpriority?$q" >/dev/null
              tagged=$((tagged + 1))
            fi
          fi
        fi
        echo "$room" >>"$seen"
      done <<<"$muted"
      echo "checked $checked new muted rooms, tagged $tagged"
    '';
  };
in
{
  systemd.services.matrix-lowpriority-tagger = {
    description = "Tag muted Discord/Slack channel portals as low priority";
    after = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "matrix-lowpriority-tagger";
      LoadCredential = [ "as_token:/var/lib/matrix-doublepuppet/as_token" ];
      ExecStart = "${tagger}/bin/matrix-lowpriority-tagger";
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };

  systemd.timers.matrix-lowpriority-tagger = {
    description = "Tag new muted Discord/Slack channel portals hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:23:00";
      Persistent = true;
    };
  };
}
