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
  
  # SOPS Unified Secret definitions
  # All secrets managed through single SOPS file
  commonSecrets = {
    # API Keys and Tokens
    "api/github_token" = { mode = "0400"; };
    "api/openai_key" = { mode = "0400"; };
    "api/anthropic_key" = { mode = "0400"; };
    "api/npm_token" = { mode = "0400"; };
    
    # Git Configuration Secrets
    "git/signing_key_id" = { mode = "0400"; };
    "git/signing_key_private" = { mode = "0600"; };
    
    # SSH Keys and Configuration
    "ssh/private_key" = { mode = "0600"; };
    "ssh/public_key" = { mode = "0644"; };
    "ssh/config" = { mode = "0600"; };
    
    # SSL/TLS Certificates
    "ssl/certificate" = { mode = "0644"; };
    "ssl/private_key" = { mode = "0600"; };
    
    # Development Environment Files
    "development/npmrc" = { mode = "0600"; };
    "development/docker_config" = { mode = "0600"; };
    
    # Cloud Provider Credentials
    "cloud/aws/access_key_id" = { mode = "0400"; };
    "cloud/aws/secret_access_key" = { mode = "0400"; };
    "cloud/gcp/service_account_key" = { mode = "0600"; };
    
    # Database Credentials
    "databases/postgresql/password" = { mode = "0400"; };
    "databases/mysql/password" = { mode = "0400"; };
    
    # Environment Variables
    "development/env_vars/database_password" = { mode = "0400"; };
    "development/env_vars/jwt_secret" = { mode = "0400"; };
    "development/env_vars/encryption_key" = { mode = "0400"; };
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
  # SOPS configuration - Unified approach
  sops = {
    # Single unified secrets file for all platforms
    defaultSopsFile = ../secrets-unified.yaml;
    
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