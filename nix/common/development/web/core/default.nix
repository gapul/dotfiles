# Web開発環境 - コア統合モジュール
# Node.js/Bun/Deno環境、パッケージマネージャー、ビルドツールの統合

{ lib, pkgs, config, ... }:

with lib;

{
  imports = [
    ./runtime.nix
    ./package-managers.nix
    ./build-tools.nix
  ];

  options.web.core = {
    enable = mkEnableOption "Web development core environment";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" "performance" ];
      default = "standard";
      description = "Web development core profile";
    };
    
    autoSetup = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically configure optimal settings";
    };
  };

  config = mkIf config.web.core.enable {
    # Enable core components
    web.runtime.enable = mkDefault true;
    web.packageManagers.enable = mkDefault true;
    web.buildTools.enable = mkDefault true;
    
    # Profile-specific runtime configurations
    web.runtime.bun = mkDefault (
      elem config.web.core.profile [ "standard" "full" "performance" ]
    );
    web.runtime.deno = mkDefault (
      elem config.web.core.profile [ "standard" "full" "performance" ]
    );
    web.runtime.workerd = mkDefault (
      elem config.web.core.profile [ "full" "performance" ]
    );
    
    # Profile-specific package manager configurations
    web.packageManagers.primary = mkDefault (
      if config.web.core.profile == "minimal" then "npm"
      else "bun"
    );
    web.packageManagers.fallback = mkDefault (
      if config.web.core.profile == "minimal" then [ "pnpm" ]
      else if config.web.core.profile == "standard" then [ "pnpm" "npm" ]
      else [ "pnpm" "npm" "yarn" ]
    ];
    
    # Profile-specific build tool configurations
    web.buildTools.turbopack.enable = mkDefault (
      elem config.web.core.profile [ "standard" "full" "performance" ]
    );
    web.buildTools.swc.optimization = mkDefault (
      if config.web.core.profile == "minimal" then "none"
      else if config.web.core.profile == "standard" then "basic"
      else "aggressive"
    );
    web.buildTools.vite.optimization = mkDefault (
      if config.web.core.profile == "minimal" then "development"
      else "production"
    );
    web.buildTools.farm.enable = mkDefault (
      elem config.web.core.profile [ "full" "performance" ]
    );
    
    # Enhanced shell configuration for web development
    home.shellAliases = {
      # Quick project commands
      "web-init" = "npx create-vite@latest";
      "react-init" = "npx create-react-app";
      "next-init" = "npx create-next-app@latest";
      "vue-init" = "npx create-vue@latest";
      "svelte-init" = "npx create-svelte@latest";
      "astro-init" = "npx create-astro@latest";
      
      # Development workflow
      "dev" = "dev-start";
      "build" = "build-optimize";
      "preview" = "vite preview";
      
      # Package management shortcuts
      "deps" = "pm install";
      "add-dev" = "pm add --dev";
      "outdated" = "pm outdated";
      
      # Code quality
      "lint" = "eslint . --ext .js,.jsx,.ts,.tsx,.vue,.svelte";
      "format" = "prettier --write .";
      "type-check" = "tsc --noEmit";
    };
    
    # Web development utilities
    home.packages = with pkgs; [
      # Modern CLI tools for web development
      tree-sitter
      
      # Image optimization
      imagemagick
      oxipng
      jpegoptim
      
      # Performance monitoring
      hyperfine
      
      # Network utilities
      websocat
      httpie
      
      # JSON/YAML processing
      jq
      yq-go
      
      # Git utilities for web projects
      git-filter-repo
      git-lfs
    ];
    
    # Project templates directory
    home.file.".web-templates" = {
      source = pkgs.writeTextDir "README.md" ''
        # Web Development Templates
        
        This directory contains project templates for quick initialization.
        
        ## Available Templates
        
        - `react/` - React with Vite
        - `vue/` - Vue 3 with Vite  
        - `svelte/` - SvelteKit
        - `next/` - Next.js 15+ App Router
        - `astro/` - Astro 4
        - `node/` - Node.js backend
        - `tauri/` - Tauri desktop app
        
        ## Usage
        
        ```bash
        cp -r ~/.web-templates/<template> <project-name>
        cd <project-name>
        pm install
        ```
      '';
      recursive = true;
    };
    
    # Global gitignore for web projects
    home.file.".gitignore_global_web" = {
      text = ''
        # Dependencies
        node_modules/
        .pnp
        .pnp.js
        .yarn/install-state.gz
        
        # Production builds
        build/
        dist/
        .next/
        .nuxt/
        .output/
        .vercel/
        .netlify/
        .firebase/
        
        # Development
        .env
        .env.local
        .env.development.local
        .env.test.local
        .env.production.local
        
        # IDE
        .vscode/
        .idea/
        *.swp
        *.swo
        
        # OS
        .DS_Store
        Thumbs.db
        
        # Logs
        *.log
        logs/
        npm-debug.log*
        yarn-debug.log*
        yarn-error.log*
        
        # Runtime
        *.pid
        *.seed
        *.pid.lock
        
        # Coverage
        coverage/
        .nyc_output/
        
        # Cache directories
        .cache/
        .parcel-cache/
        .turbo/
        .swc/
        .next/cache/
        
        # Testing
        .jest/
        
        # Temporary folders
        tmp/
        temp/
      '';
    };
    
    # Web development health check
    home.file."bin/web-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🌐 Web Development Environment Health Check"
        echo "=========================================="
        
        # Check runtimes
        echo "🔧 Runtime Environment:"
        
        runtimes=(
          "node:Node.js"
          "bun:Bun"
          "deno:Deno"
        )
        
        for runtime_desc in "''${runtimes[@]}"; do
          runtime="''${runtime_desc%%:*}"
          desc="''${runtime_desc##*:}"
          
          if command -v "$runtime" &> /dev/null; then
            version=$($runtime --version 2>/dev/null || echo "unknown")
            echo "✅ $desc: $version"
          else
            echo "❌ $desc: not found"
          fi
        done
        
        echo ""
        echo "📦 Package Managers:"
        
        package_managers=(
          "npm:npm"
          "pnpm:pnpm" 
          "yarn:Yarn"
          "bun:Bun"
        )
        
        for pm_desc in "''${package_managers[@]}"; do
          pm="''${pm_desc%%:*}"
          desc="''${pm_desc##*:}"
          
          if command -v "$pm" &> /dev/null; then
            version=$($pm --version 2>/dev/null || echo "unknown")
            echo "✅ $desc: $version"
          else
            echo "❌ $desc: not found"
          fi
        done
        
        echo ""
        echo "🛠️  Build Tools:"
        
        build_tools=(
          "vite:Vite"
          "esbuild:esbuild"
          "swc:SWC"
        )
        
        for tool_desc in "''${build_tools[@]}"; do
          tool="''${tool_desc%%:*}"
          desc="''${tool_desc##*:}"
          
          if command -v "$tool" &> /dev/null; then
            echo "✅ $desc: available"
          else
            echo "❌ $desc: not found"
          fi
        done
        
        # Check project detection
        echo ""
        echo "📁 Current Project:"
        
        if [[ -f "package.json" ]]; then
          project_name=$(jq -r '.name // "unnamed"' package.json)
          echo "✅ Project: $project_name"
          
          if [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]]; then
            echo "🚀 Framework: Next.js"
          elif [[ -f "vite.config.js" ]] || [[ -f "vite.config.ts" ]]; then
            echo "⚡ Build tool: Vite"
          elif [[ -f "svelte.config.js" ]]; then
            echo "🎭 Framework: SvelteKit"
          elif [[ -f "nuxt.config.js" ]] || [[ -f "nuxt.config.ts" ]]; then
            echo "💚 Framework: Nuxt"
          fi
          
          # Check package manager
          detected_pm=$(detect-pm 2>/dev/null || echo "npm")
          echo "📦 Package manager: $detected_pm"
        else
          echo "⚪ No web project detected in current directory"
        fi
        
        echo ""
        echo "💡 Profile: ${config.web.core.profile}"
        echo "✅ Web development environment ready!"
      '';
    };
  };
}