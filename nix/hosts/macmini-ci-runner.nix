# Run darwin CI on this machine.
#
# GitHub's macos-14 runners start with an empty nix store every time, so they rebuild carla and
# breeze-icons from source. Measured on 2026-08-31 it varied from 4 to 31 minutes, and once it
# timed out. Each time I had to force it through with --admin, or argue "this PR cannot possibly
# break" by showing the drvPath was identical to main.
#
# Here the store stays warm, so from the second run on it is evaluation only. It is an M4, so the
# raw speed also beats macos-14 (Intel generation).
#
# ## Why not services.github-runners
#
# That module requires nix.enable, but on this machine Determinate Nix owns /etc/nix/nix.conf, so
# nix.enable = false (darwin-common.nix). The premises don't fit.
#
# What it requires is also unnecessary in this setup. The module wants it in order to add the
# runner to trusted-users, but darwin-common.nix already takes the design "avoid trusted-user
# since it is root-equivalent; make substituters apply to all users via root-owned lines". The
# runner can pull from cachix as is.
#
# ## Using self-hosted on a public repository
#
# The default danger is that anyone opening a PR runs arbitrary code on this machine. It is closed:
#
#   - The repository requires approval for fork PRs from all_external_contributors (2026-08-31).
#     The default first_time_contributors means "free from then on once one PR has passed", which
#     is not enough.
#   - ci.yml pins actions by SHA.
#
# Isolation via a dedicated user was given up (see the let below). macOS refuses to create users
# over SSH, and allowing it would mean granting Full Disk Access to all of SSH.
#
# There have been zero PRs from other people's forks so far. Closing this is about the path, not
# the track record.
#
# ## Why not ephemeral
#
# Making it disposable per job requires re-registering each time, and registration tokens expire
# after an hour, so a PAT would have to live here. Since approval now applies to every external
# contributor, only my own code runs here, so keeping the store warm by staying resident wins over
# worrying about leftovers.
{ lib, pkgs, ... }:
let
  # Could not use a dedicated user. macOS does not let a rebuild over SSH create users
  # ("users cannot be create over SSH without Full Disk Access"). This machine runs headless, so
  # getting past that means giving Remote Login Full Disk Access. That setting applies to every
  # program over SSH, which does not balance against the isolation a dedicated user would give.
  #
  # Dropping the isolation is acceptable because GitHub now requires approval for fork PRs from
  # all_external_contributors, so only my own code runs here. In addition, ci.yml pins actions by
  # SHA.
  #
  # To bring the isolation back, enable "Allow full disk access for remote users" under
  # System Settings > General > Sharing > Remote Login, then switch back to a dedicated user.
  user = "gapul";
  home = "/Users/${user}";
  # The runner copied out of the store (see postActivation) is data; what config.sh writes
  # (.runner, .credentials, _work, _diag, self-updated bin.*) goes to RUNNER_ROOT, which nixpkgs'
  # wrapper otherwise defaults to ~/.github-runner. Both lived in ~ until 2026-10-18.
  workDir = "${home}/.local/share/github-runner";
  stateDir = "${home}/.local/state/github-runner";
  legacyWorkDir = "${home}/actions-runner";
  legacyStateDir = "${home}/.github-runner";
  logFile = "${home}/Library/Logs/gh-runner.log";
  repo = "https://github.com/gapul/dotfiles";

  # Register if not yet registered, then just run. config.sh creates .runner, so its presence
  # tells the second and later runs apart.
  runner = pkgs.github-runner;

  runScript = pkgs.writeShellApplication {
    name = "gh-runner-macmini";
    text = ''
      export PATH=${
        pkgs.lib.makeBinPath [
          pkgs.git
          pkgs.curl
          pkgs.coreutils
          pkgs.gnutar
          pkgs.gzip
          pkgs.bash
        ]
      }:/usr/bin:/bin:/nix/var/nix/profiles/default/bin

      # One-time move of an existing registration. Done here rather than in activation because
      # launchd has already stopped the old runner by the time this starts, so nothing holds it.
      if [ ! -e ${stateDir} ] && [ -d ${legacyStateDir} ]; then
        mkdir -p "$(dirname ${stateDir})"
        mv ${legacyStateDir} ${stateDir}
      fi

      # postActivation installs this after launchd has already started the job; KeepAlive retries.
      cd ${workDir}

      # nixpkgs の github-runner は GitHub の配布物と構造が違い、config.sh も run.sh も
      # bin/ の下にある。トップに置かれているつもりで叩くと何も起きずに終わる。
      #
      # さらに、状態 (.runner / .credentials / _work) は実体のある場所ではなく
      # RUNNER_ROOT (${stateDir}) に書かれる。作業領域を見て「未設定」と判断すると、既に
      # 登録済みなのに config.sh を叩いて「already configured」で止まる。
      if [ ! -f ${stateDir}/.runner ]; then
        token=$(cat /var/lib/secrets/github-runner-token)
        ./bin/config.sh \
          --unattended --replace \
          --url ${repo} \
          --token "$token" \
          --name macmini \
          --labels macmini \
          --work _work
      fi

      exec ./bin/run.sh
    '';
  };
in
{
  # Unpack the runner itself. GitHub's distribution tries to update itself, so copy it from the
  # store into the work area and use that (the store is read-only).
  #
  # Also fix the registration token's permissions here. Placed by hand it tends to end up 0400 root,
  # but the runner runs as gapul and cannot read it. Then config.sh gets an empty string, and it
  # retries forever with only "Permission denied" in the log (hit on 2026-09-01).
  system.activationScripts.postActivation.text = ''
    if [ -f /var/lib/secrets/github-runner-token ]; then
      /usr/sbin/chown ${user} /var/lib/secrets/github-runner-token
      /bin/chmod 0400 /var/lib/secrets/github-runner-token
    fi

    if [ ! -x ${workDir}/bin/run.sh ]; then
      /usr/bin/install -d -o ${user} -g staff -m 0700 ${workDir}
      /usr/bin/ditto ${runner}/ ${workDir}/
      /usr/sbin/chown -R ${user}:staff ${workDir}
    fi
    # The old copy only held the store's runner and runner.log.
    if [ -x ${workDir}/bin/run.sh ] && [ -d ${legacyWorkDir} ]; then
      /bin/rm -rf ${legacyWorkDir}
    fi
  '';

  launchd.daemons.gh-runner = {
    script = "exec ${lib.getExe runScript}";
    serviceConfig = {
      Label = "org.nixos.gh-runner";
      RunAtLoad = true;
      KeepAlive = true;
      UserName = user;
      # Not workDir: on the first switch it does not exist yet when launchd starts the job, and a
      # missing WorkingDirectory fails with EX_CONFIG before the script can run.
      WorkingDirectory = home;
      # Isolate the CI runner's Nix cache from interactive and agent sessions to
      # reduce cross-process interference on fetcher-cache-v4.sqlite. Multiple CI
      # jobs still share this runner-specific database.
      EnvironmentVariables.NIX_CACHE_HOME = "${home}/.cache/github-runner/nix";
      EnvironmentVariables.RUNNER_ROOT = stateDir;
      # It runs as gapul, so it cannot write to /var/log. If the path is unwritable, launchd gives up
      # with EX_CONFIG before starting the process and leaves no log, so the cause is invisible
      # (hit on 2026-08-31; it just kept exiting 78).
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };
}
