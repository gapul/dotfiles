# Android (Termux) 上の nix-on-droid 環境。
#   初回: https://f-droid.org/packages/com.termux.nix/ のアプリから
#     nix-on-droid switch --flake github:gapul/dotfiles?dir=nix#default
# ECS: この Entity は modules/home の component (git/cli/shell/terminal) を
# そのまま合成する。nix-index/agent-skills 等 flake input モジュール前提の
# component と、GUI/ワークステーション系 role は積まない。
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

  # Termux 側のフォント/カラーは nix-on-droid の terminal オプションでも設定できるが、
  # まずは最小構成。テーマは zellij (terminal component) 側が持つ。
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
