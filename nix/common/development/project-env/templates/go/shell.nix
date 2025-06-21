{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    go
    gopls
    golangci-lint
    gotools
  ];
  
  shellHook = ''
    echo "🐹 Go development environment ready!"
    echo "Go: $(go version)"
    echo ""
    echo "Available tools: gopls, golangci-lint, gotools"
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
  '';
}
