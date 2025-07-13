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
    process = mkEnableOption "Process tools (bottom, procs)";
    git = mkEnableOption "Git tools (lazygit, delta)";
    file-manager = mkEnableOption "File manager (yazi)";
    system-info = mkEnableOption "System info (fastfetch)";
    data-analysis = mkEnableOption "Data analysis (visidata)";
    atuin = mkEnableOption "Shell history (atuin)";
    starship = mkEnableOption "Shell prompt (starship)";
    zoxide = mkEnableOption "Smart cd (zoxide)";
  };

  config = mkIf cfg.enable {
    # Auto-enable features based on profile
    dotfiles.development.modern-cli = {
      navigation = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      content = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      process = mkDefault (cfg.profile == "full");
      git = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      file-manager = mkDefault (cfg.profile == "full");
      system-info = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      data-analysis = mkDefault (cfg.profile == "full");
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
    ] ++ optionals cfg.process [
      bottom      # Modern top replacement
      procs       # Modern ps replacement
    ] ++ optionals cfg.git [
      lazygit     # Terminal UI for git
      delta       # Better git diff
    ] ++ optionals cfg.file-manager [
      yazi        # Terminal file manager
    ] ++ optionals cfg.system-info [
      fastfetch   # System info display
    ] ++ optionals cfg.data-analysis [
      visidata    # Terminal data analysis
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
        ls = "eza --color=auto --group-directories-first";
        ll = "eza -la --color=auto --group-directories-first";
        la = "eza -la --color=auto --group-directories-first";
        tree = "eza --tree";
        find = "fd";
      })
      
      # Content aliases  
      (mkIf cfg.content {
        cat = "bat --style=auto";
        grep = "rg";
        rg = "rg --smart-case";
      })
      
      # Process aliases
      (mkIf cfg.process {
        top = "bottom";
        htop = "bottom";
        ps = "procs";
      })
      
      # Git aliases
      (mkIf cfg.git {
        lazygit = "lazygit";
        lg = "lazygit";
        git-ui = "lazygit";
      })
      
      # File manager
      (mkIf cfg.file-manager {
        fm = "yazi";
        files = "yazi";
      })
      
      # System info
      (mkIf cfg.system-info {
        info = "fastfetch";
        sysinfo = "fastfetch";
        neofetch = "fastfetch";
      })
      
      # Data analysis
      (mkIf cfg.data-analysis {
        data = "visidata";
        vd = "visidata";
      })
      
      # Atuin
      (mkIf cfg.atuin {
        history = "atuin search";
        h = "atuin search";
      })
    ]);

    # VisiData configuration
    home-manager.users.yuki.home.file.".visidatarc" = mkIf cfg.data-analysis {
      text = ''
        # VisiData configuration
        options.regex_flags = 're.IGNORECASE'
        options.clipboard_copy_cmd = 'pbcopy'  # macOS
        options.motd_url = ''  # Disable message of the day
      '';
    };


    # Enhanced health check script
    home-manager.users.yuki.home.file."bin/modern-cli-health" = mkIf cfg.enable {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🚀 Modern CLI Tools Health Check"
        echo "================================="
        echo ""
        
        # Check all tools individually
        command -v eza >/dev/null && echo "✅ eza" || echo "❌ eza"
        command -v fd >/dev/null && echo "✅ fd" || echo "❌ fd"
        command -v bat >/dev/null && echo "✅ bat" || echo "❌ bat"
        command -v rg >/dev/null && echo "✅ rg" || echo "❌ rg"
        command -v bottom >/dev/null && echo "✅ bottom" || echo "❌ bottom"
        command -v procs >/dev/null && echo "✅ procs" || echo "❌ procs"
        command -v lazygit >/dev/null && echo "✅ lazygit" || echo "❌ lazygit"
        command -v delta >/dev/null && echo "✅ delta" || echo "❌ delta"
        command -v yazi >/dev/null && echo "✅ yazi" || echo "❌ yazi"
        command -v fastfetch >/dev/null && echo "✅ fastfetch" || echo "❌ fastfetch"
        command -v visidata >/dev/null && echo "✅ visidata" || echo "❌ visidata"
        command -v atuin >/dev/null && echo "✅ atuin" || echo "❌ atuin"
        command -v starship >/dev/null && echo "✅ starship" || echo "❌ starship"
        command -v zoxide >/dev/null && echo "✅ zoxide" || echo "❌ zoxide"
        
        echo ""
        echo "Profile: ${cfg.profile}"
        echo "All checks completed!"
      '';
    };
  };
}