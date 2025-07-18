# Advanced Crane Rust Optimization
# Complete crane integration with performance optimization and build caching

{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.dotfiles.development.crane-optimization;
  
  # Initialize crane library with optimizations
  craneLib = inputs.crane.lib.${pkgs.system}.overrideToolchain (
    pkgs.rust-bin.stable.latest.default.override {
      extensions = [ "rust-src" "rust-analyzer" "llvm-tools-preview" ];
      targets = [ "wasm32-unknown-unknown" ];
    }
  );
  
  # Common Rust build optimizations
  commonArgs = {
    # Enable all optimizations
    CARGO_PROFILE_RELEASE_LTO = "fat";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
    CARGO_PROFILE_RELEASE_PANIC = "abort";
    
    # Build optimizations
    CARGO_NET_GIT_FETCH_WITH_CLI = "true";
    CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse";
    
    # Cache optimizations
    CARGO_HOME = "./cargo-home";
    SCCACHE_DIR = "./sccache";
  };
in
{
  options.dotfiles.development.crane-optimization = {
    enable = mkEnableOption "Advanced crane Rust optimization";
    
    features = {
      buildOptimization = mkOption {
        type = types.bool;
        default = true;
        description = "Enable advanced build optimizations";
      };
      
      cacheStrategy = mkOption {
        type = types.enum [ "local" "distributed" "hybrid" ];
        default = "hybrid";
        description = "Build caching strategy";
      };
      
      crossCompilation = mkOption {
        type = types.bool;
        default = true;
        description = "Enable cross-compilation support";
      };
      
      wasmSupport = mkOption {
        type = types.bool;
        default = true;
        description = "Enable WebAssembly compilation support";
      };
      
      benchmarking = mkOption {
        type = types.bool;
        default = true;
        description = "Enable build time benchmarking";
      };
    };
    
    targets = mkOption {
      type = types.listOf types.str;
      default = [ "x86_64-unknown-linux-gnu" "aarch64-unknown-linux-gnu" "wasm32-unknown-unknown" ];
      description = "Additional compilation targets";
    };
    
    optimizationLevel = mkOption {
      type = types.enum [ "debug" "release" "release-with-debug" ];
      default = "release";
      description = "Default optimization level";
    };
  };

  config = mkIf cfg.enable {
    # Enhanced Rust development packages
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core Rust toolchain with crane
      (rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" "llvm-tools-preview" "rustfmt" "clippy" ];
        targets = cfg.targets;
      })
      
      # Build tools
      cargo-edit
      cargo-watch
      cargo-audit
      cargo-deny
      cargo-outdated
      cargo-tree
      cargo-expand
      cargo-bloat
      
      # Performance tools
      cargo-criterion
      cargo-bench
      flamegraph
      
      # Cross-compilation support
      cross
      
    ] ++ optionals cfg.features.wasmSupport [
      # WebAssembly tools
      wasm-pack
      wasmtime
      
    ] ++ optionals (cfg.features.cacheStrategy != "local") [
      # Distributed caching
      sccache
    ];

    # Advanced crane configuration
    home-manager.users.yuki.home.file."nix/crane-config.nix" = {
      text = ''
        # Advanced Crane Configuration
        { inputs, pkgs, lib, ... }:

        let
          # Enhanced crane library with optimizations
          craneLib = inputs.crane.lib.''${pkgs.system}.overrideToolchain (
            pkgs.rust-bin.stable.latest.default.override {
              extensions = [ "rust-src" "rust-analyzer" "llvm-tools-preview" ];
              targets = ${builtins.toJSON cfg.targets};
            }
          );
          
          # Build optimization arguments
          commonArgs = {
            # Compiler optimizations
            CARGO_PROFILE_RELEASE_LTO = "${if cfg.optimizationLevel == "release" then "fat" else "thin"}";
            CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "${if cfg.optimizationLevel == "release" then "1" else "16"}";
            CARGO_PROFILE_RELEASE_PANIC = "abort";
            CARGO_PROFILE_RELEASE_OPT_LEVEL = "${if cfg.optimizationLevel == "release" then "3" else "2"}";
            
            # Build system optimizations
            CARGO_NET_GIT_FETCH_WITH_CLI = "true";
            CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse";
            CARGO_HTTP_MULTIPLEXING = "true";
            
            # Incremental compilation
            CARGO_INCREMENTAL = "${if cfg.optimizationLevel == "debug" then "1" else "0"}";
            
            # Cache configuration
            ${if cfg.features.cacheStrategy != "local" then ''
            RUSTC_WRAPPER = "''${pkgs.sccache}/bin/sccache";
            SCCACHE_DIR = "./sccache";
            '' else ""}
            
            # Target directory optimization
            CARGO_TARGET_DIR = "./target";
            
            # Cross-compilation setup
            ${if cfg.features.crossCompilation then ''
            CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "''${pkgs.gcc}/bin/gcc";
            CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "''${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-gnu-gcc";
            '' else ""}
          };
        in {
          inherit craneLib commonArgs;
          
          # Optimized build function
          buildRustPackage = src: overrides: craneLib.buildPackage (commonArgs // {
            inherit src;
            
            # Dependency caching for faster builds
            cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
              inherit src;
            });
            
            # Build flags optimization
            cargoExtraArgs = "--release ${if cfg.features.buildOptimization then "--target-cpu=native" else ""}";
            
            # macOS specific optimizations
            buildInputs = with pkgs; lib.optionals stdenv.isDarwin [
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.CoreFoundation
              darwin.apple_sdk.frameworks.SystemConfiguration
              libiconv
            ];
            
            # Additional environment variables
            env = commonArgs;
          } // overrides);
          
          # WebAssembly build function
          ${if cfg.features.wasmSupport then ''
          buildWasmPackage = src: overrides: craneLib.buildPackage (commonArgs // {
            inherit src;
            
            cargoExtraArgs = "--target wasm32-unknown-unknown --no-default-features";
            
            buildInputs = with pkgs; [
              wasm-pack
              binaryen
            ];
            
            # WASM optimization
            postBuild = \'\'
              wasm-opt -Oz -o optimized.wasm target/wasm32-unknown-unknown/release/*.wasm
            \'\';
          } // overrides);
          '' else ""}
          
          # Cross-compilation build function
          ${if cfg.features.crossCompilation then ''
          buildCrossPackage = src: target: overrides: craneLib.buildPackage (commonArgs // {
            inherit src;
            
            cargoExtraArgs = "--target ''${target} --release";
            
            # Target-specific configuration
            env = commonArgs // {
              "CARGO_TARGET_''${lib.toUpper (lib.replaceStrings ["-"] ["_"] target)}_LINKER" = 
                if target == "aarch64-unknown-linux-gnu" then
                  "''${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-gnu-gcc"
                else
                  "''${pkgs.gcc}/bin/gcc";
            };
          } // overrides);
          '' else ""}
        }
      '';
    };

    # Optimized Rust project templates
    home-manager.users.yuki.home.file."bin/crane-create" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        PROJECT_NAME="''${1:-}"
        PROJECT_TYPE="''${2:-binary}"
        
        if [[ -z "$PROJECT_NAME" ]]; then
          echo "Usage: crane-create <project_name> [binary|library|workspace|wasm]"
          exit 1
        fi
        
        echo "🦀 Creating optimized Rust project: $PROJECT_NAME"
        echo "Project type: $PROJECT_TYPE"
        
        mkdir -p "$PROJECT_NAME"
        cd "$PROJECT_NAME"
        
        case "$PROJECT_TYPE" in
          binary)
            create_binary_project
            ;;
          library)
            create_library_project
            ;;
          workspace)
            create_workspace_project
            ;;
          wasm)
            create_wasm_project
            ;;
          *)
            echo "❌ Unknown project type: $PROJECT_TYPE"
            exit 1
            ;;
        esac
        
        # Common setup
        setup_common_files
        setup_nix_integration
        
        echo "✅ Project created successfully!"
        echo ""
        echo "Next steps:"
        echo "  cd $PROJECT_NAME"
        echo "  direnv allow"
        echo "  cargo build"
      '';
    };

    # Project creation functions
    home-manager.users.yuki.home.file."bin/crane-create-helpers" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Helper functions for crane-create
        
        create_binary_project() {
          cargo init --name "$PROJECT_NAME" --bin .
          
          # Optimized Cargo.toml
          cat >> Cargo.toml << 'EOF'

        [profile.release]
        lto = "fat"
        codegen-units = 1
        panic = "abort"
        strip = true

        [profile.dev]
        incremental = true
        debug = true

        [profile.bench]
        inherits = "release"
        debug = true
        EOF
        }
        
        create_library_project() {
          cargo init --name "$PROJECT_NAME" --lib .
          
          # Library-specific optimizations
          cat >> Cargo.toml << 'EOF'

        [lib]
        crate-type = ["cdylib", "rlib"]

        [profile.release]
        lto = "fat"
        codegen-units = 1
        panic = "abort"
        strip = true

        [profile.dev]
        incremental = true
        
        [dependencies]
        # Add common library dependencies here
        EOF
        }
        
        create_workspace_project() {
          # Create workspace Cargo.toml
          cat > Cargo.toml << EOF
        [workspace]
        members = [
            "crates/*",
        ]
        
        [workspace.dependencies]
        # Shared dependencies
        
        [profile.release]
        lto = "fat"
        codegen-units = 1
        panic = "abort"
        strip = true
        
        [profile.dev]
        incremental = true
        EOF
          
          # Create initial crate
          mkdir -p crates/$PROJECT_NAME
          cd crates/$PROJECT_NAME
          cargo init --name "$PROJECT_NAME" --lib .
          cd ../..
        }
        
        ${if cfg.features.wasmSupport then ''
        create_wasm_project() {
          cargo init --name "$PROJECT_NAME" --lib .
          
          # WASM-specific configuration
          cat >> Cargo.toml << 'EOF'

        [lib]
        crate-type = ["cdylib"]

        [dependencies]
        wasm-bindgen = "0.2"
        js-sys = "0.3"
        web-sys = "0.3"

        [dependencies.web-sys]
        version = "0.3"
        features = [
          "console",
          "Document",
          "Element",
          "HtmlElement",
          "Window",
        ]

        [profile.release]
        lto = true
        opt-level = "s"  # Optimize for size
        
        [profile.dev]
        debug = true
        EOF
          
          # WASM setup script
          cat > build-wasm.sh << 'EOF'
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🕸️  Building WebAssembly package..."
        
        # Build with wasm-pack
        wasm-pack build --target web --out-dir pkg
        
        # Optimize with wasm-opt
        wasm-opt -Oz -o pkg/optimized.wasm pkg/*.wasm
        
        echo "✅ WASM build completed!"
        echo "Package available in ./pkg/"
        EOF
          
          chmod +x build-wasm.sh
        }
        '' else ""}
        
        setup_common_files() {
          # .gitignore
          cat > .gitignore << 'EOF'
        /target/
        /Cargo.lock
        **/*.rs.bk
        *.pdb
        .env
        .DS_Store
        /sccache/
        /cargo-home/
        EOF
          
          # Rust toolchain
          cat > rust-toolchain.toml << 'EOF'
        [toolchain]
        channel = "stable"
        components = ["rustfmt", "clippy", "rust-src", "rust-analyzer"]
        targets = ["wasm32-unknown-unknown"]
        EOF
          
          # Clippy configuration
          cat > .clippy.toml << 'EOF'
        # Clippy configuration for enhanced linting
        avoid-breaking-exported-api = false
        cognitive-complexity-threshold = 30
        EOF
          
          # Rustfmt configuration
          cat > rustfmt.toml << 'EOF'
        # Rustfmt configuration
        edition = "2021"
        max_width = 100
        hard_tabs = false
        tab_spaces = 4
        newline_style = "Unix"
        use_small_heuristics = "Default"
        EOF
        }
        
        setup_nix_integration() {
          # Flake for crane integration
          cat > flake.nix << 'EOF'
        {
          description = "Rust project with crane optimization";
          
          inputs = {
            nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
            crane.url = "github:ipetkov/crane";
            rust-overlay.url = "github:oxalica/rust-overlay";
            flake-utils.url = "github:numtide/flake-utils";
          };
          
          outputs = { self, nixpkgs, crane, rust-overlay, flake-utils }:
            flake-utils.lib.eachDefaultSystem (system:
              let
                pkgs = import nixpkgs {
                  inherit system;
                  overlays = [ (import rust-overlay) ];
                };
                
                craneLib = crane.lib.''${system}.overrideToolchain (
                  pkgs.rust-bin.stable.latest.default.override {
                    extensions = [ "rust-src" "rust-analyzer" ];
                  }
                );
                
                # Build the project
                my-crate = craneLib.buildPackage {
                  src = craneLib.cleanCargoSource (craneLib.path ./.);
                  
                  buildInputs = with pkgs; lib.optionals stdenv.isDarwin [
                    darwin.apple_sdk.frameworks.Security
                    darwin.apple_sdk.frameworks.CoreFoundation
                    darwin.apple_sdk.frameworks.SystemConfiguration
                  ];
                };
              in {
                checks = { inherit my-crate; };
                packages.default = my-crate;
                
                devShells.default = craneLib.devShell {
                  checks = self.checks.''${system};
                  
                  packages = with pkgs; [
                    rust-analyzer
                    cargo-edit
                    cargo-watch
                    cargo-audit
                    cargo-criterion
                    flamegraph
                  ];
                  
                  shellHook = ''
                    echo "🦀 Rust development environment with crane optimization"
                    echo "Available commands:"
                    echo "  cargo build --release  # Optimized build"
                    echo "  cargo watch -x check   # Continuous checking"
                    echo "  cargo audit            # Security audit"
                    echo "  cargo criterion        # Benchmarking"
                  '';
                };
              });
        }
        EOF
          
          # .envrc for direnv
          echo "use flake" > .envrc
        }
      '';
    };

    # Build optimization scripts
    home-manager.users.yuki.home.file."bin/crane-build" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        BUILD_TYPE="''${1:-release}"
        TARGET="''${2:-}"
        FEATURES="''${3:-}"
        
        echo "🏗️  Building Rust project with crane optimizations..."
        echo "Build type: $BUILD_TYPE"
        ${if cfg.features.crossCompilation then ''
        echo "Target: ''${TARGET:-native}"
        '' else ""}
        echo "Features: ''${FEATURES:-default}"
        
        # Build arguments
        ARGS=""
        
        case "$BUILD_TYPE" in
          debug)
            ARGS="--profile dev"
            ;;
          release)
            ARGS="--release"
            ;;
          release-with-debug)
            ARGS="--release"
            export CARGO_PROFILE_RELEASE_DEBUG=true
            ;;
          *)
            echo "❌ Unknown build type: $BUILD_TYPE"
            exit 1
            ;;
        esac
        
        ${if cfg.features.crossCompilation then ''
        if [[ -n "$TARGET" ]]; then
          ARGS="$ARGS --target $TARGET"
        fi
        '' else ""}
        
        if [[ -n "$FEATURES" ]]; then
          ARGS="$ARGS --features $FEATURES"
        fi
        
        # Performance monitoring
        ${if cfg.features.benchmarking then ''
        START_TIME=$(date +%s)
        '' else ""}
        
        # Execute build
        echo "🔨 Running: cargo build $ARGS"
        cargo build $ARGS
        
        ${if cfg.features.benchmarking then ''
        END_TIME=$(date +%s)
        BUILD_TIME=$((END_TIME - START_TIME))
        echo "✅ Build completed in ''${BUILD_TIME}s"
        
        # Log build time for analysis
        echo "$(date -Iseconds),$BUILD_TYPE,$TARGET,$FEATURES,''${BUILD_TIME}s" >> .build-times.log
        '' else ""}
        
        echo "✅ Build completed successfully!"
      '';
    };

    # Performance benchmarking
    home-manager.users.yuki.home.file."bin/crane-benchmark" = mkIf cfg.features.benchmarking {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "📊 Crane Build Performance Benchmark"
        echo "===================================="
        
        PROJECT_DIR="''${1:-.}"
        ITERATIONS="''${2:-3}"
        
        cd "$PROJECT_DIR"
        
        if [[ ! -f "Cargo.toml" ]]; then
          echo "❌ No Cargo.toml found in current directory"
          exit 1
        fi
        
        echo "🧹 Cleaning previous builds..."
        cargo clean
        
        echo "🔄 Running benchmark ($ITERATIONS iterations)..."
        
        # Cold build (dependencies)
        echo ""
        echo "❄️  Cold build (with dependencies):"
        START=$(date +%s%N)
        cargo build --release
        END=$(date +%s%N)
        COLD_TIME=$(( (END - START) / 1000000 ))
        echo "Cold build time: ''${COLD_TIME}ms"
        
        # Incremental builds
        echo ""
        echo "🔥 Incremental builds:"
        TOTAL_TIME=0
        
        for i in $(seq 1 $ITERATIONS); do
          # Touch a source file to trigger rebuild
          touch src/main.rs 2>/dev/null || touch src/lib.rs 2>/dev/null || true
          
          START=$(date +%s%N)
          cargo build --release
          END=$(date +%s%N)
          TIME=$(( (END - START) / 1000000 ))
          TOTAL_TIME=$((TOTAL_TIME + TIME))
          echo "Incremental build $i: ''${TIME}ms"
        done
        
        AVERAGE_INCREMENTAL=$((TOTAL_TIME / ITERATIONS))
        
        # Dependencies-only build (crane optimization test)
        echo ""
        echo "📦 Dependencies-only build test:"
        cargo clean
        
        # Simulate crane's buildDepsOnly
        mkdir -p temp-deps
        cp Cargo.toml Cargo.lock temp-deps/ 2>/dev/null || cp Cargo.toml temp-deps/
        cd temp-deps
        echo 'fn main() {}' > main.rs
        
        START=$(date +%s%N)
        cargo build --release
        END=$(date +%s%N)
        DEPS_TIME=$(( (END - START) / 1000000 ))
        echo "Dependencies build time: ''${DEPS_TIME}ms"
        
        cd ..
        rm -rf temp-deps
        
        # Results summary
        echo ""
        echo "📊 Benchmark Results:"
        echo "===================="
        echo "Cold build (full): ''${COLD_TIME}ms"
        echo "Dependencies only: ''${DEPS_TIME}ms"
        echo "Average incremental: ''${AVERAGE_INCREMENTAL}ms"
        echo ""
        echo "💡 Performance insights:"
        echo "  Dependencies overhead: $((DEPS_TIME * 100 / COLD_TIME))% of total build time"
        echo "  Incremental efficiency: $((AVERAGE_INCREMENTAL * 100 / COLD_TIME))% of cold build"
        echo "  Crane optimization potential: $((DEPS_TIME))ms savings per rebuild"
        
        # Save results
        {
          echo "# Crane Build Benchmark Results - $(date)"
          echo "Project: $(basename $(pwd))"
          echo "Cold build: ''${COLD_TIME}ms"
          echo "Dependencies: ''${DEPS_TIME}ms" 
          echo "Incremental average: ''${AVERAGE_INCREMENTAL}ms"
          echo "Optimization potential: $((DEPS_TIME))ms"
        } >> .crane-benchmark.log
        
        echo ""
        echo "✅ Benchmark completed! Results saved to .crane-benchmark.log"
      '';
    };

    # Shell aliases for crane operations
    home-manager.users.yuki.programs.zsh.shellAliases = {
      "crane-new" = "crane-create";
      "crane-build-opt" = "crane-build release";
      "crane-build-debug" = "crane-build debug";
      "crane-bench" = "crane-benchmark";
      "rust-opt" = "crane-build release";
    } // optionalAttrs cfg.features.wasmSupport {
      "crane-wasm" = "crane-create";
      "build-wasm" = "./build-wasm.sh";
    };

    # Environment variables for optimal builds
    home-manager.users.yuki.home.sessionVariables = mkMerge [
      (mkIf cfg.features.buildOptimization {
        # Compiler optimizations
        CARGO_PROFILE_RELEASE_LTO = "fat";
        CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
        CARGO_PROFILE_RELEASE_PANIC = "abort";
        
        # Build system optimizations
        CARGO_NET_GIT_FETCH_WITH_CLI = "true";
        CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse";
        CARGO_HTTP_MULTIPLEXING = "true";
      })
      (mkIf (cfg.features.cacheStrategy != "local") {
        # Distributed caching
        RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
        SCCACHE_CACHE_SIZE = "10G";
      })
      {
        # General optimizations
        CARGO_INCREMENTAL = mkDefault "1";
        RUST_BACKTRACE = mkDefault "1";
      }
    ];

    # Health check for crane optimization
    home-manager.users.yuki.home.file."bin/crane-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🦀 Crane Rust Optimization Health Check"
        echo "======================================="
        
        # Check Rust toolchain
        if command -v rustc &>/dev/null; then
          echo "✅ Rust: $(rustc --version)"
        else
          echo "❌ Rust: Not installed"
          exit 1
        fi
        
        # Check Cargo
        if command -v cargo &>/dev/null; then
          echo "✅ Cargo: $(cargo --version)"
        else
          echo "❌ Cargo: Not installed"
          exit 1
        fi
        
        # Check crane availability (in nix environment)
        if nix eval --expr 'let pkgs = import <nixpkgs> {}; in pkgs.lib.hasAttr "crane" (import <crane>)' 2>/dev/null; then
          echo "✅ Crane: Available in Nix"
        else
          echo "⚠️  Crane: Not available (normal outside nix shell)"
        fi
        
        # Check optimization tools
        echo ""
        echo "🛠️  Optimization Tools:"
        command -v cargo-edit &>/dev/null && echo "  ✅ cargo-edit" || echo "  ❌ cargo-edit"
        command -v cargo-watch &>/dev/null && echo "  ✅ cargo-watch" || echo "  ❌ cargo-watch"
        command -v cargo-audit &>/dev/null && echo "  ✅ cargo-audit" || echo "  ❌ cargo-audit"
        command -v cargo-criterion &>/dev/null && echo "  ✅ cargo-criterion" || echo "  ❌ cargo-criterion"
        ${if cfg.features.cacheStrategy != "local" then ''
        command -v sccache &>/dev/null && echo "  ✅ sccache" || echo "  ❌ sccache"
        '' else ""}
        ${if cfg.features.wasmSupport then ''
        command -v wasm-pack &>/dev/null && echo "  ✅ wasm-pack" || echo "  ❌ wasm-pack"
        '' else ""}
        
        # Check current project
        echo ""
        echo "📦 Current Project:"
        if [[ -f "Cargo.toml" ]]; then
          echo "  ✅ Cargo.toml found"
          if [[ -f "flake.nix" ]]; then
            echo "  ✅ Nix flake integration"
          else
            echo "  ⚠️  No Nix flake (consider adding for crane optimization)"
          fi
        else
          echo "  ❌ No Cargo.toml in current directory"
        fi
        
        # Performance settings check
        echo ""
        echo "⚙️  Optimization Settings:"
        echo "  Build optimization: ${if cfg.features.buildOptimization then "✅ Enabled" else "❌ Disabled"}"
        echo "  Cache strategy: ${cfg.features.cacheStrategy}"
        echo "  Cross-compilation: ${if cfg.features.crossCompilation then "✅ Enabled" else "❌ Disabled"}"
        echo "  WASM support: ${if cfg.features.wasmSupport then "✅ Enabled" else "❌ Disabled"}"
        
        echo ""
        echo "📋 Available commands:"
        echo "  crane-create <name> <type>  - Create optimized Rust project"
        echo "  crane-build <type>          - Build with optimizations"
        echo "  crane-benchmark            - Performance benchmark"
        ${if cfg.features.wasmSupport then ''
        echo "  build-wasm                 - Build WebAssembly package"
        '' else ""}
        
        echo ""
        echo "✅ Crane optimization health check completed!"
      '';
    };
  };
}