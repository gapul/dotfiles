{ nixLinuxBuilder, ... }:
# input-output-hk/nix-linux-builder: a FOSS (Apache-2.0) Linux builder that plugs into Nix's
# `external-builders` hook. Each Linux build boots a short-lived Virtualization.framework VM that
# mounts the host /nix/store over VirtioFS and writes its outputs straight into it, with x86_64-linux
# going through Rosetta. It replaced cpick/nix-rosetta-builder (2026-10-10), a long-lived Lima VM
# whose disk held a second store that had grown to 54 GB; here there is no such disk, and the
# outputs are collected by the host's own GC.
#
# It is the open replacement for Determinate's native Linux builder, which is closed source and
# rolled out per account through the telemetry turned off in darwin-telemetry.nix.
#
# The module declares its nix.conf lines through nix.settings, which nothing writes while
# nix.enable = false (Determinate owns nix.conf); darwin-common.nix carries them into
# nix.custom.conf. Its preActivation copies the host binary to /usr/local/lib/nix-linux-builder
# and ad-hoc signs it with the virtualization entitlement, which the store copy loses.
{
  imports = [ nixLinuxBuilder.darwinModules.default ];

  services.nix-linux-builder = {
    enable = true;
    # One VM per build, and max-jobs = 2 here (flake.nix), so two can run at once. The resident
    # models hold most of the 24 GB; 6 GiB each keeps the worst case at 12 GiB. Four vCPUs matches
    # cores = 4.
    memorySize = 6 * 1024 * 1024 * 1024;
    cpuCount = 4;
  };
}
