# Web開発環境 - フレームワーク統合モジュール
# React、Vue、Svelte、Astroフレームワークの統合管理

{ lib, pkgs, config, ... }:

with lib;

{
  imports = [
    ./react
  ];

  options.web.frameworks = {
    enable = mkEnableOption "Web development frameworks";
    
    primary = mkOption {
      type = types.enum [ "react" "vue" "svelte" "astro" ];
      default = "react";
      description = "Primary framework for development";
    };
    
    enabled = mkOption {
      type = types.listOf (types.enum [ "react" "vue" "svelte" "astro" ]);
      default = [ "react" ];
      description = "List of enabled frameworks";
    };
    
    typescript = mkOption {
      type = types.bool;
      default = true;
      description = "Enable TypeScript support for all frameworks";
    };
    
    testing = mkOption {
      type = types.enum [ "vitest" "jest" ];
      default = "vitest";
      description = "Default testing framework";
    };
    
    bundler = mkOption {
      type = types.enum [ "vite" "webpack" "turbopack" ];
      default = "vite";
      description = "Default bundler";
    };
  };

  config = mkIf config.web.frameworks.enable {
    # Enable specific frameworks
    web.frameworks.react.enable = mkDefault (elem "react" config.web.frameworks.enabled);
    
    # Framework development packages
    home.packages = with pkgs; [
      nodejs_22
      nodePackages.npm
      nodePackages.pnpm
      bun
      
      # Universal tools
      nodePackages.typescript
      nodePackages.eslint
      nodePackages.prettier
      nodePackages.vitest
    ];
    
    # Shell aliases for framework development
    home.shellAliases = {
      # Framework shortcuts based on primary
      "fw-init" = 
        if config.web.frameworks.primary == "react" then "react-init"
        else if config.web.frameworks.primary == "vue" then "vue-init"
        else if config.web.frameworks.primary == "svelte" then "svelte-init"
        else if config.web.frameworks.primary == "astro" then "astro-init"
        else "react-init";
      
      "fw-dev" = "npm run dev";
      "fw-build" = "npm run build";
      "fw-test" = "npm test";
      "fw-lint" = "npm run lint";
      
      # Universal development commands
      "dev-start" = "npm run dev";
      "build-app" = "npm run build";
      "test-app" = "npm test";
      "lint-app" = "npm run lint";
    };
    
    # Framework health check
    home.file."bin/frameworks-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🏗️  Web Frameworks Health Check"
        echo "=============================="
        
        # Check enabled frameworks
        echo "📦 Enabled Frameworks:"
        
        frameworks=(
          ${concatMapStringsSep "\n          " (fw: ''"${fw}"'') config.web.frameworks.enabled}
        )
        
        for framework in "''${frameworks[@]}"; do
          case "$framework" in
            react)
              if command -v react-health &> /dev/null; then
                echo "✅ React: configured"
              else
                echo "❌ React: not properly configured"
              fi
              ;;
            vue)
              echo "⚪ Vue: configured but not yet implemented"
              ;;
            svelte)
              echo "⚪ Svelte: configured but not yet implemented"
              ;;
            astro)
              echo "⚪ Astro: configured but not yet implemented"
              ;;
          esac
        done
        
        echo ""
        echo "📊 Configuration:"
        echo "Primary framework: ${config.web.frameworks.primary}"
        echo "Enabled frameworks: ${toString config.web.frameworks.enabled}"
        echo "TypeScript: ${if config.web.frameworks.typescript then "enabled" else "disabled"}"
        echo "Testing framework: ${config.web.frameworks.testing}"
        echo "Default bundler: ${config.web.frameworks.bundler}"
        
        # Run specific framework health checks
        echo ""
        echo "🔍 Detailed Health Checks:"
        
        for framework in "''${frameworks[@]}"; do
          if command -v "''${framework}-health" &> /dev/null; then
            echo ""
            "''${framework}-health"
          fi
        done
        
        echo ""
        echo "✅ Frameworks health check completed!"
      '';
    };
  };
}