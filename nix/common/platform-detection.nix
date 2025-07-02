# Enhanced Platform Detection Module
# Comprehensive cross-platform detection and capability system
# Supports: macOS (Intel/Apple Silicon), Linux, NixOS, WSL, Android/Termux
{ lib, pkgs }:

rec {
  # Basic system information
  systemName = pkgs.stdenv.system;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  isAarch64 = pkgs.stdenv.isAarch64;
  isX86_64 = pkgs.stdenv.isx86_64;
  
  # Enhanced platform detection with variants
  platform = 
    if isDarwin then
      if isAarch64 then "darwin-aarch64" else "darwin-x86_64"
    else if isLinux then
      # Try to detect specific Linux variants
      if builtins.pathExists "/etc/nixos" then "nixos"
      else if builtins.pathExists "/proc/version" then
        let versionContent = builtins.readFile "/proc/version";
        in if (builtins.match ".*Microsoft.*" versionContent != null) then "wsl"
           else if (builtins.match ".*android.*" versionContent != null) then "android"
           else "linux"
      else if builtins.pathExists "/data/data/com.termux" then "android"
      else "linux"
    else "unknown";
    
  # Simplified platform name for compatibility
  platformSimple = 
    if isDarwin then "darwin"
    else if isLinux then "linux" 
    else "unknown";
  
  # Enhanced capability detection based on platform
  capabilities = {
    # Package installation capabilities
    canInstallPackages = true;
    limitedPackages = platform == "android" || platform == "wsl";
    
    # GUI and display capabilities
    hasGUI = platform != "android" && platform != "wsl";
    supportsGraphicalApps = platform == "darwin-aarch64" || platform == "darwin-x86_64" || platform == "nixos" || platform == "linux";
    
    # System integration capabilities
    hasSystemd = platform == "nixos" || (platform == "linux" && builtins.pathExists "/bin/systemctl");
    useHomeManager = !isDarwin;  # Darwin uses nix-darwin
    canModifySystem = platform != "android";
    
    # Resource and performance characteristics
    limitedResources = platform == "android";
    supportsContainers = platform != "android";
    hasPackageManager = isDarwin || platform == "android";  # Homebrew or pkg
    
    # Network and connectivity
    hasReliableNetwork = platform != "android";  # Android may have limited/metered connections
    supportsVPN = platform != "android";
    
    # Development capabilities
    supportsFullDevEnvironment = platform != "android";
    canRunHeavyBuilds = !capabilities.limitedResources;
    supportsLanguageServers = platform != "android";
  };
  
  # Platform-specific paths and directories
  paths = {
    home = 
      if isDarwin then "/Users"
      else if platform == "android" then "/data/data/com.termux/files/home"
      else "/home";
      
    configDir = 
      if isDarwin then "Library/Application Support"
      else if platform == "android" then ".config"  # Termux uses standard .config
      else ".config";
      
    binDir = 
      if platform == "android" then "$PREFIX/bin"
      else if isDarwin then "/opt/homebrew/bin:/usr/local/bin"
      else "/usr/local/bin:/usr/bin";
  };
  
  # Platform-specific optimizations
  optimizations = {
    # Memory and CPU settings
    maxJobs = 
      if capabilities.limitedResources then 1
      else if isDarwin && isAarch64 then 8  # Apple Silicon
      else if isDarwin then 4  # Intel Mac
      else 4;  # Conservative default for Linux
      
    maxMemoryMB = 
      if capabilities.limitedResources then 1024
      else if isDarwin && isAarch64 then 8192
      else 4096;
      
    # Build optimizations
    enableParallelBuilding = !capabilities.limitedResources;
    useCompression = capabilities.limitedResources;  # Save space on limited devices
    enableCaching = capabilities.hasReliableNetwork;
  };
  
  # Filter packages for platform compatibility (enhanced)
  filterForPlatformEnabled = true;
  
  # Package filtering categories
  packageCategories = {
    # Core packages - available on all platforms
    core = [ "git" "curl" "jq" "vim" ];
    
    # Development packages - not on resource-limited platforms
    development = if capabilities.supportsFullDevEnvironment 
                  then [ "nodejs" "python3" "go" "rust" ]
                  else [ "python3" ];  # Minimal dev environment
    
    # GUI packages - only where GUI is supported
    gui = if capabilities.hasGUI 
          then [ "firefox" "vscodium" ]
          else [];
    
    # System packages - platform-specific system tools
    system = 
      if isDarwin then [ "mas" "dockutil" ]
      else if platform == "nixos" then [ "systemd" ]
      else if platform == "android" then [ "termux-api" ]
      else [];
  };
  
  # Compatibility matrix for debugging
  compatibilityInfo = {
    detectedPlatform = platform;
    detectedCapabilities = capabilities;
    supportedFeatures = {
      gui = capabilities.hasGUI;
      development = capabilities.supportsFullDevEnvironment;
      containers = capabilities.supportsContainers;
      systemModification = capabilities.canModifySystem;
    };
    platformPaths = paths;
    performanceSettings = optimizations;
  };
}