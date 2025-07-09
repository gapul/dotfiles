{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./detection/project.nix
    ./detection/environment.nix
    ./detection/resources.nix
    ./detection/themes.nix
    ./detection/tools.nix
    ./detection/power.nix
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
    dotfiles.context.environmentDetection.enable = mkDefault (config.dotfiles.context.profile != "minimal");
    dotfiles.context.resourceMonitoring.enable = mkDefault true;
    
    # Configure environment detection based on profile
    dotfiles.context.environmentDetection.timePatterns.enable = mkDefault true;
    dotfiles.context.environmentDetection.locationDetection.enable = mkDefault true;
    dotfiles.context.environmentDetection.situationDetection.enable = mkDefault (config.dotfiles.context.profile == "full");
    dotfiles.context.environmentDetection.activityTracking.enable = mkDefault (config.dotfiles.context.profile == "full");
    dotfiles.context.environmentDetection.activityTracking.privacyMode = mkDefault true;
    
    # Configure resource monitoring based on profile
    dotfiles.context.resourceMonitoring.batteryMonitoring.enable = mkDefault true;
    dotfiles.context.resourceMonitoring.cpuMonitoring.enable = mkDefault true;
    dotfiles.context.resourceMonitoring.memoryMonitoring.enable = mkDefault true;
    dotfiles.context.resourceMonitoring.networkMonitoring.enable = mkDefault (config.dotfiles.context.profile != "minimal");
    dotfiles.context.resourceMonitoring.storageMonitoring.enable = mkDefault true;
    dotfiles.context.resourceMonitoring.alerting.enable = mkDefault (config.dotfiles.context.profile == "full");
    
    # Configure theme adaptation based on profile
    dotfiles.context.themeAdaptation.enable = mkDefault (config.dotfiles.context.profile != "minimal");
    dotfiles.context.themeAdaptation.timeBasedThemes.enable = mkDefault true;
    dotfiles.context.themeAdaptation.ambientLightAdaptation.enable = mkDefault (config.dotfiles.context.profile == "full");
    dotfiles.context.themeAdaptation.focusAdaptation.enable = mkDefault true;
    dotfiles.context.themeAdaptation.fatigueAdaptation.enable = mkDefault (config.dotfiles.context.profile == "full");
    dotfiles.context.themeAdaptation.applicationThemes.enable = mkDefault true;
    dotfiles.context.themeAdaptation.systemIntegration.enable = mkDefault true;
    
    # Configure tool configuration based on profile
    dotfiles.context.toolConfiguration.enable = mkDefault false;
    dotfiles.context.toolConfiguration.developerProfiles.enable = mkDefault true;
    dotfiles.context.toolConfiguration.contextualSettings.enable = mkDefault true;
    dotfiles.context.toolConfiguration.editorIntegration.enable = mkDefault true;
    dotfiles.context.toolConfiguration.terminalOptimization.enable = mkDefault (config.dotfiles.context.profile != "minimal");
    dotfiles.context.toolConfiguration.toolchainManagement.enable = mkDefault (config.dotfiles.context.profile == "full");
    
    # Configure power management based on profile
    dotfiles.context.powerManagement.enable = mkDefault true;
    dotfiles.context.powerManagement.batteryOptimization.enable = mkDefault true;
    dotfiles.context.powerManagement.performanceOptimization.enable = mkDefault (config.dotfiles.context.profile != "minimal");
    dotfiles.context.powerManagement.cloudOffloading.enable = mkDefault (config.dotfiles.context.profile == "full");
    dotfiles.context.powerManagement.intelligentScheduling.enable = mkDefault (config.dotfiles.context.profile == "full");
  };
}