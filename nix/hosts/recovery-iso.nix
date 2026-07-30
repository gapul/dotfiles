{
  pkgs,
  lib,
  user,
  ...
}:
{
  image.fileName = lib.mkForce "gapul-nixos-recovery.iso";
  boot.zfs.forceImportRoot = false;

  networking.hostName = "nixos-recovery";
  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    age
    cryptsetup
    disko
    git
    gptfdisk
    jq
    neovim
    parted
    ripgrep
    sbctl
    sops
    tmux
  ];

  environment.etc."dotfiles-recovery/README.md".source = ../../docs/NIXOS_RECOVERY.md;

  environment.shellAliases = {
    recovery-guide = "less /etc/dotfiles-recovery/README.md";
    clone-dotfiles = "git clone https://github.com/${user.username}/dotfiles.git ~/.dotfiles";
  };

  # The installer is a public artifact, so it contains no private keys, SOPS-decrypted
  # data, or fixed passwords at all. SSH login is only used if a temporary key is added after boot.
  users.users.nixos.openssh.authorizedKeys.keys = [ ];

  system.stateVersion = "26.05";
}
