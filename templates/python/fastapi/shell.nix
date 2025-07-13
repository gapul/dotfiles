# FastAPI Python Development Environment
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Python runtime and package management
    python311
    python311Packages.pip
    python311Packages.virtualenv
    python311Packages.pipx
    
    # Development tools
    python311Packages.black
    python311Packages.isort
    python311Packages.flake8
    python311Packages.mypy
    python311Packages.pytest
    
    # FastAPI specific
    python311Packages.fastapi
    python311Packages.uvicorn
    python311Packages.pydantic
    
    # Additional tools
    python311Packages.httpx
    python311Packages.python-dotenv
    
    # System dependencies
    gcc
    pkg-config
    
    # Optional: Database support
    postgresql
    sqlite
  ];

  shellHook = ''
    echo "🐍 FastAPI Python Development Environment"
    echo "========================================"
    echo "🐍 Python: $(python --version)"
    echo "📦 pip: $(pip --version)"
    echo "🚀 FastAPI: Ready for development"
    echo ""
    echo "Available commands:"
    echo "  python -m venv venv     - Create virtual environment"
    echo "  source venv/bin/activate - Activate virtual environment"
    echo "  pip install -r requirements-dev.txt - Install dependencies"
    echo "  uvicorn main:app --reload - Start development server"
    echo "  pytest                  - Run tests"
    echo "  black .                 - Format code"
    echo "  mypy .                  - Type checking"
    echo ""
    echo "📚 API Documentation will be available at:"
    echo "  http://localhost:8000/docs    (Swagger UI)"
    echo "  http://localhost:8000/redoc   (ReDoc)"
    echo ""
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
      echo "🔧 Creating Python virtual environment..."
      python -m venv venv
      echo "✅ Virtual environment created!"
      echo "Run: source venv/bin/activate"
    fi
  '';

  # Environment variables
  PYTHONPATH = ".";
  PYTHONDONTWRITEBYTECODE = "1";
  PYTHONUNBUFFERED = "1";
}