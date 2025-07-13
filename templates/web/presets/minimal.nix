# 軽量Web開発環境 - 最小構成
{ lib, pkgs, ... }:

{
  options.web-minimal = {
    enable = lib.mkEnableOption "Minimal web development environment";
  };

  config = lib.mkIf config.web-minimal.enable {
    # 最小限のパッケージのみ
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core tools only
      nodejs_22
      nodePackages.npm
      
      # Essential development tools
      nodePackages.typescript
      nodePackages.eslint
      nodePackages.prettier
      
      # Modern CLI (already in core)
      # bat, eza, ripgrep, fd - from core
    ];
    
    # Basic shell aliases
    home-manager.users.yuki.home.shellAliases = {
      "dev" = "npm run dev";
      "build" = "npm run build";
      "test" = "npm test";
      "lint" = "npm run lint";
    };
    
    # Minimal health check
    home-manager.users.yuki.home.file."bin/web-minimal-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🌐 Minimal Web Environment Health"
        echo "==============================="
        
        if command -v node &> /dev/null; then
          echo "✅ Node.js: $(node --version)"
        else
          echo "❌ Node.js: Not installed"
        fi
        
        if command -v npm &> /dev/null; then
          echo "✅ npm: $(npm --version)"
        else
          echo "❌ npm: Not installed"
        fi
        
        if command -v tsc &> /dev/null; then
          echo "✅ TypeScript: $(tsc --version)"
        else
          echo "❌ TypeScript: Not installed"
        fi
      '';
    };
  };
}