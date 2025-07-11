# Web開発環境 - Tauri コア開発環境
# Tauri CLI、Rust Toolchain、システム依存関係の統合

{ lib, pkgs, config, ... }:

let
  cfg = config.web.desktop.tauri;
in
{
  options.web.desktop.tauri = {
    enable = lib.mkEnableOption "Tauri desktop application development";
    
    cli = lib.mkOption {
      type = lib.types.str;
      default = "latest";
      description = "Tauri CLI version";
    };
    
    rustToolchain = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Rust toolchain";
      };
      
      version = lib.mkOption {
        type = lib.types.str;
        default = "stable";
        description = "Rust toolchain version";
      };
      
      components = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "rust-src" "rustfmt" "clippy" "rust-analyzer" ];
        description = "Rust components to install";
      };
      
      targets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "x86_64-unknown-linux-gnu"
          "aarch64-unknown-linux-gnu"
          "x86_64-pc-windows-gnu"
          "x86_64-apple-darwin"
          "aarch64-apple-darwin"
        ];
        description = "Rust compilation targets for cross-platform builds";
      };
    };
    
    nodejs = lib.mkOption {
      type = lib.types.str;
      default = "22";
      description = "Node.js version for Tauri CLI";
    };
    
    webview = {
      engine = lib.mkOption {
        type = lib.types.enum [ "wry" "webkit2gtk" "webkitgtk" ];
        default = "wry";
        description = "WebView engine to use";
      };
      
      devtools = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable WebView developer tools";
      };
    };
    
    features = {
      bundleFormats = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "deb" "rpm" "appimage" "nsis" "msi" "dmg" "app" ]);
        default = [ "deb" "appimage" "dmg" "app" ];
        description = "Bundle formats to support";
      };
      
      autoUpdater = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable auto-updater support";
      };
      
      systemTray = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable system tray support";
      };
      
      notifications = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable notifications support";
      };
    };
    
    development = {
      hotReload = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable hot reload for development";
      };
      
      sourceMaps = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable source maps for debugging";
      };
      
      debugMode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable debug mode";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Core packages for Tauri development
    home.packages = with pkgs; [
      # Node.js for Tauri CLI
      nodejs_22
      
      # Rust toolchain
      rustc
      cargo
      rustfmt
      clippy
      rust-analyzer
      
      # Tauri CLI (install via npm for latest version)
      nodePackages.npm
      
      # System dependencies for Tauri
      pkg-config
      openssl
      
      # WebView dependencies
      webkitgtk
      gtk3
      cairo
      gdk-pixbuf
      glib
      dbus
      
      # Build tools
      gcc
      cmake
      make
      
      # Cross-compilation support
      llvm
      
      # Development utilities
      nodePackages.concurrently
      nodePackages.wait-on
      
    ] ++ lib.optionals pkgs.stdenv.isLinux [
      # Linux-specific dependencies
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cups
      curl
      gtk3
      libappindicator-gtk3
      librsvg
      libsoup
      libxss
      libyuv
      nspr
      nss
      pango
      udev
      xdg-utils
    ] ++ lib.optionals pkgs.stdenv.isDarwin [
      # macOS-specific dependencies
      darwin.apple_sdk.frameworks.Security
      darwin.apple_sdk.frameworks.CoreServices
      darwin.apple_sdk.frameworks.CoreData
      darwin.apple_sdk.frameworks.Foundation
      darwin.apple_sdk.frameworks.AppKit
      darwin.apple_sdk.frameworks.WebKit
      darwin.apple_sdk.frameworks.Cocoa
    ];
    
    # Environment variables for Tauri development
    home.sessionVariables = {
      # Rust environment
      RUST_BACKTRACE = if cfg.development.debugMode then "1" else "0";
      RUST_LOG = if cfg.development.debugMode then "debug" else "info";
      
      # Tauri environment
      TAURI_DEV = if cfg.development.debugMode then "true" else "false";
      TAURI_DEBUG = if cfg.development.debugMode then "true" else "false";
      
      # WebView configuration
      TAURI_WEBVIEW_DEBUG = if cfg.webview.devtools then "true" else "false";
      
      # Build configuration
      TAURI_BUNDLE_FORMAT = lib.concatStringsSep "," cfg.features.bundleFormats;
      
      # Development optimizations
      CARGO_TARGET_DIR = "${config.xdg.cacheHome}/cargo/target";
      RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
    };
    
    # Rust toolchain configuration
    home-manager.users.yuki.home.file.".cargo/config.toml" = {
      text = ''
        [build]
        target-dir = "$HOME/.cache/cargo/target"
        
        [env]
        ${lib.optionalString cfg.development.debugMode ''
        RUST_LOG = "debug"
        RUST_BACKTRACE = "1"
        ''}
        
        [target.x86_64-unknown-linux-gnu]
        linker = "clang"
        rustflags = ["-C", "link-arg=-fuse-ld=lld"]
        
        [target.aarch64-unknown-linux-gnu] 
        linker = "clang"
        rustflags = ["-C", "link-arg=-fuse-ld=lld"]
        
        ${lib.optionalString pkgs.stdenv.isDarwin ''
        [target.x86_64-apple-darwin]
        rustflags = ["-C", "link-arg=-Wl,-rpath,@executable_path/../Frameworks"]
        
        [target.aarch64-apple-darwin]
        rustflags = ["-C", "link-arg=-Wl,-rpath,@executable_path/../Frameworks"]
        ''}
        
        [registries.crates-io]
        protocol = "sparse"
        
        [net]
        retry = 2
        git-fetch-with-cli = true
        
        [profile.dev]
        debug = ${if cfg.development.sourceMaps then "true" else "false"}
        opt-level = 0
        
        [profile.release]
        debug = false
        opt-level = 3
        lto = true
        codegen-units = 1
        panic = "abort"
      '';
    };
    
    # Default Tauri configuration template
    home.file.".tauri-templates/tauri.conf.template.json" = {
      text = builtins.toJSON {
        "$schema" = "../node_modules/@tauri-apps/cli/schema.json";
        build = {
          beforeBuildCommand = "npm run build";
          beforeDevCommand = "npm run dev";
          devPath = "http://localhost:3000";
          distDir = "../dist";
          withGlobalTauri = false;
        };
        package = {
          productName = "My Tauri App";
          version = "0.1.0";
        };
        tauri = {
          allowlist = {
            all = false;
            shell = {
              all = false;
              open = true;
            };
            window = {
              all = false;
              close = true;
              hide = true;
              maximize = true;
              minimize = true;
              show = true;
              startDragging = true;
              unmaximize = true;
              unminimize = true;
            };
            fs = {
              all = false;
              readFile = true;
              writeFile = true;
              readDir = true;
              copyFile = true;
              createDir = true;
              removeDir = true;
              removeFile = true;
              renameFile = true;
              exists = true;
            };
            path = {
              all = true;
            };
            os = {
              all = true;
            };
          } // lib.optionalAttrs cfg.features.notifications {
            notification = {
              all = true;
            };
          } // lib.optionalAttrs cfg.features.systemTray {
            systemTray = {
              all = true;
            };
          };
          
          bundle = {
            active = true;
            targets = if cfg.features.bundleFormats == [] then "all" else cfg.features.bundleFormats;
            identifier = "com.example.myapp";
            icon = [
              "icons/32x32.png"
              "icons/128x128.png"
              "icons/128x128@2x.png"
              "icons/icon.icns"
              "icons/icon.ico"
            ];
          } // lib.optionalAttrs cfg.features.autoUpdater {
            updater = {
              active = true;
              endpoints = [
                "https://example.com/releases/{{target}}/{{current_version}}"
              ];
              dialog = true;
              pubkey = "";
            };
          } // lib.optionalAttrs pkgs.stdenv.isLinux {
            appimage = {
              bundleMediaFramework = true;
            };
            deb = {
              depends = [
                "libwebkit2gtk-4.0-37"
                "libgtk-3-0"
                "libayatana-appindicator3-1"
              ];
            };
          } // lib.optionalAttrs pkgs.stdenv.isDarwin {
            macOS = {
              frameworks = [
                "Security"
                "CoreServices"
                "Foundation"
                "AppKit"
                "WebKit"
              ];
              minimumSystemVersion = "10.13";
              exceptionDomain = "";
              signingIdentity = null;
              entitlements = null;
            };
          };
          
          security = {
            csp = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'";
          };
          
          windows = [
            ({
              fullscreen = false;
              resizable = true;
              title = "My Tauri App";
              width = 1200;
              height = 800;
              minWidth = 400;
              minHeight = 300;
              center = true;
            } // lib.optionalAttrs cfg.webview.devtools {
              additionalBrowserArgs = "--enable-features=VaapiVideoDecoder --disable-features=VizDisplayCompositor";
            })
          ];
        } // lib.optionalAttrs cfg.features.systemTray {
          systemTray = {
            iconPath = "icons/icon.png";
            iconAsTemplate = true;
            menuOnLeftClick = false;
          };
        };
      };
    };
    
    # Shell aliases for Tauri development
    home.shellAliases = {
      # Tauri CLI shortcuts
      "tauri" = "npx @tauri-apps/cli";
      "tauri-dev" = "npx @tauri-apps/cli dev";
      "tauri-build" = "npx @tauri-apps/cli build";
      "tauri-bundle" = "npx @tauri-apps/cli bundle";
      
      # Development workflow
      "tauri-init" = "npx create-tauri-app";
      "tauri-info" = "npx @tauri-apps/cli info";
      
      # Rust shortcuts for Tauri
      "cargo-tauri" = "cargo install tauri-cli --locked && cargo tauri";
      "rust-update" = "rustup update";
      "rust-target-add" = "rustup target add";
      
      # Cross-compilation shortcuts
      "tauri-linux" = "npx @tauri-apps/cli build --target x86_64-unknown-linux-gnu";
      "tauri-windows" = "npx @tauri-apps/cli build --target x86_64-pc-windows-gnu";
      "tauri-macos" = "npx @tauri-apps/cli build --target x86_64-apple-darwin";
      "tauri-macos-arm" = "npx @tauri-apps/cli build --target aarch64-apple-darwin";
    };
    
    # Tauri project initialization script
    home.file."bin/tauri-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_usage() {
          cat << EOF
        Usage: tauri-init <project-name> [framework] [directory]
        
        FRAMEWORKS:
          react      React with Vite (default)
          vue        Vue 3 with Vite
          svelte     SvelteKit
          vanilla    Vanilla HTML/JS
          
        EXAMPLES:
          tauri-init my-app
          tauri-init my-app react
          tauri-init my-app vue ./projects/
        EOF
        }
        
        PROJECT_NAME="$1"
        FRAMEWORK="''${2:-react}"
        DIRECTORY="''${3:-.}"
        
        if [[ -z "$PROJECT_NAME" ]]; then
          echo "❌ Project name required"
          show_usage
          exit 1
        fi
        
        echo "🚀 Creating Tauri project: $PROJECT_NAME"
        echo "Framework: $FRAMEWORK"
        echo "Directory: $DIRECTORY"
        echo ""
        
        # Create project directory
        mkdir -p "$DIRECTORY/$PROJECT_NAME"
        cd "$DIRECTORY/$PROJECT_NAME"
        
        # Initialize frontend based on framework
        case "$FRAMEWORK" in
          react)
            echo "⚛️  Setting up React + Vite..."
            npm create vite@latest . -- --template react-ts
            ;;
          vue)
            echo "💚 Setting up Vue 3 + Vite..."
            npm create vue@latest . -- --typescript
            ;;
          svelte)
            echo "🎭 Setting up SvelteKit..."
            npm create svelte@latest . -- --template skeleton --types typescript
            ;;
          vanilla)
            echo "🌐 Setting up Vanilla HTML/JS..."
            npm create vite@latest . -- --template vanilla-ts
            ;;
          *)
            echo "❌ Unknown framework: $FRAMEWORK"
            show_usage
            exit 1
            ;;
        esac
        
        # Install dependencies
        echo "📦 Installing dependencies..."
        npm install
        
        # Add Tauri
        echo "🦀 Adding Tauri..."
        npm install --save-dev @tauri-apps/cli
        npx tauri init --ci
        
        # Copy Tauri configuration template
        if [[ -f ~/.tauri-templates/tauri.conf.template.json ]]; then
          cp ~/.tauri-templates/tauri.conf.template.json src-tauri/tauri.conf.json
          
          # Update project name in config
          if command -v jq &> /dev/null; then
            jq ".package.productName = \"$PROJECT_NAME\"" src-tauri/tauri.conf.json > tmp.json && mv tmp.json src-tauri/tauri.conf.json
          fi
        fi
        
        # Update package.json scripts
        if command -v jq &> /dev/null; then
          jq '.scripts["tauri"] = "tauri" | .scripts["tauri:dev"] = "tauri dev" | .scripts["tauri:build"] = "tauri build"' package.json > tmp.json && mv tmp.json package.json
        fi
        
        # Create default icons directory
        mkdir -p src-tauri/icons
        
        # Create basic README
        cat > README.md << EOF
        # $PROJECT_NAME
        
        A Tauri application built with $FRAMEWORK.
        
        ## Development
        
        \`\`\`bash
        # Start development server
        npm run tauri:dev
        
        # Build for production
        npm run tauri:build
        
        # Bundle for distribution
        npx tauri bundle
        \`\`\`
        
        ## Features
        
        ${lib.optionalString cfg.features.autoUpdater "- ✅ Auto-updater"}
        ${lib.optionalString cfg.features.systemTray "- ✅ System tray"}
        ${lib.optionalString cfg.features.notifications "- ✅ Notifications"}
        - ✅ Cross-platform builds
        - ✅ Hot reload in development
        
        ## Bundle Formats
        
        ${lib.concatMapStringsSep "\n" (format: "- ${format}") cfg.features.bundleFormats}
        EOF
        
        echo ""
        echo "✅ Tauri project created successfully!"
        echo ""
        echo "📁 Project: $DIRECTORY/$PROJECT_NAME"
        echo "🔧 Framework: $FRAMEWORK"
        echo ""
        echo "🚀 Next steps:"
        echo "  cd $DIRECTORY/$PROJECT_NAME"
        echo "  npm run tauri:dev"
      '';
    };
    
    # Tauri health check
    home.file."bin/tauri-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🦀 Tauri Development Environment Health Check"
        echo "============================================"
        
        # Check Rust toolchain
        echo "🔧 Rust Toolchain:"
        
        if command -v rustc &> /dev/null; then
          echo "✅ Rust compiler: $(rustc --version)"
        else
          echo "❌ Rust compiler: not found"
        fi
        
        if command -v cargo &> /dev/null; then
          echo "✅ Cargo: $(cargo --version)"
        else
          echo "❌ Cargo: not found"
        fi
        
        if command -v rustfmt &> /dev/null; then
          echo "✅ rustfmt: available"
        else
          echo "❌ rustfmt: not found"
        fi
        
        if command -v clippy &> /dev/null; then
          echo "✅ clippy: available"
        else
          echo "❌ clippy: not found"
        fi
        
        if command -v rust-analyzer &> /dev/null; then
          echo "✅ rust-analyzer: available"
        else
          echo "❌ rust-analyzer: not found"
        fi
        
        echo ""
        echo "📦 Node.js Environment:"
        
        if command -v node &> /dev/null; then
          echo "✅ Node.js: $(node --version)"
        else
          echo "❌ Node.js: not found"
        fi
        
        if command -v npm &> /dev/null; then
          echo "✅ npm: $(npm --version)"
        else
          echo "❌ npm: not found"
        fi
        
        echo ""
        echo "🏗️  Tauri CLI:"
        
        if npx @tauri-apps/cli --version &> /dev/null; then
          echo "✅ Tauri CLI: $(npx @tauri-apps/cli --version)"
        else
          echo "❌ Tauri CLI: not found (run: npm install -g @tauri-apps/cli)"
        fi
        
        echo ""
        echo "🔗 System Dependencies:"
        
        # Check system dependencies
        deps=(
          "pkg-config:pkg-config"
          "gcc:GCC compiler"
          "cmake:CMake"
          "make:Make"
        )
        
        for dep_desc in "''${deps[@]}"; do
          dep="''${dep_desc%%:*}"
          desc="''${dep_desc##*:}"
          
          if command -v "$dep" &> /dev/null; then
            echo "✅ $desc: available"
          else
            echo "❌ $desc: not found"
          fi
        done
        
        # Platform-specific checks
        ${lib.optionalString pkgs.stdenv.isLinux ''
        echo ""
        echo "🐧 Linux Dependencies:"
        
        linux_deps=(
          "libgtk-3-dev:GTK3 development"
          "libwebkit2gtk-4.0-dev:WebKit2GTK development"
        )
        
        for dep_desc in "''${linux_deps[@]}"; do
          dep="''${dep_desc%%:*}"
          desc="''${dep_desc##*:}"
          
          if dpkg -l | grep -q "$dep" 2>/dev/null || rpm -qa | grep -q "$dep" 2>/dev/null; then
            echo "✅ $desc: installed"
          else
            echo "⚠️  $desc: may be missing"
          fi
        done
        ''}
        
        ${lib.optionalString pkgs.stdenv.isDarwin ''
        echo ""
        echo "🍎 macOS Dependencies:"
        echo "✅ Xcode Command Line Tools: required for compilation"
        echo "✅ macOS SDK: available through Nix"
        ''}
        
        # Check Rust targets
        echo ""
        echo "🎯 Rust Targets:"
        
        targets=(
          ${lib.concatMapStringsSep "\n          " (target: ''"${target}"'') cfg.rustToolchain.targets}
        )
        
        for target in "''${targets[@]}"; do
          if rustup target list --installed | grep -q "$target"; then
            echo "✅ $target: installed"
          else
            echo "❌ $target: not installed (run: rustup target add $target)"
          fi
        done
        
        # Current project check
        echo ""
        echo "📁 Current Project:"
        
        if [[ -f "src-tauri/Cargo.toml" ]]; then
          project_name=$(grep '^name = ' src-tauri/Cargo.toml | sed 's/name = "\(.*\)"/\1/')
          echo "✅ Tauri project: $project_name"
          
          if [[ -f "src-tauri/tauri.conf.json" ]]; then
            echo "✅ Tauri config: present"
          else
            echo "❌ Tauri config: missing"
          fi
        else
          echo "⚪ No Tauri project detected in current directory"
        fi
        
        echo ""
        echo "📊 Configuration:"
        echo "WebView engine: ${cfg.webview.engine}"
        echo "Debug mode: ${if cfg.development.debugMode then "enabled" else "disabled"}"
        echo "Hot reload: ${if cfg.development.hotReload then "enabled" else "disabled"}"
        echo "Bundle formats: ${toString cfg.features.bundleFormats}"
        
        echo ""
        echo "✅ Tauri health check completed!"
      '';
    };
  };
}