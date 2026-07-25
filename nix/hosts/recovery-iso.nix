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

  # インストーラーは公開成果物なので、秘密鍵・SOPS復号済みデータ・固定パスワードを
  # 一切含めない。SSHログインは起動後に一時鍵を追加した場合だけ利用する。
  users.users.nixos.openssh.authorizedKeys.keys = [ ];

  system.stateVersion = "26.05";
}
