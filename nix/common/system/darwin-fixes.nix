{ config, lib, pkgs, ... }:

with lib;

{
  # Fix HOME ownership warning when using sudo with nix-darwin
  environment.variables = {
    # Preserve user HOME directory for nix-darwin operations
    HOME = mkDefault "/Users/yuki";
  };
  
  # System environment setup to prevent warnings
  system.activationScripts.preActivation = {
    text = ''
      # Ensure proper ownership and permissions
      if [ "$USER" = "root" ] && [ "$SUDO_USER" != "" ]; then
        export HOME="/Users/$SUDO_USER"
        export USER="$SUDO_USER"
      fi
    '';
  };
  
  # Nix daemon configuration for better sudo handling
  nix.daemonIOLowPriority = mkDefault true;
  
  # Additional nix settings to reduce warnings
  nix.settings = {
    # Trust system users to reduce permission warnings
    trusted-users = [ "root" "yuki" "@admin" ];
    
    # Reduce verbosity for common operations
    warn-dirty = false;
    
    # Improve build isolation
    sandbox = mkDefault true;
  };
  
  # Ensure proper file permissions
  system.activationScripts.fixPermissions = {
    text = ''
      # Fix any permission issues that might cause warnings
      if [ -d "/Users/yuki" ]; then
        chown -R yuki:staff "/Users/yuki/.nix-profile" 2>/dev/null || true
        chown -R yuki:staff "/Users/yuki/.nix-defexpr" 2>/dev/null || true
      fi
    '';
  };
}