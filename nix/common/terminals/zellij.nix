# Zellij Terminal Multiplexer Configuration
# Modern Rust-based alternative to tmux with built-in UI
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.terminals.zellij;
in
{
  options.dotfiles.terminals.zellij = {
    enable = mkEnableOption "Zellij terminal multiplexer";
    
    configFile = mkOption {
      type = types.path;
      default = ../../../configs/terminals/zellij/config.kdl;
      description = "Path to Zellij configuration file";
    };
    
    defaultSession = mkOption {
      type = types.str;
      default = "main";
      description = "Default session name";
    };
    
    autoAttach = mkOption {
      type = types.bool;
      default = true;
      description = "Auto-attach to existing session if available";
    };
  };

  config = mkIf cfg.enable {
    # Zellij is available in nixpkgs
    home-manager.users.yuki.home.packages = with pkgs; [
      zellij
    ];
    
    # Link configuration file
    home-manager.users.yuki.home.file.".config/zellij/config.kdl" = {
      source = cfg.configFile;
    };
    
    # Session management aliases
    home-manager.users.yuki.home.shellAliases = {
      # Zellij session management
      "zj" = "zellij";
      "zls" = "zellij list-sessions";
      "za" = "zellij attach";
      "zn" = "zellij --session";
      "zk" = "zellij kill-session";
      "zd" = "zellij delete-session";
      
      # Development layouts
      "zdev" = "zellij --layout dev";
      "zweb" = "zellij --layout web";
      
      # Auto-attach to main session or create new
      "z" = "zellij attach main || zellij --session main";
      
      # Quick session commands
      "project-session" = "zellij --session $(basename $(pwd))";
    };
    
    # Environment variables
    home-manager.users.yuki.home.sessionVariables = {
      ZELLIJ_AUTO_ATTACH = if cfg.autoAttach then "true" else "false";
      ZELLIJ_AUTO_EXIT = "true";
    };
    
    # Zellij health check script
    home-manager.users.yuki.home.file."bin/zellij-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🚀 Zellij Terminal Multiplexer Status"
        echo "==================================="
        
        # Check if Zellij is installed
        if command -v zellij &> /dev/null; then
          echo "✅ Zellij: Installed"
          echo "   Version: $(zellij --version)"
        else
          echo "❌ Zellij: Not installed"
          return 1
        fi
        
        # Check configuration file
        if [[ -f "$HOME/.config/zellij/config.kdl" ]]; then
          echo "✅ Configuration: Found"
        else
          echo "❌ Configuration: Missing"
        fi
        
        # Check active sessions
        local sessions=$(zellij list-sessions 2>/dev/null || echo "")
        if [[ -n "$sessions" ]]; then
          echo "📋 Active Sessions:"
          echo "$sessions" | sed 's/^/   /'
        else
          echo "📋 Active Sessions: None"
        fi
        
        # Check if running inside Zellij
        if [[ -n "$ZELLIJ" ]]; then
          echo "🔄 Current Session: $ZELLIJ_SESSION_NAME"
        else
          echo "🔄 Current Session: Not in Zellij"
        fi
        
        echo ""
        echo "📚 Quick Commands:"
        echo "  z                 - Attach to main session"
        echo "  zdev              - Start development layout"
        echo "  zweb              - Start web development layout"
        echo "  project-session   - Create session based on current directory"
        echo "  zls               - List sessions"
        echo "  za <session>      - Attach to session"
        echo "  zk <session>      - Kill session"
      '';
    };
    
    # Session manager script
    home-manager.users.yuki.home.file."bin/zellij-session-manager" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_help() {
          cat << EOF
        Zellij Session Manager
        
        USAGE:
            zellij-session-manager <command> [options]
        
        COMMANDS:
            list                List all sessions
            new <name>          Create new session
            attach <name>       Attach to session
            kill <name>         Kill session
            killall             Kill all sessions
            rename <old> <new>  Rename session
            
        LAYOUTS:
            dev                 Development layout
            web                 Web development layout
            
        EXAMPLES:
            zellij-session-manager new work
            zellij-session-manager attach work
            zellij-session-manager list
        EOF
        }
        
        case "''${1:-}" in
          list)
            echo "📋 Zellij Sessions:"
            zellij list-sessions || echo "No sessions found"
            ;;
          new)
            if [[ $# -lt 2 ]]; then
              echo "Usage: zellij-session-manager new <session_name>"
              exit 1
            fi
            session_name="$2"
            layout="''${3:-dev}"
            echo "🚀 Creating session: $session_name (layout: $layout)"
            zellij --session "$session_name" --layout "$layout"
            ;;
          attach)
            if [[ $# -lt 2 ]]; then
              echo "Usage: zellij-session-manager attach <session_name>"
              exit 1
            fi
            session_name="$2"
            echo "🔗 Attaching to session: $session_name"
            zellij attach "$session_name"
            ;;
          kill)
            if [[ $# -lt 2 ]]; then
              echo "Usage: zellij-session-manager kill <session_name>"
              exit 1
            fi
            session_name="$2"
            echo "🗑️  Killing session: $session_name"
            zellij kill-session "$session_name"
            ;;
          killall)
            echo "🗑️  Killing all sessions..."
            zellij list-sessions | while read -r session; do
              [[ -n "$session" ]] && zellij kill-session "$session" 2>/dev/null || true
            done
            echo "✅ All sessions killed"
            ;;
          rename)
            if [[ $# -lt 3 ]]; then
              echo "Usage: zellij-session-manager rename <old_name> <new_name>"
              exit 1
            fi
            echo "Note: Zellij doesn't support session renaming directly"
            echo "You'll need to create a new session and migrate manually"
            ;;
          -h|--help|help)
            show_help
            ;;
          "")
            show_help
            ;;
          *)
            echo "Unknown command: $1"
            show_help
            exit 1
            ;;
        esac
      '';
    };
    
    # Auto-start script for shell integration
    home-manager.users.yuki.home.file."bin/zellij-auto-start" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Auto-start Zellij if not already inside a session
        
        # Don't start if already in Zellij
        [[ -n "$ZELLIJ" ]] && return
        
        # Don't start in non-interactive shells
        [[ $- != *i* ]] && return
        
        # Don't start in certain terminals (like IDEs)
        [[ -n "$VSCODE_TERM" ]] && return
        [[ -n "$EMACS" ]] && return
        
        # Auto-attach to main session or create new one
        if ${if cfg.autoAttach then "true" else "false"}; then
          exec zellij attach ${cfg.defaultSession} || zellij --session ${cfg.defaultSession}
        fi
      '';
    };
  };
}