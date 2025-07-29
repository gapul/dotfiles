# Template configuration for LaTeX Academic Paper
# Integration with templates system

{ lib, pkgs, ... }:

{
  # Template metadata for templates/index.nix integration
  meta = {
    name = "LaTeX Academic Paper";
    description = "Modern LaTeX environment for academic paper writing with comprehensive toolchain";
    category = "academic";
    tags = [ "latex" "academic" "paper" "research" "bibtex" "lualatex" "japanese" ];
    maturity = "stable";
    platforms = [ "darwin" "linux" ];
    dependencies = [ "texlive" "biber" "pandoc" "git" ];
    maintainers = [ "dotfiles-team" ];
  };

  # Component interface for composition
  provides = [ "latex-document" "academic-paper" "bibliography-system" ];
  requires = [ ];
  ports = { };

  # Template-specific environment variables
  environment = {
    PAPER_NAME = "paper";
    LATEX_ENGINE = "lualatex";
    BIB_PROCESSOR = "biber";
    BUILD_DIR = "build";
  };

  # Quick setup commands
  setupCommands = [
    "make setup"    # Initialize project structure
    "make build"    # Build PDF
    "make watch"    # Start continuous build
  ];

  # Health check commands
  healthCheck = [
    "command -v lualatex"
    "command -v biber"
    "command -v pandoc"
    "test -f Makefile"
    "test -f paper.tex || test -f template-paper.tex"
  ];

  # Integration with other templates
  compatibleWith = [
    "data/r-analytics"     # For statistical papers
    "data/python-ml"       # For ML research papers
  ];

  # Template-specific aliases
  aliases = {
    build = "make build";
    watch = "make watch";
    clean = "make clean";
    view = "make view";
    spell = "make spell";
    wordcount = "make wordcount";
    archive = "make archive";
  };
}