# Example sops-nix configuration
# This module shows how to use sops-nix for secret management
# 
# NOTE: This is disabled by default for security reasons
# To enable, add this module to your configuration imports

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.security.sops-example;
in
{
  options.dotfiles.security.sops-example = {
    enable = mkEnableOption "sops-nix example configuration (disabled by default)";
  };

  config = mkIf cfg.enable {
    # System-wide sops configuration
    sops = {
      # Default sops file location
      defaultSopsFile = ../../secrets/secrets.yaml;
      
      # Validate sops files at build time
      validateSopsFiles = false; # Set to true when you have real secrets
      
      # Age configuration for decryption
      age = {
        # Location of age key file
        keyFile = "/var/lib/sops-nix/key.txt";
        
        # Generate key if it doesn't exist
        generateKey = true;
      };
      
      # System secrets configuration
      secrets = {
        # Example: WiFi password
        "system/wifi_password" = {
          # File where the decrypted secret will be placed
          path = "/run/secrets/wifi_password";
          # Owner and permissions
          owner = "root";
          group = "wheel";
          mode = "0400";
        };
        
        # Example: Backup encryption key
        "system/backup_encryption_key" = {
          path = "/run/secrets/backup_key";
          owner = "root";
          group = "wheel"; 
          mode = "0400";
        };
      };
    };

    # Home Manager sops configuration (for user secrets)
    home-manager.users.yuki = {
      sops = {
        # Default sops file for user secrets
        defaultSopsFile = ../../secrets/secrets.yaml;
        
        # Age configuration
        age.keyFile = "\${config.home.homeDirectory}/.config/sops/age/keys.txt";
        
        # User secrets
        secrets = {
          # Development API keys
          "development/api_key" = {
            path = "\${config.home.homeDirectory}/.config/dev/api_key";
          };
          
          # AI platform secrets
          "ai_platform/openai_api_key" = {
            path = "\${config.home.homeDirectory}/.config/openai/api_key";
          };
          
          "ai_platform/github_token" = {
            path = "\${config.home.homeDirectory}/.config/github/token";
          };
          
          # Cloud provider secrets
          "cloud/aws_access_key" = {
            path = "\${config.home.homeDirectory}/.aws/access_key";
          };
        };
      };
      
      # Example: Use secrets in programs
      programs.git = {
        extraConfig = {
          # Use decrypted GitHub token
          github.user = "yuki";
          # Token file will be available at the path specified above
        };
      };
      
      # Example: Environment variables from secrets
      home.sessionVariables = {
        # These would be set from the decrypted files
        # OPENAI_API_KEY = "$(cat \${config.sops.secrets.\"ai_platform/openai_api_key\".path})";
      };
    };
    
    # Example: System service using secrets
    launchd.user.agents.secret-example = {
      serviceConfig = {
        Label = "com.example.secret-service";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-c"
          # Use the decrypted secret file
          "echo 'Secret loaded from: /run/secrets/wifi_password'"
        ];
        RunAtLoad = false; # Don't actually run this example
      };
    };
  };
}