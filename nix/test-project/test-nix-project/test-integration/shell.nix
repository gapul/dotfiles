{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    (python3.withPackages (ps: with ps; [
      # Add your project-specific packages here
      pip setuptools wheel
      poetry
      
      # Common development tools
      black flake8 mypy pytest
      requests pyyaml
      
      # Uncomment as needed:
      # pandas numpy matplotlib
      # django flask fastapi
      # pytest-cov coverage
    ]))
  ];
  
  shellHook = ''
    echo "🐍 Python project environment ready!"
    echo "Add packages to shell.nix buildInputs"
    export PYTHONPATH="$PWD:$PYTHONPATH"
  '';
}
