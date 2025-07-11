# Web開発環境 - 高速ビルドツール統合
# Vite, Turbopack, SWC, Farm, esbuild, Webpack, Rollupの統合

{ lib, pkgs, config, ... }:

let
  cfg = config.web.buildTools;
in
{
  options.web.buildTools = {
    enable = lib.mkEnableOption "Web build tools integration";
    
    turbopack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Turbopack (Next.js bundler)";
      };
      
      nextjs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Next.js integration";
      };
      
      react = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable React integration";
      };
    };
    
    swc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable SWC (Speedy Web Compiler)";
      };
      
      typescript = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TypeScript compilation";
      };
      
      jsx = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable JSX transformation";
      };
      
      optimization = lib.mkOption {
        type = lib.types.enum [ "none" "basic" "aggressive" ];
        default = "basic";
        description = "Optimization level";
      };
    };
    
    vite = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Vite build tool";
      };
      
      plugins = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "react" "vue" "svelte" "solid" ]);
        default = [ "react" "vue" "svelte" ];
        description = "Vite plugins to enable";
      };
      
      optimization = lib.mkOption {
        type = lib.types.enum [ "development" "production" ];
        default = "production";
        description = "Build optimization mode";
      };
    };
    
    farm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Farm build tool";
      };
      
      rust = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Rust-based optimizations";
      };
      
      performance = lib.mkOption {
        type = lib.types.enum [ "balanced" "speed" "size" "maximum" ];
        default = "balanced";
        description = "Performance optimization focus";
      };
    };
    
    legacy = {
      webpack = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Webpack (legacy support)";
      };
      
      rollup = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Rollup (library builds)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core build tools
      nodejs_22
      
      # Next-generation bundlers
      nodePackages.vite
      nodePackages."@swc/cli"
      nodePackages."@swc/core"
      
      # Fast compilers
      esbuild
      
      # Development utilities
      nodePackages.concurrently
      nodePackages.cross-env
      nodePackages.dotenv-cli
      
      # Build analysis tools
      nodePackages.webpack-bundle-analyzer
      nodePackages.bundle-analyzer
      
    ] ++ lib.optionals cfg.legacy.webpack [
      nodePackages.webpack
      nodePackages.webpack-cli
      nodePackages.webpack-dev-server
    ] ++ lib.optionals cfg.legacy.rollup [
      nodePackages.rollup
    ];
    
    # Environment variables for build tools
    home-manager.users.yuki.home.sessionVariables = {
      # Vite optimizations
      VITE_CJS_TRACE = "true";
      VITE_CJS_IGNORE_WARNING = "true";
      
      # SWC configuration
      SWC_CACHE_DIR = "${config.xdg.cacheHome}/swc";
      
      # esbuild configuration
      ESBUILD_CACHE_DIR = "${config.xdg.cacheHome}/esbuild";
      
      # Node.js optimizations for build tools
      NODE_OPTIONS = "--max-old-space-size=4096 --experimental-vm-modules";
      
      # Build performance
      FORCE_COLOR = "1";
      CI = lib.mkIf config.web.buildTools.vite.optimization == "production" "true";
    };
    
    # Shell aliases for build tools
    home-manager.users.yuki.home.shellAliases = {
      # Vite shortcuts
      "vite-dev" = "vite";
      "vite-build" = "vite build";
      "vite-preview" = "vite preview";
      
      # SWC shortcuts
      "swc-compile" = "swc";
      "swc-watch" = "swc --watch";
      
      # esbuild shortcuts
      "esbuild-dev" = "esbuild --serve";
      "esbuild-build" = "esbuild --bundle --minify";
      
      # Build analysis
      "analyze" = "webpack-bundle-analyzer";
      "bundle-size" = "du -sh dist/ build/ .next/ .nuxt/ .output/";
      
      # Development servers
      "dev-server" = "vite --host";
      "build-watch" = "vite build --watch";
    };
    
    # Default Vite configuration
    home-manager.users.yuki.home.file."vite.config.template.js" = {
      text = ''
        import { defineConfig } from 'vite'
        ${lib.optionalString (lib.elem "react" cfg.vite.plugins) "import react from '@vitejs/plugin-react-swc'"}
        ${lib.optionalString (lib.elem "vue" cfg.vite.plugins) "import vue from '@vitejs/plugin-vue'"}
        ${lib.optionalString (lib.elem "svelte" cfg.vite.plugins) "import { svelte } from '@sveltejs/vite-plugin-svelte'"}
        
        export default defineConfig({
          plugins: [
            ${lib.optionalString (lib.elem "react" cfg.vite.plugins) "react(),"}
            ${lib.optionalString (lib.elem "vue" cfg.vite.plugins) "vue(),"}
            ${lib.optionalString (lib.elem "svelte" cfg.vite.plugins) "svelte(),"}
          ],
          
          build: {
            target: 'esnext',
            minify: '${if cfg.vite.optimization == "production" then "esbuild" else "false"}',
            sourcemap: ${if cfg.vite.optimization == "production" then "false" else "true"},
            rollupOptions: {
              output: {
                manualChunks: {
                  vendor: ['react', 'react-dom'],
                  utils: ['lodash', 'date-fns']
                }
              }
            }
          },
          
          server: {
            host: '0.0.0.0',
            port: 3000,
            open: true,
            hmr: {
              overlay: true
            }
          },
          
          preview: {
            host: '0.0.0.0',
            port: 4173,
            open: true
          },
          
          optimizeDeps: {
            include: ['react', 'react-dom']
          },
          
          define: {
            __DEV__: ${if cfg.vite.optimization == "development" then "true" else "false"}
          }
        })
      '';
    };
    
    # SWC configuration
    home-manager.users.yuki.home.file.".swcrc" = {
      text = builtins.toJSON {
        jsc = {
          target = "es2022";
          parser = lib.mkMerge [
            {
              syntax = "typescript";
              decorators = true;
              dynamicImport = true;
            }
            (lib.mkIf cfg.swc.jsx {
              tsx = true;
            })
          ];
          transform = lib.mkMerge [
            (lib.mkIf cfg.swc.jsx {
              react = {
                runtime = "automatic";
                development = cfg.swc.optimization != "aggressive";
                refresh = cfg.swc.optimization == "none";
              };
            })
          ];
          minify = {
            compress = cfg.swc.optimization == "aggressive";
            mangle = cfg.swc.optimization == "aggressive";
          };
        };
        
        module = {
          type = "es6";
          strict = true;
          strictMode = true;
          lazy = false;
          noInterop = false;
        };
        
        minify = cfg.swc.optimization == "aggressive";
        
        env = {
          targets = {
            chrome = "90";
            firefox = "90";
            safari = "14";
            edge = "90";
          };
          mode = "entry";
          coreJs = "3.22";
        };
      };
    };
    
    # Build optimization script
    home-manager.users.yuki.home.file."bin/build-optimize" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🚀 Build Optimization Tool"
        echo "========================="
        
        PROJECT_TYPE=""
        
        # Detect project type
        if [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]]; then
          PROJECT_TYPE="nextjs"
        elif [[ -f "vite.config.js" ]] || [[ -f "vite.config.ts" ]]; then
          PROJECT_TYPE="vite"
        elif [[ -f "webpack.config.js" ]]; then
          PROJECT_TYPE="webpack"
        elif [[ -f "rollup.config.js" ]]; then
          PROJECT_TYPE="rollup"
        else
          echo "⚠️  No build configuration detected"
          echo "Creating default Vite configuration..."
          cp ~/vite.config.template.js ./vite.config.js
          PROJECT_TYPE="vite"
        fi
        
        echo "📦 Detected project type: $PROJECT_TYPE"
        
        # Optimize based on project type
        case "$PROJECT_TYPE" in
          nextjs)
            echo "🏗️  Optimizing Next.js build..."
            ${if cfg.turbopack.enable then ''
              echo "⚡ Using Turbopack..."
              npm run build -- --turbo
            '' else ''
              npm run build
            ''}
            ;;
          vite)
            echo "⚡ Optimizing Vite build..."
            vite build --mode production
            ;;
          webpack)
            echo "📦 Optimizing Webpack build..."
            npx webpack --mode=production --optimize-minimize
            ;;
          rollup)
            echo "🎯 Optimizing Rollup build..."
            npx rollup -c --environment NODE_ENV:production
            ;;
        esac
        
        # Build analysis
        if [[ -d "dist" ]] || [[ -d "build" ]] || [[ -d ".next" ]]; then
          echo ""
          echo "📊 Build Analysis:"
          echo "=================="
          
          # Size analysis
          if [[ -d "dist" ]]; then
            echo "📁 dist/: $(du -sh dist/ | cut -f1)"
          fi
          
          if [[ -d "build" ]]; then
            echo "📁 build/: $(du -sh build/ | cut -f1)"
          fi
          
          if [[ -d ".next" ]]; then
            echo "📁 .next/: $(du -sh .next/ | cut -f1)"
          fi
          
          # Performance recommendations
          echo ""
          echo "💡 Performance Recommendations:"
          echo "==============================="
          echo "• Consider code splitting for large bundles"
          echo "• Use dynamic imports for non-critical code"
          echo "• Enable gzip compression in production"
          echo "• Optimize images and assets"
          echo "• Use a CDN for static assets"
        fi
        
        echo ""
        echo "✅ Build optimization completed!"
      '';
    };
    
    # Development server wrapper
    home-manager.users.yuki.home.file."bin/dev-start" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🚀 Starting development server..."
        
        # Detect and start appropriate dev server
        if [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]]; then
          echo "⚡ Starting Next.js with ${if cfg.turbopack.enable then "Turbopack" else "default bundler"}..."
          ${if cfg.turbopack.enable then ''
            npm run dev -- --turbo
          '' else ''
            npm run dev
          ''}
        elif [[ -f "vite.config.js" ]] || [[ -f "vite.config.ts" ]]; then
          echo "⚡ Starting Vite dev server..."
          vite --host 0.0.0.0
        elif [[ -f "package.json" ]]; then
          echo "📦 Starting npm dev server..."
          npm run dev
        else
          echo "❌ No development configuration found"
          echo "Run 'project-init' to set up a new project"
          exit 1
        fi
      '';
    };
  };
}