#!/usr/bin/env bash
set -euo pipefail

failures=()

probe() {
  local name="$1" url="$2" expected="$3" code
  code="$(curl -sS -o /dev/null --max-time 15 -w '%{http_code}' "$url" || true)"
  if [[ ! "$code" =~ $expected ]]; then
    failures+=("$name: HTTP $code ($url)")
    printf 'NG  %-18s HTTP %s\n' "$name" "$code"
  else
    printf 'OK  %-18s HTTP %s\n' "$name" "$code"
  fi
}

# Public specifications where upstream provides one, otherwise a stable API or
# auth boundary.  401/403 proves the route exists without storing credentials in
# this health check.
probe bambuddy http://127.0.0.1:8010/openapi.json '^200$'
probe romm http://127.0.0.1:8091/openapi.json '^200$'
probe rallly http://127.0.0.1:8089/api/private/openapi '^200$'
probe pingvin-share http://127.0.0.1:8094/api/configs '^200$'
probe calnode http://127.0.0.1:8086/mcp '^(400|401|405)$'
probe homeassistant http://127.0.0.1:8123/api/ '^401$'
probe readeck http://127.0.0.1:8087/api/profile '^(401|403)$'
probe spliit http://127.0.0.1:8090/api/health '^200$'
probe syncthing http://127.0.0.1:8384/rest/system/status '^(200|403)$'

if (( ${#failures[@]} )); then
  printf '%s\n' "${failures[@]}" >&2
  exit 1
fi
