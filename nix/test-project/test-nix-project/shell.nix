{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    rustc
    cargo
    rust-analyzer
    rustfmt
    clippy
    cargo-watch
  ];
  
  shellHook = ''
    echo "🦀 Rust development environment ready!"
    echo "Rust: $(rustc --version)"
    echo "Cargo: $(cargo --version)"
    echo ""
    echo "Available tools: rust-analyzer, rustfmt, clippy, cargo-watch"
  '';
}
