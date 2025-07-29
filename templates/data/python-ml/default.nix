# Data Science & Machine Learning Development Environment
# Complete setup for Python ML development with Jupyter, GPU support, and popular libraries

{ pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  }
, lib ? pkgs.lib
, stdenv ? pkgs.stdenv
}:

let
  # Python package set with ML libraries
  pythonPackages = pkgs.python311.withPackages (ps: with ps; [
    # Core scientific computing
    numpy
    scipy
    pandas
    matplotlib
    seaborn
    plotly
    bokeh
    
    # Machine learning
    scikit-learn
    xgboost
    lightgbm
    catboost
    
    # Deep learning frameworks
    tensorflow
    torch
    torchvision
    torchaudio
    pytorch-lightning
    transformers
    
    # Jupyter ecosystem
    jupyter
    jupyterlab
    ipython
    ipywidgets
    nbconvert
    papermill
    
    # Data processing
    polars
    pyarrow
    dask
    h5py
    tables
    
    # Computer vision
    opencv4
    pillow
    scikit-image
    
    # Natural language processing
    nltk
    spacy
    gensim
    
    # Statistics and metrics
    statsmodels
    pingouin
    
    # Visualization
    altair
    pygraphviz
    
    # Development tools
    black
    isort
    flake8
    mypy
    pytest
    pytest-cov
    
    # Utilities
    tqdm
    requests
    click
    pyyaml
    python-dotenv
  ]);

  # Development scripts
  setupScript = pkgs.writeShellScriptBin "setup-datascience" ''
    set -e
    
    echo "🚀 Setting up Data Science & ML development environment..."
    
    # Create project structure
    mkdir -p {notebooks,data/{raw,processed,external},src,models,reports,scripts}
    
    # Initialize git if not exists
    if [ ! -d .git ]; then
      git init
    fi
    
    # Create .gitignore for data science projects
    cat > .gitignore << 'EOF'
    # Byte-compiled / optimized / DLL files
    __pycache__/
    *.py[cod]
    *$py.class
    
    # Distribution / packaging
    .Python
    build/
    develop-eggs/
    dist/
    downloads/
    eggs/
    .eggs/
    lib/
    lib64/
    parts/
    sdist/
    var/
    wheels/
    *.egg-info/
    .installed.cfg
    *.egg
    
    # Data files
    data/raw/*
    data/external/*
    !data/raw/.gitkeep
    !data/external/.gitkeep
    *.csv
    *.tsv
    *.parquet
    *.h5
    *.hdf5
    
    # Model files
    models/*.pkl
    models/*.joblib
    models/*.pt
    models/*.pth
    models/*.h5
    models/*.pb
    
    # Jupyter Notebook
    .ipynb_checkpoints
    
    # Environment variables
    .env
    
    # IDE
    .vscode/
    .idea/
    
    # OS
    .DS_Store
    Thumbs.db
    EOF
    
    # Create placeholder files
    touch data/raw/.gitkeep
    touch data/processed/.gitkeep
    touch data/external/.gitkeep
    touch models/.gitkeep
    
    # Verify installations
    echo "🔍 Verifying installations..."
    python --version
    jupyter --version
    
    echo ""
    echo "🎯 Quick start:"
    echo "  ds-dev notebook     # Start Jupyter Lab"
    echo "  ds-dev train        # Run training script"
    echo "  ds-dev experiment   # Start MLflow experiment tracking"
    echo ""
    echo "✅ Data Science environment ready!"
  '';

  devScript = pkgs.writeShellScriptBin "ds-dev" ''
    case "$1" in
      notebook)
        echo "📓 Starting Jupyter Lab..."
        jupyter lab --no-browser --ip=0.0.0.0 --port=8888
        ;;
      nb:convert)
        echo "📄 Converting notebook to script..."
        if [ -n "$2" ]; then
          jupyter nbconvert --to script "$2"
        else
          echo "Usage: ds-dev nb:convert <notebook.ipynb>"
        fi
        ;;
      nb:run)
        echo "▶️ Running notebook..."
        if [ -n "$2" ]; then
          papermill "$2" "output_$(basename "$2")"
        else
          echo "Usage: ds-dev nb:run <notebook.ipynb>"
        fi
        ;;
      train)
        echo "🏋️ Running training script..."
        if [ -f "src/train.py" ]; then
          python src/train.py
        else
          echo "No src/train.py found. Create your training script first."
        fi
        ;;
      evaluate)
        echo "📊 Running evaluation..."
        if [ -f "src/evaluate.py" ]; then
          python src/evaluate.py
        else
          echo "No src/evaluate.py found. Create your evaluation script first."
        fi
        ;;
      data:download)
        echo "📥 Downloading data..."
        if [ -f "scripts/download_data.py" ]; then
          python scripts/download_data.py
        else
          echo "No scripts/download_data.py found. Create your data download script first."
        fi
        ;;
      data:process)
        echo "⚙️ Processing data..."
        if [ -f "src/data_processing.py" ]; then
          python src/data_processing.py
        else
          echo "No src/data_processing.py found. Create your data processing script first."
        fi
        ;;
      experiment)
        echo "🧪 Starting MLflow tracking server..."
        mlflow ui --host 0.0.0.0 --port 5000
        ;;
      tensorboard)
        echo "📈 Starting TensorBoard..."
        tensorboard --logdir=./logs --host=0.0.0.0 --port=6006
        ;;
      test)
        echo "🧪 Running tests..."
        pytest tests/ -v --cov=src
        ;;
      lint)
        echo "🔍 Running code analysis..."
        flake8 src/ tests/
        mypy src/
        ;;
      format)
        echo "💅 Formatting code..."
        black src/ tests/
        isort src/ tests/
        ;;
      profile)
        echo "⚡ Profiling script..."
        if [ -n "$2" ]; then
          python -m cProfile -o profile.stats "$2"
          echo "Profile saved to profile.stats"
        else
          echo "Usage: ds-dev profile <script.py>"
        fi
        ;;
      gpu:check)
        echo "🔍 Checking GPU availability..."
        python -c "
    import torch
    print(f'PyTorch CUDA available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'CUDA devices: {torch.cuda.device_count()}')
        for i in range(torch.cuda.device_count()):
            print(f'  Device {i}: {torch.cuda.get_device_name(i)}')
    
    try:
        import tensorflow as tf
        print(f'TensorFlow GPU devices: {len(tf.config.list_physical_devices(\"GPU\"))}')
    except ImportError:
        print('TensorFlow not available')
        "
        ;;
      clean)
        echo "🧹 Cleaning project..."
        find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
        find . -name "*.pyc" -delete
        rm -rf .pytest_cache
        rm -rf .mypy_cache
        ;;
      env:export)
        echo "📦 Exporting environment..."
        pip freeze > requirements.txt
        echo "Requirements exported to requirements.txt"
        ;;
      docker:build)
        echo "🐳 Building Docker image..."
        docker build -t ml-project .
        ;;
      docker:run)
        echo "🐳 Running Docker container..."
        docker run -p 8888:8888 -v $(pwd):/workspace ml-project
        ;;
      *)
        echo "🧬 Data Science & ML Development Commands"
        echo ""
        echo "Usage: ds-dev <command> [args]"
        echo ""
        echo "Notebook commands:"
        echo "  notebook          Start Jupyter Lab"
        echo "  nb:convert <nb>   Convert notebook to Python script"
        echo "  nb:run <nb>       Run notebook with papermill"
        echo ""
        echo "ML workflow commands:"
        echo "  train             Run training script"
        echo "  evaluate          Run evaluation script"
        echo "  data:download     Download data"
        echo "  data:process      Process raw data"
        echo ""
        echo "Experiment tracking:"
        echo "  experiment        Start MLflow UI"
        echo "  tensorboard       Start TensorBoard"
        echo ""
        echo "Development commands:"
        echo "  test              Run tests"
        echo "  lint              Run code analysis"
        echo "  format            Format code"
        echo "  profile <script>  Profile Python script"
        echo "  gpu:check         Check GPU availability"
        echo "  clean             Clean cache files"
        echo ""
        echo "Environment commands:"
        echo "  env:export        Export requirements.txt"
        echo "  docker:build      Build Docker image"
        echo "  docker:run        Run Docker container"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "datascience-ml-dev";
  
  buildInputs = with pkgs; [
    # Python with ML packages
    pythonPackages
    
    # System dependencies
    stdenv.cc.cc.lib
    zlib
    libGL
    glib
    
    # Development tools
    git
    setupScript
    devScript
    
    # Additional ML tools
    graphviz
    
    # Container tools
    docker
    
    # GPU support (if available)
  ] ++ lib.optionals (pkgs.config.cudaSupport or false) [
    cudatoolkit
    cudnn
  ] ++ [
    
    # Additional utilities
    jq
    curl
    wget
    unzip
  ];

  shellHook = ''
    # Python environment
    export PYTHONPATH="$PWD/src:$PYTHONPATH"
    export PYTHON_ENV="development"
    
    # Jupyter configuration
    export JUPYTER_CONFIG_DIR="$HOME/.jupyter"
    export JUPYTER_DATA_DIR="$HOME/.local/share/jupyter"
    
    # ML framework settings
    export TF_CPP_MIN_LOG_LEVEL=2
    export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128
    
    # Performance settings
    export OMP_NUM_THREADS=4
    export MKL_NUM_THREADS=4
    export NUMBA_NUM_THREADS=4
    
    ${lib.optionalString (pkgs.config.cudaSupport or false) ''
    # CUDA environment
    export CUDA_PATH="${pkgs.cudatoolkit}"
    export LD_LIBRARY_PATH="${pkgs.cudatoolkit}/lib:${pkgs.cudnn}/lib:$LD_LIBRARY_PATH"
    ''}
    
    # Create data directories if they don't exist
    mkdir -p data/{raw,processed,external} models reports logs
    
    echo "🧬 Data Science & Machine Learning Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐍 Python: $(python --version)"
    echo "📓 Jupyter: $(jupyter --version | head -n1)"
    echo "🔢 NumPy: $(python -c 'import numpy; print(numpy.__version__)')"
    echo "🐼 Pandas: $(python -c 'import pandas; print(pandas.__version__)')"
    echo "🔥 PyTorch: $(python -c 'import torch; print(torch.__version__)')"
    echo "🧠 TensorFlow: $(python -c 'import tensorflow as tf; print(tf.__version__)' 2>/dev/null || echo 'Not available')"
    ${lib.optionalString (pkgs.config.cudaSupport or false) ''
    echo "🚀 CUDA: Available"
    ''}
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-datascience  # Initial project setup"
    echo "  ds-dev             # Development commands"
    echo ""
    echo "📚 Quick start:"
    echo "  ds-dev notebook    # Start Jupyter Lab (localhost:8888)"
    echo "  ds-dev gpu:check   # Check GPU availability"
    echo "  ds-dev experiment  # Start MLflow UI (localhost:5000)"
    echo ""
    echo "📂 Project structure:"
    echo "  data/              # Raw, processed, and external data"
    echo "  notebooks/         # Jupyter notebooks"
    echo "  src/               # Source code"
    echo "  models/            # Trained models"
    echo "  reports/           # Analysis reports"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';

  # Platform-specific libraries
  LD_LIBRARY_PATH = lib.makeLibraryPath (with pkgs; [
    stdenv.cc.cc.lib
    zlib
    libGL
    glib
  ] ++ lib.optionals (pkgs.config.cudaSupport or false) [
    cudatoolkit
    cudnn
  ]);
}