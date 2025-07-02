# Minimal development environment for testing
{ config, lib, pkgs, ... }:

with lib;

{
  options.dotfiles.development = {
    enable = mkEnableOption "Development environment";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "minimal";
      description = "Development environment profile";
    };
  };

  config = mkIf config.dotfiles.development.enable {
    # Basic development packages for testing
    environment.systemPackages = with pkgs; [
      git
      vim
      curl
      jq
      
      # Additional development tools
      gh          # GitHub CLI
      just        # Task runner
      direnv      # Environment management
      starship    # Shell prompt
    ];
  };
}