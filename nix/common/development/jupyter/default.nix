{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.jupyter;
in
{
  options.jupyter = {
    enable = mkEnableOption "Jupyter core development tools";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Jupyter tooling profile";
    };
    
    editors = mkEnableOption "Editor integrations" // { default = true; };
    
    autoOptimize = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically configure optimal settings";
    };
  };
  
  imports = [
    ./editors
  ];

  config = mkIf cfg.enable {
    # Enable editor integrations
    jupyter.editors.enable = mkDefault cfg.editors;
    jupyter.editors.profile = mkDefault cfg.profile;
    
    # Core development tools only (no heavy packages)
    home-manager.users.yuki.home.packages = with pkgs; [
      # Python base (projects can extend this)
      python311
      python311Packages.pip
      python311Packages.virtualenv
      
      # Core Jupyter tools
      python311Packages.jupyter
      python311Packages.jupyterlab
      python311Packages.ipython
      python311Packages.notebook
      
      # Essential development tools
      python311Packages.black
      python311Packages.flake8
      python311Packages.pytest
    ];
    
    # Global shell aliases for Jupyter development
    home-manager.users.yuki.home.shellAliases = {
      # Project management
      "jupyter-init" = "nix run github:yuki/jupyter-templates";
      "jupyter-project" = "nix develop .#jupyter";
      
      # Quick health checks
      "jupyter-health" = "python -c \"import sys, jupyter, IPython; print(f'✅ Python {sys.version_info.major}.{sys.version_info.minor}, Jupyter {jupyter.__version__}, IPython {IPython.__version__}')\"";
      "jupyter-kernels" = "jupyter kernelspec list";
    };
    
    # Global Jupyter development scripts
    home-manager.users.yuki.home.file."bin/jupyter-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        # Jupyter project initialization script
        PROJECT_NAME="''${1:-jupyter-project}"
        TEMPLATE="''${2:-data-science}"
        
        show_usage() {
          echo "Usage: jupyter-init <project-name> [template]"
          echo ""
          echo "Templates:"
          echo "  data-science     Data science project (default)"
          echo "  machine-learning Machine learning project"
          echo "  quantum          Quantum computing project"
          echo "  research         Research project"
          echo ""
          echo "Examples:"
          echo "  jupyter-init my-analysis"
          echo "  jupyter-init ml-project machine-learning"
        }
        
        if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
          show_usage
          exit 0
        fi
        
        echo "🔬 Creating Jupyter project: $PROJECT_NAME"
        echo "📋 Template: $TEMPLATE"
        
        # Create project directory
        mkdir -p "$PROJECT_NAME"
        cd "$PROJECT_NAME"
        
        # Create basic structure
        mkdir -p {notebooks,data/{raw,processed},src,tests,docs}
        
        # Create requirements.txt based on template
        case "$TEMPLATE" in
          "data-science")
            cat > requirements.txt << 'EOF'
        # Core Data Science Packages
        numpy>=1.24.0
        pandas>=2.0.0
        matplotlib>=3.7.0
        seaborn>=0.12.0
        plotly>=5.17.0
        
        # Jupyter Environment
        jupyter>=1.0.0
        jupyterlab>=4.0.0
        ipywidgets>=8.0.0
        
        # Additional Analysis Tools
        scipy>=1.10.0
        scikit-learn>=1.3.0
        statsmodels>=0.14.0
        EOF
            ;;
          "machine-learning")
            cat > requirements.txt << 'EOF'
        # Machine Learning Core
        numpy>=1.24.0
        pandas>=2.0.0
        scikit-learn>=1.3.0
        matplotlib>=3.7.0
        seaborn>=0.12.0
        
        # Deep Learning
        torch>=2.0.0
        torchvision>=0.15.0
        tensorflow>=2.13.0
        
        # Jupyter Environment
        jupyter>=1.0.0
        jupyterlab>=4.0.0
        ipywidgets>=8.0.0
        
        # ML Utilities
        mlflow>=2.7.0
        optuna>=3.4.0
        shap>=0.42.0
        EOF
            ;;
          "quantum")
            cat > requirements.txt << 'EOF'
        # Quantum Computing
        qiskit>=1.0.0
        qiskit-aer>=0.13.0
        qiskit-ibm-runtime>=0.19.0
        
        # Scientific Computing
        numpy>=1.24.0
        scipy>=1.10.0
        matplotlib>=3.7.0
        sympy>=1.12
        
        # Jupyter Environment
        jupyter>=1.0.0
        jupyterlab>=4.0.0
        ipywidgets>=8.0.0
        EOF
            ;;
          "research")
            cat > requirements.txt << 'EOF'
        # Scientific Computing
        numpy>=1.24.0
        scipy>=1.10.0
        matplotlib>=3.7.0
        pandas>=2.0.0
        sympy>=1.12
        
        # Jupyter Environment
        jupyter>=1.0.0
        jupyterlab>=4.0.0
        ipywidgets>=8.0.0
        
        # Documentation
        sphinx>=7.1.0
        sphinx-rtd-theme>=1.3.0
        
        # Testing
        pytest>=7.4.0
        pytest-cov>=4.1.0
        EOF
            ;;
        esac
        
        # Create basic .gitignore
        cat > .gitignore << 'EOF'
        # Python
        __pycache__/
        *.py[cod]
        *$py.class
        *.so
        .Python
        env/
        venv/
        .venv/
        .env
        
        # Jupyter
        .ipynb_checkpoints/
        */.ipynb_checkpoints/*
        
        # Data
        data/raw/*
        !data/raw/.gitkeep
        data/processed/*
        !data/processed/.gitkeep
        
        # Models
        models/*.pkl
        models/*.joblib
        models/*.h5
        
        # IDE
        .vscode/
        .idea/
        *.swp
        *.swo
        
        # OS
        .DS_Store
        Thumbs.db
        EOF
        
        # Create placeholder files
        touch data/raw/.gitkeep
        touch data/processed/.gitkeep
        
        # Create sample notebook
        cat > notebooks/01-initial-exploration.ipynb << 'EOF'
        {
         "cells": [
          {
           "cell_type": "markdown",
           "metadata": {},
           "source": [
            "# Initial Data Exploration\n",
            "\n",
            "This notebook contains the initial exploration of the dataset."
           ]
          },
          {
           "cell_type": "code",
           "execution_count": null,
           "metadata": {},
           "outputs": [],
           "source": [
            "import numpy as np\n",
            "import pandas as pd\n",
            "import matplotlib.pyplot as plt\n",
            "import seaborn as sns\n",
            "\n",
            "# Set plotting style\n",
            "plt.style.use('default')\n",
            "sns.set_palette('husl')\n",
            "\n",
            "print('✅ Environment ready for analysis')"
           ]
          }
         ],
         "metadata": {
          "kernelspec": {
           "display_name": "Python 3",
           "language": "python",
           "name": "python3"
          },
          "language_info": {
           "codemirror_mode": {
            "name": "ipython",
            "version": 3
           },
           "file_extension": ".py",
           "mimetype": "text/x-python",
           "name": "python",
           "nbconvert_exporter": "python",
           "pygments_lexer": "ipython3",
           "version": "3.11.0"
          }
         },
         "nbformat": 4,
         "nbformat_minor": 4
        }
        EOF
        
        # Create README
        cat > README.md << EOF
        # $PROJECT_NAME
        
        A Jupyter-based $TEMPLATE project.
        
        ## Setup
        
        \`\`\`bash
        # Install dependencies
        pip install -r requirements.txt
        
        # Start Jupyter Lab
        jupyter lab
        \`\`\`
        
        ## Project Structure
        
        \`\`\`
        $PROJECT_NAME/
        ├── notebooks/          # Jupyter notebooks
        ├── data/
        │   ├── raw/           # Raw data files
        │   └── processed/     # Processed data files
        ├── src/               # Source code modules
        ├── tests/             # Unit tests
        ├── docs/              # Documentation
        ├── requirements.txt   # Python dependencies
        └── README.md         # This file
        \`\`\`
        EOF
        
        echo ""
        echo "✅ Project created successfully!"
        echo "📁 Location: $(pwd)"
        echo ""
        echo "🚀 Next steps:"
        echo "  cd $PROJECT_NAME"
        echo "  pip install -r requirements.txt"
        echo "  jupyter lab"
      '';
    };
    
    # Global health check
    home-manager.users.yuki.home.file."bin/jupyter-env-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔬 Jupyter Environment Health Check"
        echo "==================================="
        echo ""
        
        # Check Python
        if command -v python &> /dev/null; then
          PYTHON_VERSION=$(python --version 2>&1)
          echo "✅ Python: $PYTHON_VERSION"
        else
          echo "❌ Python: Not found"
          exit 1
        fi
        
        # Check core packages
        echo ""
        echo "📦 Core Packages:"
        
        for package in jupyter jupyterlab numpy pandas matplotlib; do
          if python -c "import $package" 2>/dev/null; then
            VERSION=$(python -c "import $package; print($package.__version__)" 2>/dev/null || echo "unknown")
            echo "  ✅ $package: $VERSION"
          else
            echo "  ❌ $package: Not available"
          fi
        done
        
        # Check Jupyter kernels
        echo ""
        echo "🔧 Jupyter Kernels:"
        if command -v jupyter &> /dev/null; then
          jupyter kernelspec list 2>/dev/null | grep -E "python|available" || echo "  ⚠️  No kernels found"
        else
          echo "  ❌ Jupyter command not available"
        fi
        
        # Check optional packages
        echo ""
        echo "🧪 Optional Packages:"
        for package in scipy scikit-learn plotly seaborn; do
          if python -c "import $package" 2>/dev/null; then
            echo "  ✅ $package: Available"
          else
            echo "  ⚠️  $package: Not available"
          fi
        done
        
        echo ""
        echo "🎯 Environment Status: Ready for Jupyter development"
      '';
    };
  };
}