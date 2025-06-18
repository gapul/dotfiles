{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    rustc
    cargo
    rustfmt
    clippy
    rust-analyzer
    pkg-config
  ];
  
  shellHook = ''
    echo "🦀 Rust development environment ready!"
    echo "Rust: $(rustc --version)"
    echo "Cargo: $(cargo --version)"
    
    # Create new Rust project if Cargo.toml doesn't exist
    if [ ! -f Cargo.toml ]; then
      echo "To create a new Rust project: cargo init"
    fi
  '';
}