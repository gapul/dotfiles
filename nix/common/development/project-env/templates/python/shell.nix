{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    python3
    python3Packages.pip
    python3Packages.virtualenv
    python3Packages.poetry
    python3Packages.black
    python3Packages.flake8
    python3Packages.pytest
    python3Packages.mypy
  ];
  
  shellHook = ''
    echo "🐍 Python development environment ready!"
    echo "Python: $(python --version)"
    echo "Pip: $(pip --version)"
    
    # Create virtual environment if it doesn't exist
    if [ ! -d .venv ]; then
      echo "Creating Python virtual environment..."
      python -m venv .venv
    fi
    
    echo "To activate virtual environment: source .venv/bin/activate"
  '';
}