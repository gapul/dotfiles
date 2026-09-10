{ pkgs, ... }:

let
  checkMemoryPressure = pkgs.writeShellScript "memory-pressure-alert" ''
    set -u

    state_dir=/var/lib/memory-pressure-alert
    state_file="$state_dir/state"
    low_count=0
    alerted=0
    recovery_count=0
    if [ -r "$state_file" ]; then
      # The file is written by this script and contains only integer assignments.
      . "$state_file"
    fi

    available_kib="$(${pkgs.gawk}/bin/awk '$1 == "MemAvailable:" { print $2 }' /proc/meminfo)"
    total_kib="$(${pkgs.gawk}/bin/awk '$1 == "MemTotal:" { print $2 }' /proc/meminfo)"
    swap_total_kib="$(${pkgs.gawk}/bin/awk '$1 == "SwapTotal:" { print $2 }' /proc/meminfo)"
    swap_free_kib="$(${pkgs.gawk}/bin/awk '$1 == "SwapFree:" { print $2 }' /proc/meminfo)"
    psi_some="$(${pkgs.gawk}/bin/awk '/^some / { for (i = 1; i <= NF; i++) if ($i ~ /^avg300=/) { sub(/^avg300=/, "", $i); print $i } }' /proc/pressure/memory)"
    psi_full="$(${pkgs.gawk}/bin/awk '/^full / { for (i = 1; i <= NF; i++) if ($i ~ /^avg300=/) { sub(/^avg300=/, "", $i); print $i } }' /proc/pressure/memory)"

    if [ "$available_kib" -lt 1572864 ]; then
      low_count=$((low_count + 1))
    else
      low_count=0
    fi

    psi_now="$(${pkgs.gawk}/bin/awk -v some="$psi_some" -v full="$psi_full" 'BEGIN { print (some >= 1.0 || full >= 0.5) ? 1 : 0 }')"
    pressure_now=0
    if [ "$low_count" -ge 2 ] || [ "$psi_now" -eq 1 ]; then
      pressure_now=1
    fi

    if [ "$alerted" -eq 1 ] && [ "$pressure_now" -eq 0 ] && [ "$available_kib" -ge 2097152 ]; then
      recovery_count=$((recovery_count + 1))
    else
      recovery_count=0
    fi

    notify() {
      title="$1"
      priority="$2"
      tags="$3"
      available_mib=$((available_kib / 1024))
      total_mib=$((total_kib / 1024))
      swap_used_mib=$(((swap_total_kib - swap_free_kib) / 1024))
      body="available=''${available_mib}MiB / total=''${total_mib}MiB; swap=''${swap_used_mib}MiB; PSI some=''${psi_some}% full=''${psi_full}% (5m average)"
      ${pkgs.curl}/bin/curl -fsS --max-time 15 \
        -H "Authorization: Bearer $NTFY_TOKEN" \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$body" \
        "http://127.0.0.1:8082/$NTFY_TOPIC" >/dev/null
    }

    if [ "$pressure_now" -eq 1 ] && [ "$alerted" -eq 0 ]; then
      if notify "Memory pressure on homeserver" high warning,memory; then
        alerted=1
        recovery_count=0
      fi
    elif [ "$alerted" -eq 1 ] && [ "$recovery_count" -ge 2 ]; then
      if notify "Memory pressure resolved on homeserver" default white_check_mark,memory; then
        alerted=0
        recovery_count=0
      fi
    fi

    tmp="$state_file.new"
    ${pkgs.coreutils}/bin/printf 'low_count=%s\nalerted=%s\nrecovery_count=%s\n' \
      "$low_count" "$alerted" "$recovery_count" > "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" "$state_file"
  '';
in
{
  systemd.services.memory-pressure-alert = {
    description = "Notify ntfy about sustained memory pressure";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "memory-pressure-alert";
      EnvironmentFile = "/var/lib/secrets/gatus.env";
      ExecStart = checkMemoryPressure;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.timers.memory-pressure-alert = {
    description = "Check homeserver memory pressure every five minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "30s";
      AccuracySec = "15s";
    };
  };
}
