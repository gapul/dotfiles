# GitHub Actions runner for pull requests only.
#
# ## Why this box gets a runner at all
#
# CI on a pull request builds `packages.<system>.pr-gate`, and that job is not computation — it is
# transfer. Measured 2026-09-10 on x86_64-linux: 1484 paths, 3.7 GiB down, 10.6 GiB unpacked, for
# a handful of derivations actually built. GitHub's runners start with an empty store every time,
# so they pay all of it, every run: 151s of a 2m31s job. A machine whose store persists pays it
# once. The same change on darwin took that job from 420s to 99s and then to 18s of build time.
#
# ## What it must never get
#
# `om ci run` on main. That one builds every output for the system — closures this host does not
# care about, VM tests, the lot — and it is what fills cachix. It is real computation, and this
# box runs 86 services people (and phones, and the tailnet) depend on. The split is in
# .github/workflows/ci.yml: `runs-on` picks this runner only for `pull_request`.
#
# The workflow deciding that is a convention, so the limits below are the part that holds when a
# pull request turns out to need a real build anyway — a flake.lock bump, a new package.
#
# ## The limits, and what they actually cover
#
# `CPUQuota` on this unit bounds what the runner process tree does: evaluation, git, the action's
# node. It does **not** bound a build, because builds happen in nix-daemon's cgroup, not this
# one. That is what `cores` and `max-jobs` in the environment are for — the daemon honours them
# per connection for a trusted user, so a build the runner asks for is confined to two cores and
# one job at a time. Together they leave half this machine free no matter what a pull request
# contains.
#
# ## Registration
#
# sops-nix has no age key on this host yet, so the token is placed by hand, the same way the
# other secrets here are:
#
#   gh api -X POST repos/gapul/dotfiles/actions/runners/registration-token --jq .token \
#     | sudo tee /var/lib/secrets/github-runner-token >/dev/null
#   sudo chmod 0400 /var/lib/secrets/github-runner-token
#
# The token is single-use and expires in an hour; it is only needed the first time, after which
# the runner keeps its own credentials under StateDirectory. Stopping the listener does not
# remove that state, so the autoscaler below can wake the same registration without another
# token.
{ lib, pkgs, ... }:
let
  runnerUnit = "github-runner-dotfiles-pr.service";
  runnerAutoscale = pkgs.writeShellApplication {
    name = "github-runner-autoscale";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      procps
      systemd
    ];
    text = ''
      set -u

      api=https://api.github.com/repos/gapul/dotfiles/actions
      idle_file=/run/github-runner-autoscale/idle-since

      fetch_json() {
        curl -fsS --retry 2 --retry-all-errors --max-time 20 \
          -H 'Accept: application/vnd.github+json' \
          -H 'X-GitHub-Api-Version: 2022-11-28' \
          -H 'User-Agent: gapul-homeserver-runner-autoscale' \
          "$1"
      }

      # The repository is public, so this costs no persistent credential. One
      # request every two minutes leaves half of GitHub's anonymous 60/hour
      # allowance unused; job-list requests happen only while a PR run is live.
      if ! runs="$(fetch_json "$api/runs?event=pull_request&per_page=10")" \
        || ! jq -e '.workflow_runs | arrays' <<<"$runs" >/dev/null; then
        echo "GitHub Actions API unavailable; leaving runner state unchanged" >&2
        exit 0
      fi

      queued=0
      while IFS= read -r run_id; do
        [ -n "$run_id" ] || continue
        if ! jobs="$(fetch_json "$api/runs/$run_id/jobs?per_page=100")" \
          || ! jq -e '.jobs | arrays' <<<"$jobs" >/dev/null; then
          echo "GitHub Actions jobs API unavailable; leaving runner state unchanged" >&2
          exit 0
        fi
        if jq -e 'any(.jobs[]?; .status == "queued" and any(.labels[]?; . == "homeserver"))' \
          <<<"$jobs" >/dev/null; then
          queued=1
          break
        fi
      done < <(
        jq -r '.workflow_runs[]? | select(.status == "queued" or .status == "in_progress") | .id' \
          <<<"$runs"
      )

      active=0
      if systemctl is-active --quiet ${runnerUnit}; then
        active=1
      fi

      # Runner.Worker exists only while a job is actually executing. A five
      # minute grace period covers the short gap between assignment and worker
      # spawn, as well as a second job queued immediately after the first.
      worker=0
      if pgrep -f '[R]unner.Worker' >/dev/null; then
        worker=1
      fi

      if [ "$queued" -eq 1 ]; then
        rm -f "$idle_file"
        if [ "$active" -eq 0 ]; then
          echo "queued homeserver job found; starting ${runnerUnit}"
          systemctl reset-failed ${runnerUnit} || true
          systemctl start --no-block ${runnerUnit}
        fi
        exit 0
      fi

      if [ "$active" -eq 0 ]; then
        rm -f "$idle_file"
        exit 0
      fi

      if [ "$worker" -eq 1 ]; then
        rm -f "$idle_file"
        exit 0
      fi

      now="$(date +%s)"
      if [ ! -r "$idle_file" ]; then
        printf '%s\n' "$now" > "$idle_file"
        exit 0
      fi
      idle_since="$(cat "$idle_file")"
      if [ -z "$idle_since" ]; then
        idle_since="$now"
      fi
      case "$idle_since" in
        *[!0-9]*) idle_since="$now" ;;
      esac
      if [ $((now - idle_since)) -ge 300 ]; then
        echo "runner idle for at least five minutes; stopping ${runnerUnit}"
        if systemctl stop ${runnerUnit}; then
          rm -f "$idle_file"
        fi
      fi
    '';
  };
in
{
  services.github-runners.dotfiles-pr = {
    enable = true;
    url = "https://github.com/gapul/dotfiles";
    tokenFile = "/var/lib/secrets/github-runner-token";
    name = "homeserver";
    # The workflow selects on this. Keep it in step with `pr_runner` in ci.yml.
    extraLabels = [ "homeserver" ];

    # The service starts with a nearly empty PATH, and the actions assume a normal machine.
    # First run died with exit 127 in the step that writes the deploy key — `ssh-keyscan` was
    # not there. The rest are what the standard actions shell out to: git for checkout, tar and
    # the compressors for actions/cache, curl for downloads.
    extraPackages = with pkgs; [
      openssh
      git
      gnutar
      gzip
      zstd
      curl
      which
    ];

    # Node 20 reached EOL, so nixpkgs dropped it and this package ships only
    # externals/node24. Several actions we pin still declare `using: node20`, and the
    # runner looks the runtime up by that literal name: the step dies before it starts,
    # with ENOENT on externals/node20/bin/node. GitHub's own runners no longer honour
    # ACTIONS_RUNNER_FORCE_ACTIONS_NODE_VERSION either (tried in #586, no effect) —
    # they just run those actions on 24. So point node20 at node24 and do the same.
    #
    # Chasing every action to a node24 release instead would be a moving target: the
    # installer and cachix actions are pinned by SHA on purpose.
    package = pkgs.github-runner.overrideAttrs (prev: {
      postInstall = prev.postInstall + ''
        ln -s ${pkgs.nodejs_24} $out/lib/externals/node20
      '';
    });

    serviceOverrides = {
      # Half the machine, at most, for everything outside the daemon.
      CPUQuota = "200%";
      # Yield to the services when there is contention rather than competing evenly.
      Nice = 10;
      IOSchedulingClass = "idle";
      # A runner has no business reaching the rest of this host.
      PrivateTmp = true;
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };

  # Applies to the nix commands the runner starts, and through them to what the daemon is asked
  # to do on its behalf. This is the half of the cap that survives a build.
  systemd.services.github-runner-dotfiles-pr.environment.NIX_CONFIG = lib.concatStringsSep "\n" [
    "cores = 2"
    "max-jobs = 1"
  ];

  # GitHub's listener costs roughly 180 MiB even when no job exists. Keep its
  # registration on disk, but let a transient API poller wake it only for a
  # queued PR job carrying the `homeserver` label.
  systemd.services.github-runner-dotfiles-pr.wantedBy = lib.mkForce [ ];

  systemd.services.github-runner-autoscale = {
    description = "Wake the GitHub Actions runner only for queued homeserver jobs";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe runnerAutoscale;
      RuntimeDirectory = "github-runner-autoscale";
      RuntimeDirectoryPreserve = "yes";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.timers.github-runner-autoscale = {
    description = "Check GitHub for queued homeserver jobs every two minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "2min";
      RandomizedDelaySec = "10s";
      AccuracySec = "5s";
    };
  };
}
