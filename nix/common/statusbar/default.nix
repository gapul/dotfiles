# Status Bar Configuration
# Manages macOS status bar applications
{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./sketchybar.nix
  ];

  options.dotfiles.statusbar = {
    enable = mkEnableOption "Status bar configuration";
    
    provider = mkOption {
      type = types.enum [ "sketchybar" "none" ];
      default = "sketchybar";
      description = "Status bar provider";
    };
  };

  config = mkIf config.dotfiles.statusbar.enable {
    # Enable status bar based on provider
    dotfiles.statusbar.sketchybar.enable = mkDefault (
      config.dotfiles.statusbar.provider == "sketchybar"
    );
  };
}