# Rust CLI Development Environment
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Rust toolchain
    rustc
    cargo
    rust-analyzer
    rustfmt
    clippy
    cargo-watch
    cargo-edit
    cargo-audit
    cargo-outdated
    
    # Build dependencies
    gcc
    pkg-config
    openssl
    
    # Development tools
    lldb
    gdb
    valgrind
    
    # Documentation
    mdbook
  ];

  shellHook = ''
    echo "🦀 Rust CLI Development Environment"
    echo "==================================="
    echo "🦀 Rust: $(rustc --version)"
    echo "📦 Cargo: $(cargo --version)"
    echo "🔧 Tools: rust-analyzer, clippy, rustfmt available"
    echo ""
    echo "Available commands:"
    echo "  cargo run                    - Run the application"
    echo "  cargo run -- --help         - Show help"
    echo "  cargo test                   - Run tests"
    echo "  cargo clippy                 - Run linter"
    echo "  cargo fmt                    - Format code"
    echo "  cargo build --release       - Build optimized binary"
    echo "  cargo watch -x run          - Auto-restart on changes"
    echo "  cargo audit                  - Security audit"
    echo "  cargo outdated               - Check for updates"
    echo ""
    echo "🚀 Project structure:"
    echo "  src/main.rs                  - Main entry point"
    echo "  src/lib.rs                   - Library code"
    echo "  src/cli.rs                   - Command-line interface"
    echo "  src/config.rs                - Configuration management"
    echo "  src/error.rs                 - Error handling"
    echo "  tests/                       - Integration tests"
    echo "  benches/                     - Benchmarks"
    echo ""
  '';

  # Environment variables
  RUST_BACKTRACE = "1";
  RUST_LOG = "debug";
}