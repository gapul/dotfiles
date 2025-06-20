{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Complete Python environment with essential packages
    (python3.withPackages (ps: with ps; [
      # Core development tools
      pip setuptools wheel
      virtualenv poetry pipx
      
      # Code quality and testing
      black flake8 mypy pytest isort pylint
      autopep8 bandit safety
      
      # Common development libraries
      requests urllib3 certifi
      beautifulsoup4 lxml
      pyyaml toml configparser
      click typer rich
      python-dotenv
      
      # Data science essentials
      pandas numpy scipy
      matplotlib seaborn plotly
      jupyter notebook ipython
      
      # Development utilities
      python-lsp-server debugpy
      pre-commit tox
    ]))
    
    # Additional development tools
    git
    just
  ];
  
  shellHook = ''
    echo "🐍 Complete Python development environment ready!"
    echo "Python: $(python --version)"
    echo "Available packages:"
    echo "  📦 Core: pip, poetry, virtualenv, pipx"
    echo "  🔍 Quality: black, flake8, mypy, pytest, pylint"
    echo "  📚 Libraries: requests, pandas, numpy, jupyter"
    echo "  🛠️  Tools: pre-commit, tox, python-lsp-server"
    echo ""
    echo "💡 Usage:"
    echo "  poetry init        # Initialize new project"
    echo "  python -m pip list # List installed packages"
    echo "  jupyter notebook   # Start Jupyter"
    echo "  pytest            # Run tests"
    echo ""
    echo "✅ All packages managed declaratively by Nix!"
  '';
}