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

  # Both `disko --flake` and `nixos-install --flake` refuse to run without these.
  # The installer image does not enable them by default, so without this line the
  # install starts with "experimental Nix feature 'nix-command' is disabled" —
  # recoverable by passing --extra-experimental-features to every command, but a
  # bad thing to discover while standing at the machine.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # CI builds and pushes the hosts' closures here, so installing is a download
  # rather than an hour of compiling on the target. cache.gapul.net is
  # deliberately absent: it runs on the machine being installed.
  nix.settings.substituters = [
    "https://cache.nixos.org"
    "https://gapul-dotfiles.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "gapul-dotfiles.cachix.org-1:tGNGJ7SGHrLAjswSIz673st0AepuNjQombMJO0VUq98="
  ];

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
  # The home server install has no network to look things up from until tailscale
  # is authenticated, so carry its runbook on the medium itself.
  environment.etc."dotfiles-recovery/HOMESERVER_MIGRATION.md".source =
    ../../docs/HOMESERVER_MIGRATION.md;

  environment.shellAliases = {
    recovery-guide = "less /etc/dotfiles-recovery/README.md";
    homeserver-guide = "less /etc/dotfiles-recovery/HOMESERVER_MIGRATION.md";
    clone-dotfiles = "git clone https://github.com/${user.username}/dotfiles.git ~/.dotfiles";
  };

  # The installer is a public artifact, so it contains no private keys, SOPS-decrypted
  # data, or fixed passwords at all. SSH login is only used if a temporary key is added after boot.
  users.users.nixos.openssh.authorizedKeys.keys = [ ];

  system.stateVersion = "26.05";
}
