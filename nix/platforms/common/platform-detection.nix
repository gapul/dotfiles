# Platform Detection Module
# Automatically detects the current platform and sets appropriate configurations
{ lib, pkgs, ... }:

let
  # Platform detection logic
  platformInfo = rec {
    # Basic system information
    system = builtins.currentSystem;
    isDarwin = pkgs.stdenv.isDarwin;
    isLinux = pkgs.stdenv.isLinux;
    isAarch64 = pkgs.stdenv.isAarch64;
    isX86_64 = pkgs.stdenv.isx86_64;
    
    # Detailed platform detection
    platform = 
      if isDarwin then
        if isAarch64 then "darwin-aarch64" else "darwin-x86_64"
      else if isLinux then
        if builtins.pathExists "/etc/nixos" then "nixos"
        else if builtins.pathExists "/proc/version" then
          let versionContent = builtins.readFile "/proc/version";
          in if lib.hasInfix "Microsoft" versionContent || lib.hasInfix "WSL" versionContent then "wsl"
             else if lib.hasInfix "Android" versionContent then "android"
             else "linux"
        else "linux"
      else "unknown";
    
    # Platform capabilities
    capabilities = {
      hasGUI = platform == "darwin" || platform == "nixos" || platform == "linux";
      hasSystemd = platform == "nixos" || platform == "linux";
      hasHomebrew = platform == "darwin";
      hasNixDarwin = platform == "darwin" || lib.hasPrefix "darwin-" platform;
      hasNixOS = platform == "nixos";
      canInstallPackages = true;
      canManageServices = platform != "android" && platform != "wsl";
      supportsBinaryCache = true;
    };
    
    # Platform-specific settings
    settings = {
      darwin = {
        useNixDarwin = true;
        useHomebrew = true;
        enableGUIApps = true;
        defaultShell = pkgs.zsh;
        fontDirectory = "~/Library/Fonts";
      };
      nixos = {
        useSystemPackages = true;
        enableGUIApps = true;
        enableSystemd = true;
        defaultShell = pkgs.zsh;
        fontDirectory = "/etc/fonts/conf.d";
      };
      linux = {
        useHomeManager = true;
        enableGUIApps = true;
        enableSystemd = true;
        defaultShell = pkgs.zsh;
        fontDirectory = "~/.local/share/fonts";
      };
      wsl = {
        useHomeManager = true;
        enableGUIApps = false;
        enableWindowsIntegration = true;
        defaultShell = pkgs.zsh;
        fontDirectory = "~/.local/share/fonts";
      };
      android = {
        useNixOnDroid = true;
        enableGUIApps = false;
        limitedPackages = true;
        defaultShell = pkgs.zsh;
        fontDirectory = "~/.termux";
      };
    };
    
    # Get current platform settings
    currentSettings = settings.${platform} or settings.linux;
    
    # Package filtering based on platform
    filterPackages = packages: 
      if platform == "android" then
        # Android has limited package availability
        lib.filter (pkg: 
          !(lib.hasAttr "meta" pkg && lib.hasAttr "platforms" pkg.meta && 
            !(lib.elem "aarch64-linux" pkg.meta.platforms))
        ) packages
      else if platform == "wsl" then
        # WSL doesn't need GUI packages
        lib.filter (pkg: 
          !(lib.hasAttr "meta" pkg && lib.hasAttr "categories" pkg.meta && 
            lib.elem "gui" pkg.meta.categories)
        ) packages
      else packages;
  };

in {
  # Export platform information
  inherit platformInfo;
  
  # Helper functions
  onPlatform = platform: config: 
    if platformInfo.platform == platform then config else {};
  
  onPlatforms = platforms: config:
    if lib.elem platformInfo.platform platforms then config else {};
  
  whenCapable = capability: config:
    if platformInfo.capabilities.${capability} or false then config else {};
  
  # Conditional package lists
  darwinPackages = platformInfo.onPlatform "darwin";
  linuxPackages = platformInfo.onPlatforms ["nixos" "linux"];
  wslPackages = platformInfo.onPlatform "wsl";
  androidPackages = platformInfo.onPlatform "android";
  
  # Cross-platform package filtering
  filterForPlatform = platformInfo.filterPackages;
  
  # Platform-specific module imports
  platformModules = 
    if platformInfo.platform == "darwin" then [
      ../darwin/system
      ../darwin/homebrew
    ]
    else if platformInfo.platform == "nixos" then [
      ../linux/desktop
    ]
    else if platformInfo.platform == "linux" then [
      ../linux/server
    ]
    else if platformInfo.platform == "wsl" then [
      ../wsl/integration
    ]
    else if platformInfo.platform == "android" then [
      ../android/termux
    ]
    else [];
}