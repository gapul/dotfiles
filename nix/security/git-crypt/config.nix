# Legacy Git-crypt Configuration - DEPRECATED
# All encryption now handled by SOPS-nix
# This file kept for reference only

{ config, lib, pkgs, ... }:

{
  # Git-crypt removed - using SOPS-only strategy
  # All secrets now managed through:
  # - nix/security/sops/secrets-unified.yaml
  # - SOPS-nix integration in default.nix
  
  # Optional: Keep gnupg for GPG operations (not Git-crypt)
  environment.systemPackages = with pkgs; [
    gnupg  # For GPG operations, SOPS GPG support
    # git-crypt removed - no longer needed
  ];
}