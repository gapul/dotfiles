# SOPS Creation Rules Configuration
# Defines encryption rules and key management for different secret types
{ config, lib, pkgs, ... }:

{
  # Creation rules for different secret categories
  sops = {
    # GitHub and Git secrets
    creation_rules = [
      {
        path_regex = "github/.*";
        key_groups = [
          {
            age = [
              # Personal development key (actual generated key)
              "age1crkk4dtd824qu3h5q24vnm4pmrjymzkelt60qnyzwcje74gncudqjr693n"
              # CI/CD key (to be generated)
              "age1ci0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            ];
            pgp = [
              # Personal GPG key
              "7C6A4B8E9F2D1A3C5E7F8B9A2C4D6E8F0A1B3C5D7E9F1A3C5E7F8B9A2C4D6E8F"
            ];
          }
        ];
      }
      
      {
        path_regex = "git/.*";
        key_groups = [
          {
            age = [
              "age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6"
            ];
            pgp = [
              "7C6A4B8E9F2D1A3C5E7F8B9A2C4D6E8F0A1B3C5D7E9F1A3C5E7F8B9A2C4D6E8F"
            ];
          }
        ];
      }
      
      # SSH keys
      {
        path_regex = "ssh/.*";
        key_groups = [
          {
            age = [
              "age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6"
            ];
            pgp = [
              "7C6A4B8E9F2D1A3C5E7F8B9A2C4D6E8F0A1B3C5D7E9F1A3C5E7F8B9A2C4D6E8F"
            ];
          }
        ];
      }
      
      # API credentials
      {
        path_regex = "api/.*";
        key_groups = [
          {
            age = [
              "age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6"
              # Shared team key for API credentials
              "age1team123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            ];
          }
        ];
      }
      
      # Platform-specific secrets
      {
        path_regex = "macos/.*";
        key_groups = [
          {
            age = [
              "age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6"
            ];
          }
        ];
      }
      
      {
        path_regex = "linux/.*";
        key_groups = [
          {
            age = [
              "age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6"
            ];
          }
        ];
      }
      
      {
        path_regex = "android/.*";
        key_groups = [
          {
            age = [
              "age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6"
            ];
          }
        ];
      }
      
      # Development and CI/CD secrets
      {
        path_regex = "dev/.*";
        key_groups = [
          {
            age = [
              "age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6"
              "age1ci0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            ];
          }
        ];
      }
    ];
  };
  
  # Key management helpers
  environment.systemPackages = lib.mkIf (config.sops.age.generateKey or false) [
    pkgs.age
    pkgs.sops
  ];
  
  # Age key generation script
  system.activationScripts.sops-age-key = lib.mkIf (config.sops.age.generateKey or false) ''
    if [ ! -f "${config.sops.age.keyFile}" ]; then
      echo "Generating age key for SOPS..."
      mkdir -p "$(dirname "${config.sops.age.keyFile}")"
      ${pkgs.age}/bin/age-keygen -o "${config.sops.age.keyFile}"
      chmod 600 "${config.sops.age.keyFile}"
      echo "Age key generated at: ${config.sops.age.keyFile}"
      echo "Public key:"
      ${pkgs.age}/bin/age-keygen -y "${config.sops.age.keyFile}"
    fi
  '';
}