# SOPS-nix Core Configuration
# Provides secure secret management for multi-platform dotfiles
{ config, lib, pkgs, platformInfo, ... }:

let
  # Platform-specific secret configuration
  secretsConfig = {
    darwin = {
      keyFile = "/var/lib/sops-nix/keys.txt";
      secretsPath = "/run/secrets";
    };
    linux = {
      keyFile = "/var/lib/sops-nix/keys.txt";
      secretsPath = "/run/secrets";
    };
    wsl = {
      keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      secretsPath = "${config.home.homeDirectory}/.local/share/secrets";
    };
    android = {
      keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      secretsPath = "${config.home.homeDirectory}/.local/share/secrets";
    };
  };

  currentConfig = secretsConfig.${platformInfo.platform} or secretsConfig.linux;
  
  # Common secret definitions
  commonSecrets = {
    # GitHub integration
    "github/token" = {
      mode = "0400";
    };
    
    # SSH keys
    "ssh/personal_key" = {
      mode = "0600";
    };
    
    "ssh/personal_key_pub" = {
      mode = "0644";
    };
    
    # API credentials
    "api/openai_key" = {
      mode = "0400";
    };
    
    "api/anthropic_key" = {
      mode = "0400";
    };
    
    # Git configuration
    "git/signing_key" = {
      mode = "0600";
    };
    
    # Development tools
    "dev/npm_token" = {
      mode = "0400";
    };
  };

  # Platform-specific secrets
  platformSecrets = lib.optionalAttrs (platformInfo.platform == "darwin") {
    # macOS-specific secrets
    "macos/keychain_password" = {
      mode = "0400";
    };
  } // lib.optionalAttrs (platformInfo.platform == "linux") {
    # Linux-specific secrets
    "linux/sudo_password" = {
      mode = "0400";
    };
  } // lib.optionalAttrs (platformInfo.platform == "android") {
    # Android-specific secrets
    "android/termux_token" = {
      mode = "0400";
    };
  };

in
{
  # SOPS configuration
  sops = {
    # Default secret file based on platform
    defaultSopsFile = 
      if platformInfo.platform == "darwin" then ./secrets-darwin.yaml
      else if platformInfo.platform == "linux" then ./secrets-linux.yaml
      else if platformInfo.platform == "wsl" then ./secrets-wsl.yaml
      else if platformInfo.platform == "android" then ./secrets-android.yaml
      else ./secrets.yaml;
    
    defaultSopsFormat = "yaml";
    
    # Age encryption configuration
    age = {
      keyFile = currentConfig.keyFile;
      generateKey = true;
    };
    
    # GPG configuration (optional)
    gnupg = {
      # Enable GPG support if available
      home = "${config.home.homeDirectory}/.gnupg";
      sshKeys = [ "ssh/personal_key" ];
    };
    
    # Secret definitions
    secrets = commonSecrets // platformSecrets;
  };
  
  # Ensure required directories exist
  systemd.tmpfiles.rules = lib.mkIf (platformInfo.platform == "linux") [
    "d ${currentConfig.secretsPath} 0755 root root"
    "d ${lib.dirOf currentConfig.keyFile} 0755 root root"
  ];
  
  # Home manager configuration for user-space secrets
  home-manager.users.yuki = lib.mkIf (platformInfo.platform == "wsl" || platformInfo.platform == "android") {
    home.file = {
      ".config/sops/age/.keep".text = "";
      ".local/share/secrets/.keep".text = "";
    };
  };
}