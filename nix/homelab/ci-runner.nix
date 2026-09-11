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
# the runner keeps its own credentials under StateDirectory.
{ lib, pkgs, ... }:
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

    # This runner ships only externals/node24, while pinned actions still declare
    # `using: node20` — the JS step then dies with ENOENT on a node that was never
    # installed. GitHub's hosted runners remap it; this makes ours do the same instead
    # of pinning every action to a version GitHub is retiring anyway.
    extraEnvironment.ACTIONS_RUNNER_FORCE_ACTIONS_NODE_VERSION = "node24";

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
}
