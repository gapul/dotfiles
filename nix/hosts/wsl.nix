# NixOS running inside Windows (WSL2).
#
# It doesn't share an install with the real dual-boot NixOS (it simply can't: WSL2 doesn't
# boot a physical partition, it runs the rootfs inside a VHDX on Microsoft's kernel). What's
# shared is the configuration: home reads the same roles.wsl as the real machine and the Lab PC.
#
# The goal: "while booted into Windows to use Adobe, the usual shell and tools are available
# without rebooting". GUI is left to Windows; this stays CLI-only.
#
# How to build and install the tarball: docs/NIXOS_WSL.md.
{
  pkgs,
  lib,
  user,
  ...
}:
{
  wsl = {
    enable = true;
    defaultUser = user.username;
    # Inheriting the whole Windows PATH makes which/command -v pick up Windows executables,
    # which is confusing. Keep interop but stop the PATH pollution.
    interop.includePath = false;
    # Keep the ability to call Windows commands via /mnt/c (wslview calls cmd.exe).
    wslConf.interop.enabled = true;
    wslConf.automount.enabled = true;
  };

  # Same selective unfree as the real NixOS machine. Kept in line with mkWslPkgs on the
  # standalone HM side (otherwise the same roles.wsl fails eval only under the NixOS integration).
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
      "unity-cli"
    ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ user.username ];
  };

  # WSL follows the Windows clock, but keep log timestamps in line with the main Mac.
  time.timeZone = "Asia/Tokyo";

  users.users.${user.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };
  # home-manager places the zsh config, so the system side only enables the shell.
  programs.zsh.enable = true;

  # No bootloader or fileSystems needed (WSL provides the kernel and rootfs).
  system.stateVersion = "26.05";
}
