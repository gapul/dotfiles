{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./detection/project.nix
  ];
  
  options = {
    dotfiles.context = {
      enable = mkEnableOption "Intelligent context recognition system";
      
      profile = mkOption {
        type = types.enum ["minimal" "standard" "full"];
        default = "standard";
        description = "Context recognition feature level";
      };
    };
  };

  config = mkIf config.dotfiles.context.enable {
    # Enable context detection modules based on profile
    dotfiles.context.projectDetection.enable = mkDefault true;
  };
}