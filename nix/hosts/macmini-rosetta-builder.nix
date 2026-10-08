{ rosettaBuilder, ... }:
# A Linux builder VM (Lima, Apple Virtualization, Rosetta 2) so this machine can build
# x86_64-linux and aarch64-linux itself. The point is nixos-laptop: its closure used to reach
# cachix only through om-ci on GitHub's linux runner, which kept getting killed, so the laptop
# compiled rustdesk and friends locally on every rebuild. Under Rosetta an x86_64-linux build
# here runs far faster than on a 4-vCPU hosted runner or on the homeserver, and the store
# persists between runs.
#
# Rosetta itself is a one-time `softwareupdate --install-rosetta --agree-to-license`.
# The first activation builds the VM image, which is an aarch64-linux derivation, so it needs a
# Linux builder that already exists: nixpkgs' darwin.linux-builder (`nix run
# nixpkgs#darwin.linux-builder`, registered by hand in nix.custom.conf) was used once on
# 2026-10-08 and then removed.
#
# The module also declares nix.buildMachines, which is inert here (nix.enable = false: Determinate
# owns nix.conf). The builders line that the daemon actually reads is in flake.nix's nixCustomConf
# for the macmini.
{
  imports = [ rosettaBuilder.darwinModules.default ];

  nix-rosetta-builder = {
    # The resident models hold most of the 24 GB, so the VM boots when a Linux build asks for
    # it and powers off after it has been idle, instead of keeping 8 GiB pinned all day.
    onDemand = true;
    onDemandLingerMinutes = 30;
    cores = 6;
    memory = "8GiB";
    diskSize = "120GiB";
  };
}
