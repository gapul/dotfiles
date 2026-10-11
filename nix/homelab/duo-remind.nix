{ pkgs, ... }:
# Duolingo reminder: at 21:00 JST, if today's XP is still 0, push to ntfy. Days with
# practice stay silent, which is the one thing Duolingo's own reminders cannot do, and
# it is the only piece of the app worth keeping once the app itself is gone (web only).
#
# Also appends `date,xp,streak` to /var/lib/duo-remind/xp.csv so the learning log lives
# here rather than only on Duolingo.
#
# Uses the unofficial 2017-06-30 API with the browser's `jwt_token` cookie. The user id
# is the JWT's `sub` claim, so the env file needs only DUO_JWT (see README). The token
# lasts months; on 401/403 the script posts "token expired" instead of failing silently.
# If `xpGains` changes shape, fix the jq filter below.
let
  remind = pkgs.writeShellApplication {
    name = "duo-remind";
    runtimeInputs = with pkgs; [
      curl
      jq
      coreutils
    ];
    text = ''
      : "''${DUO_JWT:?DUO_JWT is required}"
      : "''${GATUS_PUSH_TOKEN:?GATUS_PUSH_TOKEN is required}"
      : "''${NTFY_TOKEN:?NTFY_TOKEN is required}"
      : "''${NTFY_TOPIC:?NTFY_TOPIC is required}"
      export TZ=Asia/Tokyo
      # gatus external endpoint (hosts/homeserver.nix): a heartbeat that alerts if no push
      # arrives within 25h, so a timer that never fires is noticed too.
      push() { curl -fsS --max-time 10 -o /dev/null -X POST \
        -H "Authorization: Bearer $GATUS_PUSH_TOKEN" \
        "http://127.0.0.1:8084/api/v1/endpoints/timers_duo-remind/external?success=$1&error=$2"; }
      on_exit() { rc=$?; [ "$rc" -eq 0 ] || push false "exit%20$rc" || true; }
      trap on_exit EXIT
      api=https://www.duolingo.com/2017-06-30
      log=/var/lib/duo-remind/xp.csv

      notify() { # title body priority
        curl -fsS --max-time 15 -o /dev/null \
          -H "Authorization: Bearer $NTFY_TOKEN" \
          -H "Title: $1" -H "Priority: $3" -H "Tags: books" \
          -d "$2" "http://127.0.0.1:8082/$NTFY_TOPIC"
      }

      # user id from the JWT payload (base64url, pad to a multiple of 4 for jq)
      payload=$(printf '%s' "$DUO_JWT" | cut -d. -f2 | tr '_-' '/+')
      case $(( ''${#payload} % 4 )) in 2) payload="$payload==";; 3) payload="$payload=";; esac
      uid=$(printf '%s' "$payload" | jq -Rr '@base64d | fromjson | .sub')
      [ -n "$uid" ] && [ "$uid" != null ] || { echo "cannot read sub from DUO_JWT" >&2; exit 1; }

      tmp=$(mktemp)
      code=$(curl -sS --max-time 20 -o "$tmp" -w '%{http_code}' \
        -A 'Mozilla/5.0 (X11; Linux x86_64) duo-remind/1.0' \
        -H "Authorization: Bearer $DUO_JWT" -H 'Accept: application/json' \
        "$api/users/$uid?fields=xpGains,streak")
      case "$code" in
        200) ;;
        401|403)
          notify 'Duolingo: トークン失効' 'duolingo.com の Cookie jwt_token を取り直して sops の duo-remind.env を更新' 4
          echo "HTTP $code: token rejected" >&2; exit 1 ;;
        *) echo "HTTP $code from Duolingo" >&2; exit 1 ;;
      esac

      day_start=$(date -d 'today 00:00' +%s)
      xp=$(jq --argjson s "$day_start" '[(.xpGains // [])[] | select(.time >= $s) | .xp] | add // 0' "$tmp")
      streak=$(jq -r '.streak // 0' "$tmp")
      rm -f "$tmp"

      [ -f "$log" ] || printf 'date,xp,streak\n' > "$log"
      printf '%s,%s,%s\n' "$(date +%F)" "$xp" "$streak" >> "$log"

      if [ "$xp" -eq 0 ]; then
        notify 'Duolingo まだ' "今日の XP は 0。連続 $streak 日が切れる。" 4
        echo "reminded (streak=$streak)"
      else
        echo "done today: xp=$xp streak=$streak"
      fi
      push true ""
    '';
  };
in
{
  systemd.services.duo-remind = {
    description = "Duolingo: 今日まだなら ntfy に通知";
    after = [
      "network-online.target"
      "podman-ntfy.service"
      "gatus.service"
    ];
    wants = [ "network-online.target" ];
    onFailure = [ "ntfy-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "duo-remind";
      EnvironmentFile = [
        "/var/lib/secrets/gatus.env" # NTFY_TOPIC, NTFY_TOKEN, GATUS_PUSH_TOKEN, shared with the other alerts
        "/var/lib/secrets/duo-remind.env" # DUO_JWT
      ];
      ExecStart = "${remind}/bin/duo-remind";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.timers.duo-remind = {
    description = "Duolingo reminder at 21:00 JST";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 21:00:00 Asia/Tokyo";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };
}
