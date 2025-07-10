# Web開発環境 - Tauri セキュリティ設定
# APIアクセス権限、サンドボックス設定、セキュリティポリシー

{ lib, pkgs, config, ... }:

let
  cfg = config.web.desktop.tauri.security;
in
{
  options.web.desktop.tauri.security = {
    enable = lib.mkEnableOption "Tauri security configuration";
    
    allowlist = {
      fs = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "read" "write" "readDir" "writeDir" "copyFile" "createDir" "removeDir" "removeFile" "renameFile" "exists" ]);
        default = [ "read" "readDir" "exists" ];
        description = "File system permissions";
      };
      
      shell = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "execute" "open" "sidecar" ]);
        default = [ "open" ];
        description = "Shell permissions";
      };
      
      window = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "all" "close" "hide" "maximize" "minimize" "show" "startDragging" "unmaximize" "unminimize" "setTitle" "setSize" "setPosition" ]);
        default = [ "close" "hide" "maximize" "minimize" "show" "startDragging" "unmaximize" "unminimize" ];
        description = "Window management permissions";
      };
      
      path = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable path API access";
      };
      
      os = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OS API access";
      };
      
      notification = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable notification API";
      };
      
      globalShortcut = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable global shortcut registration";
      };
      
      clipboard = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable clipboard access";
      };
      
      http = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable HTTP client";
      };
    };
    
    isolation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable pattern isolation (sandbox)";
    };
    
    csp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Content Security Policy";
      };
      
      policy = lib.mkOption {
        type = lib.types.str;
        default = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' data:; img-src 'self' data: blob:; font-src 'self' data:";
        description = "Content Security Policy string";
      };
      
      strict = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use strict CSP (no unsafe-inline)";
      };
    };
    
    dangerousDisableAssetCspModification = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable automatic CSP modification for assets";
    };
    
    freezePrototype = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Freeze JavaScript prototypes";
    };
    
    capabilities = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Custom security capabilities";
    };
    
    scope = {
      allowedPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "$HOME/Documents" "$HOME/Downloads" ];
        description = "Allowed file system paths";
      };
      
      deniedPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "$HOME/.ssh" "$HOME/.gnupg" "/etc" "/System" ];
        description = "Denied file system paths";
      };
      
      allowedUrls = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Allowed HTTP URLs";
      };
      
      deniedUrls = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Denied HTTP URLs";
      };
    };
    
    securityLevel = lib.mkOption {
      type = lib.types.enum [ "minimal" "standard" "strict" "paranoid" ];
      default = "standard";
      description = "Overall security level";
    };
  };

  config = lib.mkIf cfg.enable {
    # Security-focused Tauri configuration template
    home.file.".tauri-templates/tauri-security.conf.json" = {
      text = builtins.toJSON {
        security = {
          csp = if cfg.csp.enable then 
            (if cfg.csp.strict then 
              "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'"
            else 
              cfg.csp.policy)
          else null;
          
          dangerousDisableAssetCspModification = cfg.dangerousDisableAssetCspModification;
          freezePrototype = cfg.freezePrototype;
          
          pattern = if cfg.isolation then {
            use = "isolation";
            options = {
              dir = "../dist";
            };
          } else {
            use = "brownfield";
          };
        };
        
        allowlist = lib.mkMerge [
          {
            all = false;
          }
          
          # File system permissions
          (lib.mkIf (cfg.allowlist.fs != []) {
            fs = lib.mkMerge [
              { all = false; }
              (lib.genAttrs cfg.allowlist.fs (_: true))
              {
                scope = lib.mkMerge [
                  (lib.mkIf (cfg.scope.allowedPaths != []) {
                    allow = cfg.scope.allowedPaths;
                  })
                  (lib.mkIf (cfg.scope.deniedPaths != []) {
                    deny = cfg.scope.deniedPaths;
                  })
                ];
              }
            ];
          })
          
          # Shell permissions
          (lib.mkIf (cfg.allowlist.shell != []) {
            shell = lib.mkMerge [
              { all = false; }
              (lib.genAttrs cfg.allowlist.shell (_: true))
            ];
          })
          
          # Window permissions
          (lib.mkIf (cfg.allowlist.window != []) {
            window = lib.mkMerge [
              { all = elem "all" cfg.allowlist.window; }
              (lib.genAttrs (lib.filter (x: x != "all") cfg.allowlist.window) (_: true))
            ];
          })
          
          # Path API
          (lib.mkIf cfg.allowlist.path {
            path = { all = true; };
          })
          
          # OS API
          (lib.mkIf cfg.allowlist.os {
            os = { all = true; };
          })
          
          # Notification API
          (lib.mkIf cfg.allowlist.notification {
            notification = { all = true; };
          })
          
          # Global shortcut
          (lib.mkIf cfg.allowlist.globalShortcut {
            globalShortcut = { all = true; };
          })
          
          # Clipboard access
          (lib.mkIf cfg.allowlist.clipboard {
            clipboard = {
              all = true;
              writeText = true;
              readText = true;
            };
          })
          
          # HTTP client
          (lib.mkIf cfg.allowlist.http {
            http = lib.mkMerge [
              { all = true; }
              (lib.mkIf (cfg.scope.allowedUrls != []) {
                scope = {
                  allow = cfg.scope.allowedUrls;
                  deny = cfg.scope.deniedUrls;
                };
              })
            ];
          })
        ];
        
        # Custom capabilities
        capabilities = cfg.capabilities;
      };
    };
    
    # Security level presets
    home.file.".tauri-templates/security-presets.json" = {
      text = builtins.toJSON {
        minimal = {
          allowlist = {
            fs = [ "read" "readDir" "exists" ];
            shell = [ "open" ];
            window = [ "close" "hide" "show" ];
            path = true;
            os = false;
            notification = false;
            globalShortcut = false;
            clipboard = false;
            http = false;
          };
          isolation = true;
          csp = {
            enable = true;
            strict = false;
          };
          freezePrototype = true;
          securityLevel = "minimal";
        };
        
        standard = {
          allowlist = {
            fs = [ "read" "readDir" "exists" "write" "createDir" ];
            shell = [ "open" ];
            window = [ "close" "hide" "maximize" "minimize" "show" "startDragging" "unmaximize" "unminimize" ];
            path = true;
            os = false;
            notification = true;
            globalShortcut = false;
            clipboard = true;
            http = false;
          };
          isolation = true;
          csp = {
            enable = true;
            strict = false;
          };
          freezePrototype = true;
          securityLevel = "standard";
        };
        
        strict = {
          allowlist = {
            fs = [ "read" "readDir" "exists" ];
            shell = [];
            window = [ "close" "hide" "show" ];
            path = false;
            os = false;
            notification = false;
            globalShortcut = false;
            clipboard = false;
            http = false;
          };
          isolation = true;
          csp = {
            enable = true;
            strict = true;
          };
          freezePrototype = true;
          securityLevel = "strict";
        };
        
        paranoid = {
          allowlist = {
            fs = [];
            shell = [];
            window = [ "close" ];
            path = false;
            os = false;
            notification = false;
            globalShortcut = false;
            clipboard = false;
            http = false;
          };
          isolation = true;
          csp = {
            enable = true;
            strict = true;
          };
          freezePrototype = true;
          securityLevel = "paranoid";
        };
      };
    };
    
    # Security audit script
    home.file."bin/tauri-security-audit" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔒 Tauri Security Audit"
        echo "======================"
        
        if [[ ! -f "src-tauri/tauri.conf.json" ]]; then
          echo "❌ No Tauri project found in current directory"
          exit 1
        fi
        
        CONFIG_FILE="src-tauri/tauri.conf.json"
        
        echo "📁 Project: $(basename "$(pwd)")"
        echo "📄 Config: $CONFIG_FILE"
        echo ""
        
        # Security checks
        echo "🔍 Security Analysis:"
        echo "===================="
        
        # Check CSP
        if jq -e '.tauri.security.csp' "$CONFIG_FILE" > /dev/null 2>&1; then
          csp=$(jq -r '.tauri.security.csp' "$CONFIG_FILE")
          echo "✅ Content Security Policy: enabled"
          echo "   Policy: $csp"
          
          # Check for unsafe policies
          if echo "$csp" | grep -q "unsafe-inline\|unsafe-eval"; then
            echo "⚠️  Warning: CSP contains unsafe directives"
          fi
        else
          echo "❌ Content Security Policy: not configured"
        fi
        
        # Check isolation
        if jq -e '.tauri.security.pattern.use' "$CONFIG_FILE" > /dev/null 2>&1; then
          pattern=$(jq -r '.tauri.security.pattern.use' "$CONFIG_FILE")
          echo "✅ Security pattern: $pattern"
          
          if [[ "$pattern" == "isolation" ]]; then
            echo "   ✅ Isolation enabled (recommended)"
          else
            echo "   ⚠️  Warning: Isolation not enabled"
          fi
        else
          echo "❌ Security pattern: not configured"
        fi
        
        echo ""
        echo "🔑 Permission Analysis:"
        echo "======================"
        
        # Check allowlist
        permissions=(
          "fs:File system"
          "shell:Shell execution"
          "window:Window management"
          "path:Path API"
          "os:Operating system"
          "notification:Notifications"
          "globalShortcut:Global shortcuts"
          "clipboard:Clipboard"
          "http:HTTP client"
        )
        
        for perm_desc in "''${permissions[@]}"; do
          perm="''${perm_desc%%:*}"
          desc="''${perm_desc##*:}"
          
          if jq -e ".tauri.allowlist.$perm" "$CONFIG_FILE" > /dev/null 2>&1; then
            enabled=$(jq -r ".tauri.allowlist.$perm.all // false" "$CONFIG_FILE")
            if [[ "$enabled" == "true" ]]; then
              echo "⚠️  $desc: all permissions enabled"
            else
              specific_perms=$(jq -r ".tauri.allowlist.$perm | to_entries[] | select(.value == true) | .key" "$CONFIG_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
              if [[ -n "$specific_perms" ]]; then
                echo "✅ $desc: specific permissions ($specific_perms)"
              else
                echo "✅ $desc: disabled"
              fi
            fi
          else
            echo "✅ $desc: disabled"
          fi
        done
        
        echo ""
        echo "📊 Risk Assessment:"
        echo "=================="
        
        risk_score=0
        
        # Calculate risk score
        if jq -e '.tauri.allowlist.shell.all' "$CONFIG_FILE" | grep -q "true"; then
          echo "🚨 HIGH RISK: Shell execution enabled"
          risk_score=$((risk_score + 30))
        fi
        
        if jq -e '.tauri.allowlist.fs.all' "$CONFIG_FILE" | grep -q "true"; then
          echo "⚠️  MEDIUM RISK: Full file system access"
          risk_score=$((risk_score + 20))
        fi
        
        if jq -e '.tauri.allowlist.http.all' "$CONFIG_FILE" | grep -q "true"; then
          echo "⚠️  MEDIUM RISK: HTTP client enabled"
          risk_score=$((risk_score + 15))
        fi
        
        if ! jq -e '.tauri.security.csp' "$CONFIG_FILE" > /dev/null 2>&1; then
          echo "⚠️  MEDIUM RISK: No Content Security Policy"
          risk_score=$((risk_score + 15))
        fi
        
        if jq -e '.tauri.security.pattern.use' "$CONFIG_FILE" | grep -q "brownfield"; then
          echo "⚠️  LOW RISK: Brownfield pattern (no isolation)"
          risk_score=$((risk_score + 10))
        fi
        
        echo ""
        echo "📈 Overall Risk Score: $risk_score/100"
        
        if [[ $risk_score -le 20 ]]; then
          echo "✅ Security level: LOW RISK"
        elif [[ $risk_score -le 50 ]]; then
          echo "⚠️  Security level: MEDIUM RISK"
        else
          echo "🚨 Security level: HIGH RISK"
        fi
        
        echo ""
        echo "💡 Recommendations:"
        echo "=================="
        
        if [[ $risk_score -gt 50 ]]; then
          echo "1. Review and restrict API permissions"
          echo "2. Enable isolation pattern"
          echo "3. Implement strict CSP"
          echo "4. Disable unnecessary shell access"
        elif [[ $risk_score -gt 20 ]]; then
          echo "1. Review file system permissions"
          echo "2. Strengthen Content Security Policy"
          echo "3. Consider enabling isolation"
        else
          echo "1. Security configuration looks good!"
          echo "2. Regular security audits recommended"
        fi
        
        echo ""
        echo "🔧 Security Level: ${cfg.securityLevel}"
        echo "✅ Security audit completed!"
      '';
    };
    
    # Security configuration helper
    home.file."bin/tauri-security-config" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_usage() {
          cat << EOF
        Usage: tauri-security-config <level> [project-dir]
        
        SECURITY LEVELS:
          minimal    Basic security (development)
          standard   Balanced security (production)
          strict     High security (sensitive data)
          paranoid   Maximum security (critical apps)
          
        EXAMPLES:
          tauri-security-config standard
          tauri-security-config strict ./my-project
        EOF
        }
        
        LEVEL="$1"
        PROJECT_DIR="''${2:-.}"
        
        if [[ -z "$LEVEL" ]]; then
          echo "❌ Security level required"
          show_usage
          exit 1
        fi
        
        if [[ ! -f "$PROJECT_DIR/src-tauri/tauri.conf.json" ]]; then
          echo "❌ No Tauri project found in $PROJECT_DIR"
          exit 1
        fi
        
        echo "🔒 Configuring Tauri security level: $LEVEL"
        echo "📁 Project directory: $PROJECT_DIR"
        
        CONFIG_FILE="$PROJECT_DIR/src-tauri/tauri.conf.json"
        PRESET_FILE="$HOME/.tauri-templates/security-presets.json"
        
        if [[ ! -f "$PRESET_FILE" ]]; then
          echo "❌ Security presets file not found: $PRESET_FILE"
          exit 1
        fi
        
        # Backup original config
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        echo "📋 Backup created: $CONFIG_FILE.backup.*"
        
        # Apply security preset
        if jq -e ".$LEVEL" "$PRESET_FILE" > /dev/null 2>&1; then
          preset=$(jq ".$LEVEL" "$PRESET_FILE")
          
          # Update tauri.conf.json with security settings
          jq --argjson preset "$preset" '.tauri.allowlist = $preset.allowlist | .tauri.security.csp = (if $preset.csp.enable then (if $preset.csp.strict then "default-src '\''self'\''; script-src '\''self'\''; style-src '\''self'\''; img-src '\''self'\'' data:; font-src '\''self'\''" else "default-src '\''self'\''; script-src '\''self'\'' '\''unsafe-inline'\''; style-src '\''self'\'' '\''unsafe-inline'\'' data:; img-src '\''self'\'' data: blob:; font-src '\''self'\'' data:") else null end) | .tauri.security.freezePrototype = $preset.freezePrototype | .tauri.security.pattern.use = (if $preset.isolation then "isolation" else "brownfield" end)' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
          
          echo "✅ Security configuration applied successfully!"
          echo ""
          echo "📊 Applied settings:"
          echo "  Security level: $LEVEL"
          echo "  Isolation: $(jq -r '.isolation' <<< "$preset")"
          echo "  CSP enabled: $(jq -r '.csp.enable' <<< "$preset")"
          echo "  CSP strict: $(jq -r '.csp.strict' <<< "$preset")"
          echo ""
          echo "🔍 Run 'tauri-security-audit' to verify configuration"
        else
          echo "❌ Unknown security level: $LEVEL"
          echo "Available levels: minimal, standard, strict, paranoid"
          exit 1
        fi
      '';
    };
    
    # Shell aliases for security
    home.shellAliases = {
      "tauri-security" = "tauri-security-audit";
      "tauri-sec-config" = "tauri-security-config";
      "tauri-audit" = "tauri-security-audit";
    };
  };
}