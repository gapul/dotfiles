#!/usr/bin/env bash
# NixOS laptop only. Temporarily use the local uplink and unfiltered Quad9 DoT.
# Run with sudo; `off` restores the saved Tailscale exit node and DNS timer.
set -euo pipefail
# jq is installed by Home Manager rather than in root's default sudo PATH.
export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/gapul/bin:/usr/bin:/bin

[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
state=/run/affiliate-network
override=/run/systemd/resolved.conf.d/90-affiliate-network.conf
exec 9>/run/affiliate-network.lock
flock 9

restore() {
  [[ -d $state ]] || return 0
  rm -f "$override"
  systemctl restart systemd-resolved
  tailscale set --exit-node="$(cat "$state/exit-node")"
  if [[ $(cat "$state/timer") == active ]]; then
    systemctl start resolved-prefer-home.timer
  fi
  rm -rf "$state"
}

case "${1:-status}" in
  on)
    if [[ -d $state ]]; then
      echo 'Already enabled. Run off to restore first.' >&2
      exit 1
    fi
    prefs=$(tailscale debug prefs)
    exit_ip=$(jq -r '.ExitNodeIP // ""' <<<"$prefs")
    exit_id=$(jq -r '.ExitNodeID // ""' <<<"$prefs")
    if [[ -z $exit_ip && -n $exit_id ]]; then
      exit_ip=$(tailscale status --json | jq -r --arg id "$exit_id" \
        '[.Peer[] | select(.ID == $id) | .TailscaleIPs[0]][0] // empty')
      [[ -n $exit_ip ]] || { echo 'Cannot identify current exit node.' >&2; exit 1; }
    fi
    [[ ! -e $override ]] || { echo "Unexpected existing $override" >&2; exit 1; }
    umask 077
    mkdir "$state"
    printf '%s\n' "$exit_ip" > "$state/exit-node"
    (systemctl is-active resolved-prefer-home.timer || true) > "$state/timer"
    # shellcheck disable=SC2154 # rc is assigned inside the trap string
    trap 'rc=$?; trap - EXIT INT TERM; if (( rc != 0 )); then echo "Setup interrupted; restoring network." >&2; restore; fi; exit "$rc"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    systemctl stop resolved-prefer-home.timer resolved-prefer-home.service
    mkdir -p /run/systemd/resolved.conf.d
    chmod 755 /run/systemd/resolved.conf.d
    cat > "$override" <<'EOF'
[Resolve]
DNS=
DNS=9.9.9.10#dns10.quad9.net 149.112.112.10#dns10.quad9.net
FallbackDNS=
DNSOverTLS=true
EOF
    chmod 644 "$override"
    tailscale set --exit-node=
    systemctl restart systemd-resolved
    trap - EXIT INT TERM
    echo 'Local uplink + unfiltered Quad9 DoT enabled for this boot. Run off after applying.'
    ;;
  off) restore ;;
  status)
    if [[ -d $state ]]; then echo 'Application network mode: on'; else echo 'Application network mode: off'; fi
    resolvectl status --no-pager
    ;;
  *) echo 'usage: affiliate-network.sh [on|off|status]' >&2; exit 2 ;;
esac
