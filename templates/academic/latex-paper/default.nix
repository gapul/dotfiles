# Modern LaTeX Academic Paper Template
# Optimized for academic writing with modern tools and workflow

{ lib, pkgs, ... }:

let
  # TeX tools for academic writing
  texTools = with pkgs; [
    # Core TeXLive with comprehensive packages
    texlive.combined.scheme-full
    
    # Modern workflow tools
    pandoc                    # Markdown ↔ LaTeX conversion
    biber                     # Modern bibliography processor
    latexrun                  # LaTeX build tool
    rubber                    # LaTeX build system with error parsing
    
    # Language servers and development tools
    texlab                    # TeX language server
    ltex-ls                   # Grammar and spell checking LSP
    
    # PDF tools
    qpdf                      # PDF manipulation
    pdftk                     # PDF toolkit
    poppler_utils             # PDF utilities
    zathura                   # PDF viewer with SyncTeX
    
    # Japanese fonts (for international papers)
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    
    # Development environment
    git                       # Version control
    make                      # Build automation
  ];

  # Editor packages for LaTeX development  
  editorTools = with pkgs; [
    # VS Code with extensions (configured via home-manager)
    vscode
    
    # Neovim with LaTeX support (configured via home-manager)
    neovim
    
    # Spell checking
    hunspell
    hunspellDicts.en_US
    aspell
    aspellDicts.en
  ];

  # Bibliography and citation tools
  citationTools = with pkgs; [
    # Bibliography processing
    biber
    bibtex
    
    # Citation style processors
    citeproc
  ];

in {
  # Development shell for LaTeX academic writing
  devShells.default = pkgs.mkShell {
    name = "latex-academic-paper";
    
    buildInputs = texTools ++ editorTools ++ citationTools;
    
    shellHook = ''
      echo "📝 LaTeX Academic Paper Template"
      echo "=============================="
      echo ""
      echo "🔧 Available tools:"
      echo "  • LuaLaTeX: Advanced LaTeX engine with Unicode support"
      echo "  • Biber: Modern bibliography processor"
      echo "  • Pandoc: Universal document converter"
      echo "  • VS Code: GUI editor with LaTeX Workshop"
      echo "  • Neovim: Terminal editor with Vimtex"
      echo "  • Zathura: PDF viewer with SyncTeX support"
      echo ""
      echo "📚 Workflow:"
      echo "  1. Write content in LaTeX or Markdown"
      echo "  2. Manage bibliography with .bib files"
      echo "  3. Build with 'make' or editor integration"
      echo "  4. Preview PDF with SyncTeX navigation"
      echo ""
      echo "🚀 Quick start:"
      echo "  make setup    # Initialize paper structure"
      echo "  make build    # Build PDF"
      echo "  make watch    # Continuous build"
      echo "  make clean    # Clean auxiliary files"
      echo ""
      
      # Set up TeX environment variables
      export TEXMFHOME="$PWD/.texmf"
      export TEXMFVAR="$PWD/.texlive/texmf-var"  
      export TEXMFCONFIG="$PWD/.texlive/texmf-config"
      
      # Create TeX directories if they don't exist
      mkdir -p .texmf/tex/latex
      mkdir -p .texlive/texmf-var
      mkdir -p .texlive/texmf-config
      
      # Set up Git if not already initialized
      if [ ! -d .git ]; then
        echo "📋 Initializing Git repository..."
        git init
        echo "*.aux" > .gitignore
        echo "*.bbl" >> .gitignore
        echo "*.blg" >> .gitignore
        echo "*.fls" >> .gitignore
        echo "*.fdb_latexmk" >> .gitignore
        echo "*.log" >> .gitignore
        echo "*.out" >> .gitignore
        echo "*.toc" >> .gitignore
        echo "*.synctex.gz" >> .gitignore
        echo "*.bcf" >> .gitignore
        echo "*.run.xml" >> .gitignore
        echo "*.nav" >> .gitignore
        echo "*.snm" >> .gitignore
        echo "*.vrb" >> .gitignore
        echo ".texlive/" >> .gitignore
        echo ".texmf/" >> .gitignore
        echo "Generated .gitignore for LaTeX project"
      fi
      
      # Health check
      if command -v latex-health &> /dev/null; then
        echo ""
        echo "🩺 Environment health check:"
        latex-health --quiet
      fi
    '';
    
    # Environment variables for optimal LaTeX development
    TEXMFHOME = ".texmf";
    TEXMFVAR = ".texlive/texmf-var";
    TEXMFCONFIG = ".texlive/texmf-config";
    
    # Enable shell history and completion
    SHELL_COMPLETION = "1";
  };
  
  # Template metadata
  meta = {
    name = "LaTeX Academic Paper";
    description = "Modern LaTeX environment for academic paper writing with full toolchain";
    category = "academic";
    tags = [ "latex" "academic" "paper" "research" "bibtex" "lualatex" ];
    maturity = "stable";
    platforms = [ "darwin" "linux" ];
    maintainers = [ "dotfiles-team" ];
  };
}