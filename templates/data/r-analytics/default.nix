# R Statistical Computing Development Environment
# Complete setup for R statistical analysis, data visualization, and reporting

{ pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  }
, lib ? pkgs.lib
, stdenv ? pkgs.stdenv
}:

let
  # R package set with statistical libraries
  rPackages = pkgs.rWrapper.override {
    packages = with pkgs.rPackages; [
      # Core data manipulation
      tidyverse
      dplyr
      ggplot2
      tidyr
      readr
      purrr
      stringr
      forcats
      lubridate
      
      # Data visualization
      plotly
      shiny
      shinydashboard
      flexdashboard
      DT
      leaflet
      
      # Statistical analysis
      caret
      randomForest
      glmnet
      survival
      lme4
      nlme
      
      # Machine learning
      e1071
      rpart
      gbm
      xgboost
      
      # Time series
      forecast
      zoo
      xts
      
      # Bioinformatics
      BiocManager
      
      # Reporting
      rmarkdown
      knitr
      bookdown
      blogdown
      
      # Database connectivity
      DBI
      RSQLite
      RPostgreSQL
      
      # Development tools
      devtools
      testthat
      roxygen2
      usethis
      
      # Performance
      Rcpp
      data_table
      
      # Utilities
      here
      janitor
      scales
    ];
  };

  # Development scripts
  setupScript = pkgs.writeShellScriptBin "setup-r-stats" ''
    set -e
    
    echo "🚀 Setting up R Statistical Computing environment..."
    
    # Create project structure
    mkdir -p {R,data,reports,scripts,tests,man}
    
    # Initialize git if not exists
    if [ ! -d .git ]; then
      git init
    fi
    
    # Create .gitignore for R projects
    cat > .gitignore << 'EOF'
    # History files
    .Rhistory
    .Rapp.history
    
    # Session Data files
    .RData
    .RDataTmp
    
    # User-specific files
    .Ruserdata
    
    # Example code in package build process
    *-Ex.R
    
    # Output files from R CMD build
    /*.tar.gz
    
    # Output files from R CMD check
    /*.Rcheck/
    
    # RStudio files
    .Rproj.user/
    *.Rproj
    
    # produced vignettes
    vignettes/*.html
    vignettes/*.pdf
    
    # OAuth2 token, see https://github.com/hadley/httr/releases/tag/v0.3
    .httr-oauth
    
    # knitr and R markdown default cache directories
    *_cache/
    /cache/
    
    # Temporary files created by R markdown
    *.utf8.md
    *.knit.md
    
    # R Environment Variables
    .Renviron
    
    # Data files
    data/*.csv
    data/*.rds
    data/*.RData
    
    # Shiny token, see https://shiny.rstudio.com/articles/shinyapps.html
    rsconnect/
    EOF
    
    # Create DESCRIPTION file for package development
    cat > DESCRIPTION << 'EOF'
    Package: MyRProject
    Title: Statistical Analysis Project
    Version: 0.0.0.9000
    Authors@R: 
        person("Your", "Name", , "your.email@example.com", role = c("aut", "cre"),
               comment = c(ORCID = "YOUR-ORCID-ID"))
    Description: Description of your statistical analysis project.
    License: MIT + file LICENSE
    Encoding: UTF-8
    Roxygen: list(markdown = TRUE)
    RoxygenNote: 7.2.3
    Depends: 
        R (>= 4.1.0)
    Imports: 
        tidyverse,
        ggplot2,
        dplyr
    Suggests: 
        testthat (>= 3.0.0)
    Config/testthat/edition: 3
    EOF
    
    # Verify installations
    echo "🔍 Verifying installations..."
    R --version | head -n1
    
    echo ""
    echo "🎯 Quick start:"
    echo "  r-dev console      # Start R console"
    echo "  r-dev rstudio      # Start RStudio (if available)"
    echo "  r-dev shiny        # Run Shiny app"
    echo ""
    echo "✅ R Statistical Computing environment ready!"
  '';

  devScript = pkgs.writeShellScriptBin "r-dev" ''
    case "$1" in
      console)
        echo "📊 Starting R console..."
        R
        ;;
      script)
        echo "📝 Running R script..."
        if [ -n "$2" ]; then
          Rscript "$2"
        else
          echo "Usage: r-dev script <script.R>"
        fi
        ;;
      render)
        echo "📄 Rendering R Markdown..."
        if [ -n "$2" ]; then
          Rscript -e "rmarkdown::render('$2')"
        else
          echo "Usage: r-dev render <document.Rmd>"
        fi
        ;;
      shiny)
        echo "✨ Running Shiny app..."
        if [ -n "$2" ]; then
          Rscript -e "shiny::runApp('$2', host='0.0.0.0', port=3838)"
        else
          Rscript -e "shiny::runApp('.', host='0.0.0.0', port=3838)"
        fi
        ;;
      test)
        echo "🧪 Running tests..."
        Rscript -e "devtools::test()"
        ;;
      check)
        echo "🔍 Checking package..."
        Rscript -e "devtools::check()"
        ;;
      document)
        echo "📚 Generating documentation..."
        Rscript -e "devtools::document()"
        ;;
      install)
        echo "📦 Installing package..."
        Rscript -e "devtools::install()"
        ;;
      deps)
        echo "📦 Installing dependencies..."
        Rscript -e "devtools::install_deps()"
        ;;
      build)
        echo "🏗️ Building package..."
        R CMD build .
        ;;
      lint)
        echo "🔍 Linting code..."
        Rscript -e "lintr::lint_package()"
        ;;
      format)
        echo "💅 Formatting code..."
        Rscript -e "styler::style_pkg()"
        ;;
      profile)
        echo "⚡ Profiling script..."
        if [ -n "$2" ]; then
          Rscript -e "
          library(profvis)
          profvis({
            source('$2')
          })
          "
        else
          echo "Usage: r-dev profile <script.R>"
        fi
        ;;
      benchmark)
        echo "📊 Running benchmarks..."
        if [ -n "$2" ]; then
          Rscript -e "
          library(microbenchmark)
          source('$2')
          "
        else
          echo "Usage: r-dev benchmark <benchmark.R>"
        fi
        ;;
      clean)
        echo "🧹 Cleaning project..."
        rm -rf .Rproj.user/
        rm -f .RData .Rhistory
        find . -name "*_cache" -type d -exec rm -rf {} + 2>/dev/null || true
        ;;
      jupyter)
        echo "📓 Starting Jupyter with R kernel..."
        jupyter lab --no-browser --ip=0.0.0.0 --port=8888
        ;;
      plumber)
        echo "🔌 Starting Plumber API..."
        if [ -n "$2" ]; then
          Rscript -e "
          library(plumber)
          pr('$2') %>%
            pr_run(host='0.0.0.0', port=8000)
          "
        else
          echo "Usage: r-dev plumber <api.R>"
        fi
        ;;
      docker:build)
        echo "🐳 Building Docker image..."
        docker build -t r-project .
        ;;
      docker:run)
        echo "🐳 Running Docker container..."
        docker run -p 8787:8787 -e PASSWORD=rstudio -v $(pwd):/home/rstudio r-project
        ;;
      *)
        echo "📊 R Statistical Computing Development Commands"
        echo ""
        echo "Usage: r-dev <command> [args]"
        echo ""
        echo "Interactive commands:"
        echo "  console           Start R console"
        echo "  script <file>     Run R script"
        echo "  render <file>     Render R Markdown document"
        echo "  shiny [dir]       Run Shiny application"
        echo "  jupyter           Start Jupyter Lab with R kernel"
        echo "  plumber <file>    Start Plumber API"
        echo ""
        echo "Package development:"
        echo "  test              Run package tests"
        echo "  check             Check package"
        echo "  document          Generate documentation"
        echo "  install           Install package"
        echo "  deps              Install dependencies"
        echo "  build             Build package"
        echo ""
        echo "Code quality:"
        echo "  lint              Lint R code"
        echo "  format            Format R code"
        echo "  profile <file>    Profile R script"
        echo "  benchmark <file>  Run benchmarks"
        echo ""
        echo "Utilities:"
        echo "  clean             Clean project files"
        echo "  docker:build      Build Docker image"
        echo "  docker:run        Run Docker container"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "r-stats-dev";
  
  buildInputs = with pkgs; [
    # R with packages
    rPackages
    
    # System dependencies
    which
    pandoc
    texlive.combined.scheme-medium
    
    # Development tools
    git
    setupScript
    devScript
    
    # Additional tools for R
    cairo
    pkg-config
    
    # Optional: RStudio Server (commented out as it requires specific setup)
    # rstudio-server
    
    # Container tools
    docker
    
    # Jupyter with R kernel
    jupyter
    
    # Additional utilities
    curl
    wget
  ];

  shellHook = ''
    # R environment
    export R_LIBS_USER="$HOME/.R/library"
    export R_ENVIRON_USER="$HOME/.Renviron"
    export R_PROFILE_USER="$HOME/.Rprofile"
    
    # Create R library directory
    mkdir -p "$R_LIBS_USER"
    
    # Pandoc for R Markdown
    export RSTUDIO_PANDOC="${pkgs.pandoc}/bin"
    
    # Performance settings
    export OMP_NUM_THREADS=4
    
    echo "📊 R Statistical Computing Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 R: $(R --version | head -n1)"
    echo "📄 Pandoc: $(pandoc --version | head -n1)"
    echo "📓 Jupyter: $(jupyter --version | head -n1)"
    echo "📦 Package library: $R_LIBS_USER"
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-r-stats     # Initial project setup"
    echo "  r-dev             # Development commands"
    echo ""
    echo "📚 Quick start:"
    echo "  r-dev console     # Start R console"
    echo "  r-dev shiny       # Run Shiny app (localhost:3838)"
    echo "  r-dev jupyter     # Start Jupyter Lab (localhost:8888)"
    echo ""
    echo "📊 Key packages available:"
    echo "  tidyverse, ggplot2, shiny, rmarkdown, caret, forecast"
    echo ""
    echo "📂 Project structure:"
    echo "  R/                # R source code"
    echo "  data/             # Data files"
    echo "  reports/          # Analysis reports"
    echo "  tests/            # Unit tests"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';
}