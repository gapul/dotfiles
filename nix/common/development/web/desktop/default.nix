# Web開発環境 - デスクトップアプリ開発 (Tauri)
# Tauri開発環境の統合管理

{ lib, pkgs, config, ... }:

with lib;

{
  imports = [
    ./tauri-core.nix
    ./tauri-security.nix
  ];

  options.web.desktop = {
    enable = mkEnableOption "Desktop application development with Tauri";
    
    profile = mkOption {
      type = types.enum [ "basic" "standard" "advanced" "production" ];
      default = "standard";
      description = "Tauri development profile";
    };
    
    autoSetup = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically configure optimal settings";
    };
  };

  config = mkIf config.web.desktop.enable {
    # Enable core Tauri components
    web.desktop.tauri.enable = mkDefault true;
    web.desktop.tauri.security.enable = mkDefault true;
    
    # Profile-specific configurations
    web.desktop.tauri = mkMerge [
      (mkIf (config.web.desktop.profile == "basic") {
        rustToolchain.components = mkDefault [ "rust-src" "rustfmt" ];
        rustToolchain.targets = mkDefault [ 
          "x86_64-unknown-linux-gnu" 
          "x86_64-apple-darwin" 
        ];
        features.bundleFormats = mkDefault [ "appimage" "dmg" ];
        features.autoUpdater = mkDefault false;
        features.systemTray = mkDefault false;
        development.debugMode = mkDefault true;
      })
      (mkIf (config.web.desktop.profile == "standard") {
        rustToolchain.components = mkDefault [ "rust-src" "rustfmt" "clippy" "rust-analyzer" ];
        rustToolchain.targets = mkDefault [
          "x86_64-unknown-linux-gnu"
          "aarch64-unknown-linux-gnu"
          "x86_64-apple-darwin"
          "aarch64-apple-darwin"
        ];
        features.bundleFormats = mkDefault [ "deb" "appimage" "dmg" "app" ];
        features.autoUpdater = mkDefault true;
        features.systemTray = mkDefault true;
        features.notifications = mkDefault true;
        development.debugMode = mkDefault true;
      })
      (mkIf (config.web.desktop.profile == "advanced") {
        rustToolchain.components = mkDefault [ "rust-src" "rustfmt" "clippy" "rust-analyzer" ];
        rustToolchain.targets = mkDefault [
          "x86_64-unknown-linux-gnu"
          "aarch64-unknown-linux-gnu"
          "x86_64-pc-windows-gnu"
          "x86_64-apple-darwin"
          "aarch64-apple-darwin"
        ];
        features.bundleFormats = mkDefault [ "deb" "rpm" "appimage" "nsis" "msi" "dmg" "app" ];
        features.autoUpdater = mkDefault true;
        features.systemTray = mkDefault true;
        features.notifications = mkDefault true;
        development.debugMode = mkDefault true;
      })
      (mkIf (config.web.desktop.profile == "production") {
        rustToolchain.components = mkDefault [ "rust-src" "rustfmt" "clippy" "rust-analyzer" ];
        rustToolchain.targets = mkDefault [
          "x86_64-unknown-linux-gnu"
          "aarch64-unknown-linux-gnu"
          "x86_64-pc-windows-gnu"
          "x86_64-apple-darwin"
          "aarch64-apple-darwin"
        ];
        features.bundleFormats = mkDefault [ "deb" "rpm" "appimage" "nsis" "msi" "dmg" "app" ];
        features.autoUpdater = mkDefault true;
        features.systemTray = mkDefault true;
        features.notifications = mkDefault true;
        development.debugMode = mkDefault false;
        development.sourceMaps = mkDefault false;
      })
    ];
    
    web.desktop.tauri.security = mkMerge [
      (mkIf (config.web.desktop.profile == "basic") {
        securityLevel = mkDefault "minimal";
        allowlist.fs = mkDefault [ "read" "readDir" "exists" "write" "createDir" ];
        allowlist.shell = mkDefault [ "open" ];
        allowlist.window = mkDefault [ "close" "hide" "show" "maximize" "minimize" ];
        csp.strict = mkDefault false;
      })
      (mkIf (config.web.desktop.profile == "standard") {
        securityLevel = mkDefault "standard";
        allowlist.fs = mkDefault [ "read" "readDir" "exists" "write" "createDir" "copyFile" ];
        allowlist.shell = mkDefault [ "open" ];
        allowlist.window = mkDefault [ "close" "hide" "show" "maximize" "minimize" "startDragging" "unmaximize" "unminimize" ];
        allowlist.notification = mkDefault true;
        allowlist.clipboard = mkDefault true;
        csp.strict = mkDefault false;
      })
      (mkIf (config.web.desktop.profile == "advanced") {
        securityLevel = mkDefault "standard";
        allowlist.fs = mkDefault [ "read" "readDir" "exists" "write" "createDir" "copyFile" "removeFile" "renameFile" ];
        allowlist.shell = mkDefault [ "open" "sidecar" ];
        allowlist.window = mkDefault [ "all" ];
        allowlist.notification = mkDefault true;
        allowlist.clipboard = mkDefault true;
        allowlist.globalShortcut = mkDefault true;
        allowlist.http = mkDefault true;
        csp.strict = mkDefault false;
      })
      (mkIf (config.web.desktop.profile == "production") {
        securityLevel = mkDefault "strict";
        allowlist.fs = mkDefault [ "read" "readDir" "exists" ];
        allowlist.shell = mkDefault [ "open" ];
        allowlist.window = mkDefault [ "close" "hide" "show" "maximize" "minimize" ];
        allowlist.notification = mkDefault true;
        allowlist.clipboard = mkDefault false;
        allowlist.globalShortcut = mkDefault false;
        allowlist.http = mkDefault false;
        csp.strict = mkDefault true;
      })
    ];
    
    # Desktop development utilities
    home.packages = with pkgs; [
      # Icon generation tools
      imagemagick
      librsvg
      
      # Cross-platform build tools
      wine
      mingw-w64
      
      # Package verification tools
      file
      binutils
      
      # Performance profiling
      valgrind
      perf-tools
    ] ++ lib.optionals pkgs.stdenv.isLinux [
      # Linux packaging tools
      dpkg
      rpm
      fakeroot
      
      # AppImage tools
      appimage-run
    ];
    
    # Enhanced shell aliases
    home.shellAliases = {
      # Tauri development shortcuts
      "tauri-new" = "tauri-init";
      "tauri-start" = "tauri-dev";
      "tauri-release" = "tauri-build --release";
      
      # Cross-platform builds
      "tauri-linux-x64" = "npx @tauri-apps/cli build --target x86_64-unknown-linux-gnu";
      "tauri-linux-arm64" = "npx @tauri-apps/cli build --target aarch64-unknown-linux-gnu";
      "tauri-windows-x64" = "npx @tauri-apps/cli build --target x86_64-pc-windows-gnu";
      "tauri-macos-x64" = "npx @tauri-apps/cli build --target x86_64-apple-darwin";
      "tauri-macos-arm64" = "npx @tauri-apps/cli build --target aarch64-apple-darwin";
      
      # Security and audit
      "tauri-check" = "tauri-health && tauri-security-audit";
      "tauri-secure" = "tauri-security-config";
      
      # Development workflow
      "tauri-icons" = "npx @tauri-apps/cli icon";
      "tauri-signer" = "npx @tauri-apps/cli signer";
    };
    
    # Desktop app development workflow script
    home.file."bin/tauri-workflow" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_usage() {
          cat << EOF
        Usage: tauri-workflow <command> [options]
        
        COMMANDS:
          init        Initialize new Tauri project
          dev         Start development server
          build       Build for production
          bundle      Create distribution bundles
          test        Run tests (frontend + backend)
          audit       Security and dependency audit
          release     Complete release workflow
          icon        Generate app icons from SVG
          sign        Sign application bundles
          
        OPTIONS:
          --target TARGET    Build target (linux, windows, macos, all)
          --profile PROFILE  Build profile (dev, release)
          --security LEVEL   Security level (minimal, standard, strict)
          --format FORMAT    Bundle format (deb, rpm, dmg, msi, appimage)
          
        EXAMPLES:
          tauri-workflow init my-app react
          tauri-workflow dev
          tauri-workflow build --target linux --profile release
          tauri-workflow bundle --format deb,appimage
          tauri-workflow release --target all
        EOF
        }
        
        init_project() {
          local name="$1"
          local framework="''${2:-react}"
          
          echo "🚀 Initializing Tauri project: $name"
          tauri-init "$name" "$framework"
          
          cd "$name"
          
          # Apply security configuration based on profile
          tauri-security-config "${config.web.desktop.tauri.security.securityLevel}"
          
          echo "✅ Project initialized with ${config.web.desktop.profile} profile"
        }
        
        dev_server() {
          echo "🔄 Starting Tauri development server..."
          
          # Health check first
          tauri-health
          
          # Start development
          npx @tauri-apps/cli dev ${lib.optionalString config.web.desktop.tauri.development.hotReload "--features hot-reload"}
        }
        
        build_app() {
          local target="''${1:-}"
          local profile="''${2:-release}"
          
          echo "🏗️  Building Tauri application..."
          echo "Target: $target"
          echo "Profile: $profile"
          
          # Security audit before build
          tauri-security-audit
          
          # Build command
          local build_cmd="npx @tauri-apps/cli build"
          
          if [[ "$profile" == "release" ]]; then
            build_cmd="$build_cmd --release"
          fi
          
          case "$target" in
            linux)
              $build_cmd --target x86_64-unknown-linux-gnu
              ;;
            windows)
              $build_cmd --target x86_64-pc-windows-gnu
              ;;
            macos)
              $build_cmd --target x86_64-apple-darwin
              ;;
            macos-arm)
              $build_cmd --target aarch64-apple-darwin
              ;;
            all)
              echo "Building for all platforms..."
              ${lib.concatMapStringsSep "\n              " (target: 
                "$build_cmd --target ${target}"
              ) config.web.desktop.tauri.rustToolchain.targets}
              ;;
            "")
              $build_cmd
              ;;
            *)
              echo "❌ Unknown target: $target"
              exit 1
              ;;
          esac
          
          echo "✅ Build completed!"
        }
        
        bundle_app() {
          local formats="''${1:-${lib.concatStringsSep "," config.web.desktop.tauri.features.bundleFormats}}"
          
          echo "📦 Creating distribution bundles..."
          echo "Formats: $formats"
          
          # Set bundle formats in environment
          export TAURI_BUNDLE_FORMAT="$formats"
          
          npx @tauri-apps/cli build --bundles "$formats"
          
          # List created bundles
          echo ""
          echo "📋 Created bundles:"
          find src-tauri/target/release/bundle -type f -name "*.*" 2>/dev/null | while read -r bundle; do
            echo "  📄 $(basename "$bundle") ($(du -h "$bundle" | cut -f1))"
          done
          
          echo "✅ Bundling completed!"
        }
        
        test_app() {
          echo "🧪 Running Tauri tests..."
          
          # Frontend tests
          echo "Testing frontend..."
          npm test
          
          # Backend tests
          echo "Testing Rust backend..."
          cd src-tauri
          cargo test
          cd ..
          
          # Integration tests
          if [[ -d "tests" ]]; then
            echo "Running integration tests..."
            npm run test:e2e
          fi
          
          echo "✅ All tests passed!"
        }
        
        audit_app() {
          echo "🔍 Running security and dependency audit..."
          
          # Security audit
          tauri-security-audit
          
          # Rust dependency audit
          echo ""
          echo "🦀 Rust dependencies:"
          cd src-tauri
          cargo audit
          cd ..
          
          # Node.js dependency audit
          echo ""
          echo "📦 Node.js dependencies:"
          npm audit
          
          echo "✅ Audit completed!"
        }
        
        release_workflow() {
          local target="''${1:-all}"
          
          echo "🚀 Starting release workflow..."
          
          # Pre-release checks
          echo "1. Running tests..."
          test_app
          
          echo "2. Running audit..."
          audit_app
          
          echo "3. Building application..."
          build_app "$target" "release"
          
          echo "4. Creating bundles..."
          bundle_app
          
          # Code signing (if configured)
          if command -v tauri-signer &> /dev/null; then
            echo "5. Signing bundles..."
            # Sign bundles here
          fi
          
          echo "✅ Release workflow completed!"
          echo ""
          echo "📁 Release artifacts available in src-tauri/target/release/bundle/"
        }
        
        # Parse arguments
        COMMAND=""
        TARGET=""
        PROFILE="release"
        SECURITY=""
        FORMAT=""
        
        while [[ $# -gt 0 ]]; do
          case $1 in
            init|dev|build|bundle|test|audit|release|icon|sign)
              COMMAND="$1"
              shift
              ;;
            --target)
              TARGET="$2"
              shift 2
              ;;
            --profile)
              PROFILE="$2"
              shift 2
              ;;
            --security)
              SECURITY="$2"
              shift 2
              ;;
            --format)
              FORMAT="$2"
              shift 2
              ;;
            -h|--help)
              show_usage
              exit 0
              ;;
            *)
              if [[ -z "$COMMAND" ]]; then
                echo "Unknown command: $1"
                show_usage
                exit 1
              else
                # Pass remaining args to command
                break
              fi
              ;;
          esac
        done
        
        case "$COMMAND" in
          init)
            if [[ $# -lt 1 ]]; then
              echo "❌ Project name required"
              exit 1
            fi
            init_project "$@"
            ;;
          dev)
            dev_server
            ;;
          build)
            build_app "$TARGET" "$PROFILE"
            ;;
          bundle)
            bundle_app "''${FORMAT:-}"
            ;;
          test)
            test_app
            ;;
          audit)
            audit_app
            ;;
          release)
            release_workflow "$TARGET"
            ;;
          icon)
            npx @tauri-apps/cli icon "$@"
            ;;
          sign)
            npx @tauri-apps/cli signer "$@"
            ;;
          "")
            echo "❌ No command specified"
            show_usage
            exit 1
            ;;
          *)
            echo "❌ Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
        esac
      '';
    };
    
    # Desktop health check
    home.file."bin/desktop-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🖥️  Desktop Application Development Health Check"
        echo "=============================================="
        
        # Run Tauri health check
        if command -v tauri-health &> /dev/null; then
          tauri-health
          echo ""
        fi
        
        # Platform-specific checks
        echo "🏗️  Build Environment:"
        
        # Cross-compilation tools
        tools=(
          "wine:Windows compatibility layer"
          "x86_64-w64-mingw32-gcc:Windows cross-compiler"
        )
        
        for tool_desc in "''${tools[@]}"; do
          tool="''${tool_desc%%:*}"
          desc="''${tool_desc##*:}"
          
          if command -v "$tool" &> /dev/null; then
            echo "✅ $desc: available"
          else
            echo "⚪ $desc: not available"
          fi
        done
        
        # Package formats
        echo ""
        echo "📦 Packaging Support:"
        
        formats=(
          ${lib.concatMapStringsSep "\n          " (format: ''"${format}:${format} packaging"'') config.web.desktop.tauri.features.bundleFormats}
        )
        
        for format_desc in "''${formats[@]}"; do
          format="''${format_desc%%:*}"
          desc="''${format_desc##*:}"
          echo "✅ $desc: enabled"
        done
        
        # Current project status
        echo ""
        echo "📁 Current Project:"
        
        if [[ -f "src-tauri/Cargo.toml" ]]; then
          project_name=$(grep '^name = ' src-tauri/Cargo.toml | sed 's/name = "\(.*\)"/\1/')
          echo "✅ Tauri project: $project_name"
          
          # Check bundle configuration
          if [[ -f "src-tauri/tauri.conf.json" ]]; then
            bundle_formats=$(jq -r '.tauri.bundle.targets[]? // empty' src-tauri/tauri.conf.json 2>/dev/null | tr '\n' ',' | sed 's/,$//')
            if [[ -n "$bundle_formats" ]]; then
              echo "📦 Bundle formats: $bundle_formats"
            fi
            
            # Security check
            security_level="${config.web.desktop.tauri.security.securityLevel}"
            echo "🔒 Security level: $security_level"
          fi
        else
          echo "⚪ No Tauri project detected"
        fi
        
        echo ""
        echo "📊 Profile: ${config.web.desktop.profile}"
        echo "✅ Desktop development environment ready!"
      '';
    };
  };
}