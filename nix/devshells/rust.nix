# Rust development shell with crane support for optimized builds
{ lib, pkgs, inputs, ... }:

let
  # Initialize crane library with rust-overlay toolchain
  craneLib = inputs.crane.lib.${pkgs.system}.overrideToolchain (
    pkgs.rust-bin.stable.latest.default.override {
      extensions = [ "rust-src" "rust-analyzer" ];
    }
  );
  
  # Common Rust packages for development
  rustPackages = with pkgs; [
    rust-bin.stable.latest.default
    rust-analyzer
    rustfmt
    clippy
    cargo-watch
    cargo-edit
    cargo-audit
    cargo-deny
    bacon  # Background rust code checker
  ];
  
  # Helper function to create crane-optimized build for a Rust project
  mkCraneProject = src: craneLib.buildPackage {
    inherit src;
    
    # Build dependencies separately for better caching
    cargoArtifacts = craneLib.buildDepsOnly {
      inherit src;
    };
    
    # Additional build flags for optimization
    cargoExtraArgs = "--release";
    
    # Include common build inputs
    buildInputs = with pkgs; lib.optionals pkgs.stdenv.isDarwin [
      darwin.apple_sdk.frameworks.Security
      darwin.apple_sdk.frameworks.CoreFoundation
      darwin.apple_sdk.frameworks.SystemConfiguration
    ];
  };

in {
  default = pkgs.mkShell {
    name = "rust-dev-shell";
    
    buildInputs = rustPackages ++ (with pkgs; [
      # Build tools
      pkg-config
      openssl
      
      # macOS specific dependencies
    ] ++ lib.optionals pkgs.stdenv.isDarwin [
      darwin.apple_sdk.frameworks.Security
      darwin.apple_sdk.frameworks.CoreFoundation
      darwin.apple_sdk.frameworks.SystemConfiguration
      libiconv
    ]);
    
    # Environment variables
    RUST_BACKTRACE = 1;
    RUST_LOG = "debug";
    
    # Include crane utilities in the shell
    shellHook = ''
      echo "🦀 Rust Development Shell (with Crane optimization)"
      echo "Available tools:"
      echo "  - rust-analyzer: LSP server"
      echo "  - cargo-watch: Auto-rebuild on changes"
      echo "  - cargo-edit: Add/remove dependencies"
      echo "  - cargo-audit: Security audit"
      echo "  - bacon: Background code checker"
      echo ""
      echo "Crane utilities available for optimized builds"
      echo "See nix/devshells/rust.nix for mkCraneProject helper"
    '';
  };
  
  # Export crane utilities for use in other files
  inherit craneLib mkCraneProject;
}