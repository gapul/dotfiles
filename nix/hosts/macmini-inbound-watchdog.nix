{
  lib,
  pkgs,
  ...
}:
# The mini went deaf twice: 2026-11-15 from 20:13:56 and 2026-11-16 from 00:00, each until someone
# held the power button. The box kept running (logs, outbound, local ssh from hermes to hsandbox),
# but every non-loopback listener completed the TCP handshake and went silent; only tailscaled's
# own :8080 answered, and the application firewall's "Incoming flow identified as launchd" lines
# stopped dead. It was the 2026-09-26 failure again (see the end of darwin-common.nix): at 20:13:56
# an agent ran `sudo nix store optimise` on the mini to free disk, the hardlinks put blocky's
# binary at /nix/store/.links/<hash> (socketfilterfw logged that path from 20:17), and the
# firewall's serial per-flow queue drowned walking the 700k-entry directory. The reboot at 22:23
# left .links in place, so it stalled again overnight. The linux builder VM that booted at
# 00:00:20 was a coincidence: six parallel builds on 2026-11-16 did not reproduce it.
#
# So every run first clears a populated .links (killing a running optimise) and restarts
# socketfilterfw, the documented recovery, before inbound ever stalls. Then it asks homeserver to
# key-scan the mini over the tailnet, since outbound keeps working in that state. Three misses
# (homeserver reachable, the mini's sshd not) repeat the recovery and toggle the firewall; three
# more reboot. A miss where homeserver itself does not answer counts for nothing, so a homeserver
# or house outage never reboots this machine.
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

      # .links is only nix's dedup index; nix recreates it empty, which is harmless.
      clear_links() {
        /usr/bin/find /nix/store/.links -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | /usr/bin/grep -q . || return 1
        /usr/bin/pkill -f 'nix store optimise' || true
        /usr/bin/pkill -f 'nix-store --optimise' || true
        /bin/rm -rf /nix/store/.links
        /usr/bin/pkill -x socketfilterfw || true
        return 0
      }

      if clear_links; then
        log "cleared a populated /nix/store/.links and restarted socketfilterfw"
        notify "/nix/store/.links had entries (someone ran nix store optimise?); cleared it and restarted the firewall"
        sleep 5
      fi

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
        log "last ALF inbound flow in 30m: ''${last_in:-none}; restarting socketfilterfw and toggling the firewall"
        clear_links || /usr/bin/pkill -x socketfilterfw || true
        sleep 3
        "$fw" --setglobalstate off >/dev/null 2>&1
        sleep 3
        "$fw" --setglobalstate on >/dev/null 2>&1
        sleep 5
        if probe; then
          log "firewall restart restored inbound"
          notify "inbound was dead; restarting the application firewall restored it (last ALF inbound: ''${last_in:-none})"
          echo 0 > "$state_dir/failures"
        else
          log "firewall restart did not help"
          notify "inbound is dead and the firewall restart did not help; rebooting after 3 more misses"
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
