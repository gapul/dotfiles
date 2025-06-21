{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    ruby
    bundler
  ];
  
  shellHook = ''
    echo "💎 Ruby development environment ready!"
    echo "Ruby: $(ruby --version)"
    echo "Bundler: $(bundler --version)"
    echo ""
    export GEM_HOME="$PWD/.gems"
    export GEM_PATH="$GEM_HOME"
    export PATH="$GEM_HOME/bin:$PATH"
  '';
}
