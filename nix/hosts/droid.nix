# nix-on-droid environment on Android (Termux).
#   First time: from the app at https://f-droid.org/packages/com.termux.nix/
#     nix-on-droid switch --flake github:gapul/dotfiles?dir=nix#default
# ECS: this Entity composes the modules/home components (git/cli/shell/terminal)
# as-is. It does not load components that assume flake input modules like
# nix-index/agent-skills, nor GUI/workstation roles.
{ pkgs, ... }:
let
  user = import ../user.nix;
in
{
  environment.packages = with pkgs; [
    vim
    openssh
    rsync
  ];

  # Termux-side fonts/colors can also be set via nix-on-droid's terminal options,
  # but start minimal. The theme is held by the terminal component.
  time.timeZone = "Asia/Tokyo";

  system.stateVersion = "24.05";

  home-manager = {
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
    extraSpecialArgs = {
      inherit user;
    };
    config = {
      imports = [
        ../modules/home/git.nix
        ../modules/home/cli.nix
        ../modules/home/shell.nix
        ../modules/home/terminal.nix
      ];
      home.stateVersion = "23.11";
    };
  };
}
