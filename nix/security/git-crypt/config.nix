# Git-crypt Integration Configuration
# Provides selective file encryption for sensitive configuration files
{ config, lib, pkgs, ... }:

{
  # Install git-crypt
  environment.systemPackages = with pkgs; [
    git-crypt
    gnupg
  ];
  
  # Git-crypt configuration
  programs.git = {
    enable = true;
    extraConfig = {
      # Git-crypt filter configuration
      filter."git-crypt" = {
        clean = "${pkgs.git-crypt}/bin/git-crypt clean";
        smudge = "${pkgs.git-crypt}/bin/git-crypt smudge";
        required = true;
      };
      
      diff."git-crypt" = {
        textconv = "${pkgs.git-crypt}/bin/git-crypt diff";
      };
      
      # Merge driver for encrypted files
      merge."git-crypt" = {
        name = "A custom merge driver used to merge git-crypt files.";
        driver = "${pkgs.git-crypt}/bin/git-crypt merge %O %A %B";
      };
    };
  };
}