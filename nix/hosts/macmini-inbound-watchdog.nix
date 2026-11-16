{
  lib,
  pkgs,
  ...
}:
# The mini went deaf twice: 2026-11-15 from 20:13 and 2026-11-16 from 00:00, each until someone
# held the power button. The box itself kept running (logs flowing, outbound fine, local ssh from
# hermes to hsandbox working), but nothing from the network reached a socket: TCP to 22/3773/5900
# completed the handshake and then hung, and only tailscaled's own :8080 answered. In the unified
# log the application firewall's "Incoming flow identified as launchd" lines stop dead at the
# start of each outage, so inbound flows were held before the socketfilterfw content filter
# ever gave a verdict. The 11-16 one began 5 s after nix-linux-builder booted a VM and
# InternetSharing created its vmnet interfaces; the 11-15 one had no VM, so that is not the
# whole story.
#
# Outbound still works in that state, so the mini can ask homeserver to look back at it. Three
# misses in a row (homeserver reachable, the mini's sshd not) toggle the firewall off and on,
# which also tells us whether the firewall was the culprit; three more and it reboots. A miss
# where homeserver itself does not answer counts for nothing, so a homeserver or house outage
# never reboots this machine.
let
  stateDir = "/var/db/macmini-inbound-watchdog";
  logFile = "/var/log/macmini-inbound-watchdog.log";
  self = "100.105.135.49";

  watchdog = pkgs.writeShellApplication {
    name = "macmini-inbound-watchdog";
    bashOptions = [ "nounset" ];
    text = ''
      state_dir=${lib.escapeShellArg stateDir}
      fw=/usr/libexec/ApplicationFirewall/socketfilterfw
      mkdir -p "$state_dir"

      log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

      notify() {
        local url_file=/Users/gapul/.config/ntfy/url token_file=/Users/gapul/.config/ntfy/token
        [ -r "$url_file" ] && [ -r "$token_file" ] || return 0
        /usr/bin/curl -fsS --max-time 15 -H "Authorization: Bearer $(cat "$token_file")" \
          -H "Title: inbound-watchdog (macmini)" -H "Tags: warning" -d "$1" "$(cat "$url_file")" \
          >/dev/null 2>&1 || true
      }

      # A full key exchange through the tailnet, so sshd must actually be spawned and answer.
      # Exit 0 = reachable, 1 = homeserver answered but the mini did not, 2 = homeserver itself
      # unreachable (no verdict).
      probe() {
        local out
        out=$(/usr/bin/sudo -u gapul -H /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 \
          -o ServerAliveInterval=5 -o ServerAliveCountMax=3 homeserver \
          "ssh-keyscan -T 10 -t ed25519 ${self} 2>/dev/null; echo PROBE-DONE" 2>/dev/null) || return 2
        case "$out" in *PROBE-DONE*) ;; *) return 2 ;; esac
        case "$out" in *ssh-ed25519*) return 0 ;; *) return 1 ;; esac
      }

      read_num() { local v=0; [ -r "$1" ] && v=$(<"$1"); [[ "$v" =~ ^[0-9]+$ ]] || v=0; echo "$v"; }

      probe
      rc=$?
      failures=$(read_num "$state_dir/failures")

      if [ "$rc" -eq 2 ]; then
        exit 0
      fi
      if [ "$rc" -eq 0 ]; then
        if [ "$failures" -gt 0 ]; then
          log "reachable again after $failures misses"
          [ "$failures" -ge 3 ] && notify "inbound reachable again after $failures misses"
        fi
        echo 0 > "$state_dir/failures"
        exit 0
      fi

      failures=$((failures + 1))
      echo "$failures" > "$state_dir/failures"
      log "miss $failures: homeserver up, ${self}:22 gave no key"

      if [ "$failures" -eq 3 ]; then
        last_in=$(/usr/bin/log show --style compact --info --debug --last 30m \
          --predicate 'process == "socketfilterfw" AND eventMessage CONTAINS "Incoming flow"' \
          2>/dev/null | /usr/bin/grep '^20' | /usr/bin/tail -1 | /usr/bin/cut -c1-23)
        log "last ALF inbound flow in 30m: ''${last_in:-none}; toggling the application firewall"
        "$fw" --setglobalstate off >/dev/null 2>&1
        sleep 3
        "$fw" --setglobalstate on >/dev/null 2>&1
        sleep 5
        if probe; then
          log "ALF toggle restored inbound"
          notify "inbound was dead; toggling the application firewall restored it (last ALF inbound: ''${last_in:-none})"
          echo 0 > "$state_dir/failures"
        else
          log "ALF toggle did not help"
          notify "inbound is dead and the ALF toggle did not help; rebooting after 3 more misses"
        fi
        exit 0
      fi

      if [ "$failures" -ge 6 ]; then
        boot=$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -E 's/.*sec = ([0-9]+).*/\1/')
        now=$(date +%s)
        last_reboot=$(read_num "$state_dir/last-reboot")
        if [ $((now - boot)) -lt 1800 ]; then
          log "would reboot, but up less than 30 min"
        elif [ $((now - last_reboot)) -lt 21600 ]; then
          log "would reboot, but already rebooted within 6 h"
        else
          echo "$now" > "$state_dir/last-reboot"
          echo 0 > "$state_dir/failures"
          log "rebooting"
          notify "inbound dead for $failures checks; rebooting"
          sleep 5
          /sbin/shutdown -r now "macmini-inbound-watchdog"
        fi
      fi
    '';
  };
in
{
  launchd.daemons.macmini-inbound-watchdog = {
    # `command` so nix-darwin wraps it in wait4path (see macmini-homeserver-monitor.nix).
    command = lib.getExe watchdog;
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 120;
      ProcessType = "Background";
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };

  system.activationScripts.preActivation.text = lib.mkAfter ''
    /bin/mkdir -p ${stateDir}
    /bin/chmod 0700 ${stateDir}
  '';
}
