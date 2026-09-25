{ config, pkgs, ... }:
let
  # Shared prelude: homeserver, the bot's token (sops, below), and alias -> room id resolution.
  # Plain Client-Server API over curl so an agent can drive Matrix without a TUI. Unencrypted
  # rooms only: E2EE needs an olm/vodozemac client, so keep agent rooms unencrypted.
  prelude = ''
    set -euo pipefail
    hs=https://matrix.gapul.net
    tok=$(cat "${config.sops.secrets."matrix/claude_token".path}")
    api() { curl -sSf -H "Authorization: Bearer $tok" "$@"; }
    # "#alias:server" -> "!id:server"; "!id:server" passes through.
    room_id() {
      case "$1" in
        '#'*) api "$hs/_matrix/client/v3/directory/room/$(jq -rn --arg a "$1" '$a|@uri')" | jq -r .room_id ;;
        *) printf '%s\n' "$1" ;;
      esac
    }
  '';
in
{
  # Access token of @claude:gapul.net (non-admin bot user). Minted by password login with device
  # "claude-code"; rotate by logging that device out in Element and logging in again.
  sops.secrets."matrix/claude_token".path =
    "${config.home.homeDirectory}/.config/matrix/claude_token";

  home.packages = [
    # matrix-send ROOM TEXT...   (TEXT "-" reads stdin)
    (pkgs.writeShellApplication {
      name = "matrix-send";
      runtimeInputs = [
        pkgs.curl
        pkgs.jq
      ];
      text = prelude + ''
        room=$(room_id "$1"); shift
        if [ "$#" -eq 1 ] && [ "$1" = "-" ]; then body=$(cat); else body="$*"; fi
        api -X PUT -H 'Content-Type: application/json' \
          --data-binary "$(jq -n --arg b "$body" '{msgtype:"m.text",body:$b}')" \
          "$hs/_matrix/client/v3/rooms/$room/send/m.room.message/$(date +%s)$RANDOM" | jq -r .event_id
      '';
    })
    # matrix-read ROOM [N]   -> last N (default 20) text messages, oldest first, as JSON lines
    (pkgs.writeShellApplication {
      name = "matrix-read";
      runtimeInputs = [
        pkgs.curl
        pkgs.jq
      ];
      text = prelude + ''
        room=$(room_id "$1"); n="''${2:-20}"
        api "$hs/_matrix/client/v3/rooms/$room/messages?dir=b&limit=$n" \
          | jq -c '[.chunk[] | select(.type=="m.room.message")] | reverse[]
                   | {ts:.origin_server_ts, sender, body:.content.body, event_id}'
      '';
    })
    # matrix-rooms   -> accept pending invites, then list joined rooms as "id<TAB>name"
    (pkgs.writeShellApplication {
      name = "matrix-rooms";
      runtimeInputs = [
        pkgs.curl
        pkgs.jq
      ];
      text = prelude + ''
        api "$hs/_matrix/client/v3/sync?filter=%7B%22room%22%3A%7B%22timeline%22%3A%7B%22limit%22%3A0%7D%7D%7D&timeout=0" \
          | jq -r '.rooms.invite // {} | keys[]' \
          | while read -r r; do api -X POST "$hs/_matrix/client/v3/join/$r" >/dev/null && echo "joined $r" >&2; done
        for r in $(api "$hs/_matrix/client/v3/joined_rooms" | jq -r '.joined_rooms[]'); do
          printf '%s\t%s\n' "$r" "$(api "$hs/_matrix/client/v3/rooms/$r/state/m.room.name" 2>/dev/null | jq -r .name || true)"
        done
      '';
    })
  ];
}
