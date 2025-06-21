# Platform Detection Module
# Simple platform detection function
{ lib, pkgs }:

rec {
  # Basic system information
  systemName = pkgs.stdenv.system;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  isAarch64 = pkgs.stdenv.isAarch64;
  isX86_64 = pkgs.stdenv.isx86_64;
  
  # Simplified platform detection
  platform = 
    if isDarwin then "darwin"
    else if isLinux then "linux"
    else "unknown";
  
  # Basic capabilities
  capabilities = {
    canInstallPackages = true;
    hasGUI = isDarwin || isLinux;
    useHomeManager = !isDarwin;  # Darwin uses nix-darwin
  };
  
  # Filter packages for platform compatibility (non-function for JSON compatibility)
  filterForPlatformEnabled = true;
}