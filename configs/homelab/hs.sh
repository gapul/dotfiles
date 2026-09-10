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
  hs forms list|get|create|update|delete|responses|export [ARG...]
  hs share create SHARE_ID EXPIRATION FILE [FILE...]
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
Formera uses HS_FORMERA_EMAIL and HS_FORMERA_PASSWORD to obtain a short-lived
bearer token; the token itself is never stored.
EOF
}

need_app() {
  local app="${1:-}" wake_app wake_url
  [[ -n "$app" ]] || { usage >&2; exit 2; }
  podman container exists "$app" && return 0

  # Socket-activated containers do not exist while asleep. Wake the owning
  # HTTP group, then wait for the ordinary podman operation to become possible.
  case "$app" in
    formera-backend) wake_app=formera ;;
    formera-frontend) wake_url=http://127.0.0.1:8101 ;;
    gameyfin|jellyfin|pingvin-share|rallly|romm|spliit) wake_app="$app" ;;
    rallly-db) wake_app=rallly ;;
    romm-db) wake_app=romm ;;
    spliit-db) wake_app=spliit ;;
    *) echo "unknown container: $app" >&2; exit 2 ;;
  esac
  wake_url="${wake_url:-$(base_url "$wake_app")}"
  curl -sS -o /dev/null --max-time 150 "$wake_url/" || true
  for _ in {1..120}; do
    podman container exists "$app" && return 0
    sleep 1
  done
  echo "container did not wake: $app" >&2
  exit 1
}

known_unit() {
  systemctl cat "podman-$1.service" >/dev/null 2>&1
}

base_url() {
  case "$1" in
    archivebox) echo http://127.0.0.1:8000 ;;
    bambuddy) echo http://127.0.0.1:8010 ;;
    calnode) echo http://127.0.0.1:8086 ;;
    dawarich) echo http://127.0.0.1:3005 ;;
    filestash) echo http://127.0.0.1:8099 ;;
    formera) echo http://127.0.0.1:8100 ;;
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

formera_token() {
  local login_body
  [[ -n "${HS_FORMERA_EMAIL:-}" && -n "${HS_FORMERA_PASSWORD:-}" ]] || {
    echo "HS_FORMERA_EMAIL and HS_FORMERA_PASSWORD are required" >&2
    return 1
  }
  login_body="$(jq -nc \
    --arg email "$HS_FORMERA_EMAIL" \
    --arg password "$HS_FORMERA_PASSWORD" \
    '{email: $email, password: $password}')"
  curl -fsS -H "Content-Type: application/json" --data-binary "$login_body" \
    "$(base_url formera)/api/auth/login" | jq -er .token
}

api_token() {
  local key value
  key="HS_${1^^}_TOKEN"
  key="${key//-/_}"
  value="${!key:-}"
  printf '%s' "$value"
}

pingvin_cookie() {
  local response access_token login_body
  [[ -n "${HS_PINGVIN_SHARE_EMAIL:-}" && -n "${HS_PINGVIN_SHARE_PASSWORD:-}" ]] || {
    echo "HS_PINGVIN_SHARE_EMAIL and HS_PINGVIN_SHARE_PASSWORD are required" >&2
    return 1
  }
  response="$(mktemp)"
  trap 'rm -f "$response"' RETURN
  login_body="$(jq -nc \
    --arg email "$HS_PINGVIN_SHARE_EMAIL" \
    --arg password "$HS_PINGVIN_SHARE_PASSWORD" \
    '{email: $email, password: $password}')"
  curl -fsS -H "Content-Type: application/json" --data-binary "$login_body" \
    "$(base_url pingvin-share)/api/auth/signIn" >"$response"
  access_token="$(jq -er .accessToken "$response")"
  printf 'access_token=%s' "$access_token"
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

  if [[ "$app" == pingvin-share && -z "$token" && -z "$cookie" && \
    -n "${HS_PINGVIN_SHARE_EMAIL:-}" && -n "${HS_PINGVIN_SHARE_PASSWORD:-}" ]]; then
    args+=(-H "Cookie: $(pingvin_cookie)")
  fi
  if [[ "$app" == formera && -z "$token" ]]; then
    args+=(-H "Authorization: Bearer $(formera_token)")
  fi
  if [[ -n "$body" ]]; then
    jq -e . <<<"$body" >/dev/null
    args+=(-H "Content-Type: application/json" --data-binary "$body")
  fi
  response="$(mktemp)"
  trap 'rm -f "${response:-}"' RETURN
  curl "${args[@]}" -o "$response" "$(base_url "$app")$path"
  if jq -e . "$response" >/dev/null 2>&1; then
    jq -C . "$response"
  else
    cat "$response"
  fi
}

pingvin_share_create() {
  local share_id="$1" expiration="$2" cookie chunk chunk_size total_size body
  local file name encoded_name file_id size total index
  shift 2
  [[ $# -gt 0 ]] || { usage >&2; return 2; }
  [[ "$share_id" =~ ^[a-zA-Z0-9_-]{3,50}$ ]] || {
    echo "share ID must be 3-50 letters, digits, underscores, or hyphens" >&2
    return 2
  }
  total_size=0
  for file in "$@"; do
    [[ -f "$file" ]] || { echo "not a file: $file" >&2; return 2; }
    total_size=$((total_size + $(stat -c %s "$file")))
  done

  cookie="$(pingvin_cookie)"
  chunk_size="$(curl -fsS "$(base_url pingvin-share)/api/configs" | \
    jq -er '.[] | select(.key == "share.chunkSize") | .value | tonumber')"
  body="$(jq -nc --arg id "$share_id" --arg name "${share_id:0:30}" \
    --arg expiration "$expiration" --argjson size "$total_size" \
    '{id:$id,name:$name,expiration:$expiration,description:"",recipients:[],security:{},size:$size}')"
  curl -fsS -H "Cookie: $cookie" -H "Content-Type: application/json" \
    --data-binary "$body" "$(base_url pingvin-share)/api/shares" >/dev/null

  chunk="$(mktemp)"
  trap 'rm -f "$chunk"' RETURN
  for file in "$@"; do
    name="$(basename "$file")"
    encoded_name="$(jq -rn --arg value "$name" '$value | @uri')"
    file_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    size="$(stat -c %s "$file")"
    total=$(((size + chunk_size - 1) / chunk_size))
    for ((index = 0; index < total; index++)); do
      dd if="$file" of="$chunk" bs="$chunk_size" skip="$index" count=1 \
        iflag=fullblock status=none
      curl -fsS -H "Cookie: $cookie" -H "Content-Type: application/octet-stream" \
        --data-binary "@$chunk" \
        "$(base_url pingvin-share)/api/shares/$share_id/files?id=$file_id&name=$encoded_name&chunkIndex=$index&totalChunks=$total" \
        >/dev/null
      printf '%s: %d/%d chunks\n' "$name" "$((index + 1))" "$total"
    done
  done
  curl -fsS -X POST -H "Cookie: $cookie" \
    "$(base_url pingvin-share)/api/shares/$share_id/complete" >/dev/null
  printf 'https://send.gapul.net/share/%s\n' "$share_id"
}

formera_export() {
  local form_id="$1" format="$2" output="${3:--}" token
  [[ "$format" == csv || "$format" == json ]] || {
    echo "export format must be csv or json" >&2
    return 2
  }
  token="$(formera_token)"
  if [[ "$output" == - ]]; then
    curl -fsS -H "Authorization: Bearer $token" \
      "$(base_url formera)/api/forms/$form_id/export/$format"
  else
    curl -fsS -H "Authorization: Bearer $token" -o "$output" \
      "$(base_url formera)/api/forms/$form_id/export/$format"
    printf '%s\n' "$output"
  fi
}

formera_forms() {
  local action="${1:-}" form_id file format output body
  shift || true
  case "$action" in
    list) api formera GET '/api/forms?page_size=100' ;;
    get)
      form_id="${1:-}"; [[ -n "$form_id" ]] || { usage >&2; return 2; }
      api formera GET "/api/forms/$form_id"
      ;;
    create)
      file="${1:-}"; [[ -f "$file" ]] || { echo "not a JSON file: $file" >&2; return 2; }
      body="$(jq -c . "$file")"
      api formera POST /api/forms "$body"
      ;;
    update)
      form_id="${1:-}"; file="${2:-}"
      [[ -n "$form_id" && -f "$file" ]] || { usage >&2; return 2; }
      body="$(jq -c . "$file")"
      api formera PUT "/api/forms/$form_id" "$body"
      ;;
    delete)
      form_id="${1:-}"; [[ -n "$form_id" ]] || { usage >&2; return 2; }
      api formera DELETE "/api/forms/$form_id"
      ;;
    responses)
      form_id="${1:-}"; [[ -n "$form_id" ]] || { usage >&2; return 2; }
      api formera GET "/api/forms/$form_id/submissions?page_size=100"
      ;;
    export)
      form_id="${1:-}"; format="${2:-}"; output="${3:--}"
      [[ -n "$form_id" && -n "$format" ]] || { usage >&2; return 2; }
      formera_export "$form_id" "$format" "$output"
      ;;
    *) usage >&2; return 2 ;;
  esac
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
      if podman container exists "$1"; then
        podman inspect "$1" | jq -C '.[0] | {name:.Name,image:.ImageName,state:.State.Status,health:.State.Health.Status,restarts:.RestartCount,mounts:.Mounts}'
      elif known_unit "$1"; then
        jq -nC --arg name "$1" '{name:$name,state:"sleeping"}'
      else
        echo "unknown container: $1" >&2
        exit 2
      fi
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
    if [[ -z "${1:-}" ]] || ! known_unit "$1"; then
      usage >&2
      exit 2
    fi
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
      formera) curl -fsS "$(base_url formera)/swagger/doc.json" | jq -C . ;;
      # Rallly publishes the private schema even on self-hosted installations.
      # API-key creation is intentionally not bypassed here when upstream's
      # licence/feature gate disables it.
      rallly) api "$app" GET /api/private/openapi ;;
      *) echo "OpenAPI location is not registered for: $app" >&2; exit 2 ;;
    esac
    ;;
  forms) formera_forms "$@" ;;
  share)
    action="${1:-}"
    shift || true
    case "$action" in
      create)
        [[ $# -ge 3 ]] || { usage >&2; exit 2; }
        pingvin_share_create "$@"
        ;;
      *) usage >&2; exit 2 ;;
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
