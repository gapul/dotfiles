# FastAPI Python Template Configuration
{
  name = "python-fastapi";
  displayName = "Python FastAPI";
  description = "Modern Python web API with FastAPI framework";
  
  language = "python";
  framework = "fastapi";
  type = "web-api";
  
  pythonVersion = "3.11";
  
  dependencies = [
    "fastapi"
    "uvicorn[standard]"
    "pydantic"
    "python-multipart"
    "python-jose[cryptography]"
    "passlib[bcrypt]"
  ];
  
  devDependencies = [
    "pytest"
    "pytest-asyncio"
    "httpx"
    "black"
    "isort"
    "flake8"
    "mypy"
    "pre-commit"
  ];
  
  scripts = {
    dev = "uvicorn main:app --reload --host 0.0.0.0 --port 8000";
    start = "uvicorn main:app --host 0.0.0.0 --port 8000";
    test = "pytest";
    lint = "flake8 . && mypy .";
    format = "black . && isort .";
    "format:check" = "black --check . && isort --check-only .";
  };
  
  files = [
    "main.py"
    "requirements.txt"
    "requirements-dev.txt"
    "pyproject.toml"
    "pytest.ini"
    ".pre-commit-config.yaml"
    "app/__init__.py"
    "app/api/__init__.py"
    "app/api/routes.py"
    "app/core/config.py"
    "app/models/__init__.py"
    "tests/__init__.py"
    "tests/test_main.py"
  ];
  
  nixPackages = [
    "python311"
    "python311Packages.pip"
    "python311Packages.virtualenv"
  ];
}