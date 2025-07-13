# Modern CLI Tools Integration (Simplified Version)
# Phase 5: Enhanced CLI experience with modern alternatives

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.modern-cli;
in
{
  options.dotfiles.development.modern-cli = {
    enable = mkEnableOption "Modern CLI tools integration";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Modern CLI profile level";
    };
    
    # Individual tool toggles
    navigation = mkEnableOption "Navigation tools (eza, fd, zoxide)";
    content = mkEnableOption "Content tools (bat, ripgrep)";
    git = mkEnableOption "Git tools (lazygit, delta)";
    atuin = mkEnableOption "Shell history (atuin)";
    starship = mkEnableOption "Shell prompt (starship)";
    zoxide = mkEnableOption "Smart cd (zoxide)";
  };

  config = mkIf cfg.enable {
    # Auto-enable features based on profile
    dotfiles.development.modern-cli = {
      navigation = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      content = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      git = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      atuin = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      starship = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      zoxide = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
    };

    # Install packages based on enabled features
    home-manager.users.yuki.home.packages = with pkgs; [
      # Always include core modern CLI tools
    ] ++ optionals cfg.navigation [
      eza         # Modern ls replacement
      fd          # Modern find replacement
    ] ++ optionals cfg.content [
      bat         # Modern cat replacement
      ripgrep     # Modern grep replacement
    ] ++ optionals cfg.git [
      lazygit     # Terminal UI for git
      delta       # Better git diff
    ] ++ optionals cfg.atuin [
      atuin       # Shell history
    ];

    # Zoxide configuration
    home-manager.users.yuki.programs.zoxide = mkIf cfg.zoxide {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      options = [ "--cmd cd" ];
    };

    # Starship prompt configuration
    home-manager.users.yuki.programs.starship = mkIf cfg.starship {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      
      settings = {
        format = lib.concatStrings [
          "$username"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_status"
          "$nix_shell"
          "$line_break"
          "$character"
        ];
        add_newline = false;
        
        directory = {
          style = "bold cyan";
          truncation_length = 3;
        };
        
        git_branch = {
          symbol = " ";
          style = "bold purple";
        };
        
        character = {
          success_symbol = "[❯](purple)";
          error_symbol = "[❯](red)";
        };
      };
    };

    # Atuin configuration
    home-manager.users.yuki.programs.atuin = mkIf cfg.atuin {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      
      settings = {
        auto_sync = true;
        search_mode = "fuzzy";
        filter_mode = "global";
        show_preview = true;
        exit_mode = "return-original";
        secrets_filter = true;
      };
    };

    # Shell aliases for modern CLI tools
    home-manager.users.yuki.programs.zsh.shellAliases = mkIf cfg.enable (mkMerge [
      # Navigation aliases
      (mkIf cfg.navigation {
        ll = "eza -la --color=auto --group-directories-first";
        la = "eza -la --color=auto --group-directories-first";
        tree = "eza --tree";
      })
      
      # Content aliases  
      (mkIf cfg.content {
        grep = "rg";
      })
      
      # Git aliases
      (mkIf cfg.git {
        lg = "lazygit";
      })
    ]);

    # Simple health check script
    home-manager.users.yuki.home.file."bin/modern-cli-health" = mkIf cfg.enable {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🚀 Modern CLI Tools Status"
        echo "=========================="
        command -v eza >/dev/null && echo "✅ eza" || echo "❌ eza"
        command -v bat >/dev/null && echo "✅ bat" || echo "❌ bat"
        command -v rg >/dev/null && echo "✅ ripgrep" || echo "❌ ripgrep"
        command -v fd >/dev/null && echo "✅ fd" || echo "❌ fd"
        command -v lazygit >/dev/null && echo "✅ lazygit" || echo "❌ lazygit"
        command -v atuin >/dev/null && echo "✅ atuin" || echo "❌ atuin"
        command -v starship >/dev/null && echo "✅ starship" || echo "❌ starship"
        command -v zoxide >/dev/null && echo "✅ zoxide" || echo "❌ zoxide"
        echo "Profile: ${cfg.profile}"
      '';
    };
  };
}