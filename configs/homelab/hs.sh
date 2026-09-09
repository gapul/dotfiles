#!/usr/bin/env bash
set -euo pipefail

secrets=/var/lib/secrets/homelab-cli.env
if [[ -r "$secrets" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$secrets"
  set +a
fi

usage() {
  cat <<'EOF'
Usage:
  hs list
  hs status [app]
  hs unit status|logs|restart UNIT [ARG...]
  hs logs APP [journalctl options]
  hs restart APP
  hs exec APP COMMAND [ARG...]
  hs api APP METHOD PATH [JSON]
  hs openapi APP
  hs ytdl check|run|inspect [MATCH]
  hs navidrome COMMAND [ARG...]
  hs archivebox COMMAND [ARG...]
  hs forgejo COMMAND [ARG...]
  hs paperless COMMAND [ARG...]
  hs backup snapshots|check|run|restore-drill

API tokens are read from /var/lib/secrets/homelab-cli.env as
HS_<APP>_TOKEN (hyphens become underscores). Most use Bearer auth;
Miniflux, Paperless, and Bambuddy get their native header automatically.
Pingvin Share can instead use HS_PINGVIN_SHARE_EMAIL and
HS_PINGVIN_SHARE_PASSWORD; hs obtains a short-lived cookie automatically.
EOF
}

need_app() {
  [[ -n "${1:-}" ]] || { usage >&2; exit 2; }
  podman container exists "$1" || {
    echo "unknown container: $1" >&2
    exit 2
  }
}

base_url() {
  case "$1" in
    archivebox) echo http://127.0.0.1:8000 ;;
    bambuddy) echo http://127.0.0.1:8010 ;;
    calnode) echo http://127.0.0.1:8086 ;;
    dawarich) echo http://127.0.0.1:3005 ;;
    filestash) echo http://127.0.0.1:8099 ;;
    forgejo) echo http://127.0.0.1:3003 ;;
    gameyfin) echo http://127.0.0.1:8092 ;;
    homeassistant) echo http://127.0.0.1:8123 ;;
    jellyfin) echo http://127.0.0.1:8096 ;;
    miniflux) echo http://127.0.0.1:8081 ;;
    navidrome) echo http://127.0.0.1:4533 ;;
    ntfy) echo http://127.0.0.1:8082 ;;
    paperless) echo http://127.0.0.1:8097 ;;
    pingvin-share) echo http://127.0.0.1:8094 ;;
    radicale) echo http://127.0.0.1:5232 ;;
    rallly) echo http://127.0.0.1:8089 ;;
    readeck) echo http://127.0.0.1:8087 ;;
    romm) echo http://127.0.0.1:8091 ;;
    rsshub) echo http://127.0.0.1:1200 ;;
    spliit) echo http://127.0.0.1:8090 ;;
    syncthing) echo http://127.0.0.1:8384 ;;
    vaultwarden) echo http://127.0.0.1:8080 ;;
    *) echo "no API URL registered for: $1" >&2; exit 2 ;;
  esac
}

api_token() {
  local key value
  key="HS_${1^^}_TOKEN"
  key="${key//-/_}"
  value="${!key:-}"
  printf '%s' "$value"
}

api() {
  local app="$1" method="$2" path="$3" body="${4:-}" token cookie_key cookie
  local -a args
  token="$(api_token "$app")"
  args=(-fsS -X "$method" -H "Accept: application/json")
  if [[ -n "$token" ]]; then
    case "$app" in
      bambuddy) args+=(-H "X-API-Key: $token") ;;
      miniflux) args+=(-H "X-Auth-Token: $token") ;;
      paperless) args+=(-H "Authorization: Token $token") ;;
      syncthing) args+=(-H "X-API-Key: $token") ;;
      *) args+=(-H "Authorization: Bearer $token") ;;
    esac
  fi
  cookie_key="HS_${app^^}_COOKIE"
  cookie_key="${cookie_key//-/_}"
  cookie="${!cookie_key:-}"
  [[ -n "$cookie" ]] && args+=(-H "Cookie: $cookie")

  cookie_jar=""
  if [[ "$app" == pingvin-share && -z "$token" && -z "$cookie" && \
    -n "${HS_PINGVIN_SHARE_EMAIL:-}" && -n "${HS_PINGVIN_SHARE_PASSWORD:-}" ]]; then
    cookie_jar="$(mktemp)"
    trap 'rm -f "${cookie_jar:-}"' RETURN
    login_body="$(jq -nc \
      --arg email "$HS_PINGVIN_SHARE_EMAIL" \
      --arg password "$HS_PINGVIN_SHARE_PASSWORD" \
      '{email: $email, password: $password}')"
    curl -fsS -c "$cookie_jar" -H "Content-Type: application/json" \
      --data-binary "$login_body" "$(base_url "$app")/api/auth/signIn" >/dev/null
    args+=(-b "$cookie_jar")
  fi
  if [[ -n "$body" ]]; then
    jq -e . <<<"$body" >/dev/null
    args+=(-H "Content-Type: application/json" --data-binary "$body")
  fi
  response="$(mktemp)"
  trap 'rm -f "${cookie_jar:-}" "${response:-}"' RETURN
  curl "${args[@]}" -o "$response" "$(base_url "$app")$path"
  if jq -e . "$response" >/dev/null 2>&1; then
    jq -C . "$response"
  else
    cat "$response"
  fi
}

restic_cmd() {
  RESTIC_REPOSITORY=rclone:google-drive:restic-backup \
    RESTIC_PASSWORD_FILE=/var/lib/secrets/restic.password \
    RCLONE_CONFIG=/var/lib/secrets/rclone.conf \
    restic "$@"
}

command="${1:-}"
shift || true
case "$command" in
  list)
    podman ps --format json | jq -s -C 'sort_by(.Names) | .[] | {name:.Names,image:.Image,status:.Status}'
    ;;
  status)
    if [[ -n "${1:-}" ]]; then
      need_app "$1"
      podman inspect "$1" | jq -C '.[0] | {name:.Name,image:.ImageName,state:.State.Status,health:.State.Health.Status,restarts:.RestartCount,mounts:.Mounts}'
    else
      systemctl --no-pager --failed
      podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    fi
    ;;
  unit)
    action="${1:-}"; unit="${2:-}"
    [[ -n "$unit" ]] || { usage >&2; exit 2; }
    shift 2
    case "$action" in
      status) exec systemctl status --no-pager "$unit" "$@" ;;
      logs) exec journalctl -u "$unit" --no-pager "$@" ;;
      restart) exec systemctl restart "$unit" ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  logs)
    need_app "${1:-}"
    app="$1"; shift
    exec journalctl -u "podman-$app.service" --no-pager "$@"
    ;;
  restart)
    need_app "${1:-}"
    exec systemctl restart "podman-$1.service"
    ;;
  exec)
    need_app "${1:-}"
    app="$1"; shift
    [[ $# -gt 0 ]] || { usage >&2; exit 2; }
    exec podman exec -it "$app" "$@"
    ;;
  api)
    [[ $# -ge 3 ]] || { usage >&2; exit 2; }
    api "$@"
    ;;
  openapi)
    app="${1:-}"
    case "$app" in
      bambuddy|romm) api "$app" GET /openapi.json ;;
      # Rallly publishes the private schema even on self-hosted installations.
      # API-key creation is intentionally not bypassed here when upstream's
      # licence/feature gate disables it.
      rallly) api "$app" GET /api/private/openapi ;;
      *) echo "OpenAPI location is not registered for: $app" >&2; exit 2 ;;
    esac
    ;;
  ytdl)
    action="${1:-}"; match="${2:-}"
    config=/etc/homelab/ytdl-sub-config.yaml
    subscriptions=/etc/homelab/ytdl-sub-subscriptions.yaml
    match_args=()
    [[ -n "$match" ]] && match_args=(--match "$match")
    case "$action" in
      check) exec ytdl-sub --dry-run --config "$config" "${match_args[@]}" sub "$subscriptions" ;;
      run) exec ytdl-sub --config "$config" "${match_args[@]}" sub "$subscriptions" ;;
      inspect) exec ytdl-sub --config "$config" "${match_args[@]}" inspect "$subscriptions" ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  navidrome)
    [[ $# -gt 0 ]] || { usage >&2; exit 2; }
    exec podman exec -it navidrome /app/navidrome "$@"
    ;;
  archivebox)
    [[ $# -gt 0 ]] || { usage >&2; exit 2; }
    exec podman exec -it archivebox archivebox "$@"
    ;;
  forgejo)
    [[ $# -gt 0 ]] || { usage >&2; exit 2; }
    exec podman exec -u git -it forgejo forgejo "$@"
    ;;
  paperless)
    [[ $# -gt 0 ]] || { usage >&2; exit 2; }
    exec podman exec -it paperless python3 manage.py "$@"
    ;;
  backup)
    action="${1:-}"
    case "$action" in
      snapshots) restic_cmd snapshots --host "$(hostname -s)" ;;
      check) restic_cmd check ;;
      run) exec systemctl start restic-backups-homeserver.service ;;
      restore-drill) exec systemctl start restore-drill.service ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  help|-h|--help|"") usage ;;
  *) echo "unknown command: $command" >&2; usage >&2; exit 2 ;;
esac
