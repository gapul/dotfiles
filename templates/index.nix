# Development Environment Templates Index
# Central registry for all available development templates and components

{ lib, pkgs, ... }:

let
  # Import shared utilities and components
  utils = import ./_shared/utils.nix { inherit lib pkgs; };
  workspace = import ./_shared/workspace.nix { inherit lib pkgs; };
  components = import ./_shared/component.nix { inherit lib pkgs; };
  
  # Template categories
  categories = {
    web = "Web Development";
    mobile = "Mobile Development"; 
    data = "Data Science & Analytics";
    systems = "Systems Programming";
    academic = "Academic & Research";
  };

  # Template registry with component information
  templates = {
    # Web Development Templates
    "web/nextjs-fullstack" = {
      name = "Next.js Fullstack";
      description = "Full-stack Next.js with TypeScript, authentication, database, and payments";
      category = "web";
      tags = [ "nextjs" "typescript" "react" "prisma" "postgresql" "auth" "payments" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "nodejs" "postgresql" "redis" ];
      
      # Component interface
      provides = [ "web-ui" "web-api" "frontend-routes" "rest-endpoints" ];
      requires = [ ];
      ports = { frontend = 3000; api = 3001; };
      
      # Quick composition
      components = [ "nextjs-frontend" "node-api" "postgresql-db" ];
    };
    
    "web/vue-typescript" = {
      name = "Vue.js + TypeScript";
      description = "Modern Vue.js with TypeScript, Vite, and comprehensive testing";
      category = "web";
      tags = [ "vue" "typescript" "vite" "testing" "pinia" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "nodejs" ];
    };
    
    "web/node-api" = {
      name = "TypeScript Node.js API";
      description = "RESTful API with TypeScript, Express, Prisma, and comprehensive tooling";
      category = "web";
      tags = [ "nodejs" "typescript" "express" "prisma" "api" "rest" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "nodejs" "postgresql" ];
    };
    
    "web/docker-fullstack" = {
      name = "Docker Fullstack";
      description = "Multi-service containerized applications with orchestration";
      category = "web";
      tags = [ "docker" "containers" "microservices" "orchestration" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "docker" "docker-compose" ];
    };

    # Mobile Development Templates
    "mobile/react-native" = {
      name = "React Native";
      description = "Cross-platform mobile development with Expo and TypeScript";
      category = "mobile";
      tags = [ "react-native" "expo" "typescript" "ios" "android" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "nodejs" "android-sdk" ];
    };
    
    "mobile/flutter" = {
      name = "Flutter";
      description = "Cross-platform native mobile development with Dart";
      category = "mobile";
      tags = [ "flutter" "dart" "ios" "android" "web" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "flutter" "android-sdk" ];
    };

    # Data Science Templates
    "data/python-ml" = {
      name = "Python Machine Learning";
      description = "ML development with Python, Jupyter, PyTorch, TensorFlow, and GPU support";
      category = "data";
      tags = [ "python" "ml" "jupyter" "pytorch" "tensorflow" "gpu" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "python" "cuda" ];
    };
    
    "data/r-analytics" = {
      name = "R Statistical Analytics";
      description = "Statistical computing and data visualization with R and Shiny";
      category = "data";
      tags = [ "r" "statistics" "shiny" "visualization" "data-analysis" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "r" ];
    };

    # Systems Programming Templates  
    "systems/rust-cli" = {
      name = "Rust CLI";
      description = "Command-line applications and system tools in Rust";
      category = "systems";
      tags = [ "rust" "cli" "systems" "performance" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "rust" ];
    };
    
    "systems/go-api" = {
      name = "Go Web API";
      description = "High-performance web services and APIs in Go";
      category = "systems";
      tags = [ "go" "api" "web" "performance" "microservices" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "go" ];
    };

    # Academic & Research Templates
    "academic/latex-paper" = {
      name = "LaTeX Academic Paper";
      description = "Modern LaTeX environment for academic paper writing with comprehensive toolchain";
      category = "academic";
      tags = [ "latex" "academic" "paper" "research" "bibtex" "lualatex" "japanese" ];
      maturity = "stable";
      platforms = [ "darwin" "linux" ];
      dependencies = [ "texlive" "biber" "pandoc" "git" ];
      
      # Component interface
      provides = [ "latex-document" "academic-paper" "bibliography-system" ];
      requires = [ ];
      ports = { };
      
      # Academic workflow integration
      components = [ "lualatex-engine" "biber-bibliography" "synctex-preview" ];
    };
  };

  # Helper functions
  getTemplatesByCategory = category: 
    lib.filterAttrs (path: template: template.category == category) templates;
    
  getTemplatesByTag = tag:
    lib.filterAttrs (path: template: lib.elem tag template.tags) templates;
    
  getTemplatesByPlatform = platform:
    lib.filterAttrs (path: template: lib.elem platform template.platforms) templates;

  # Template path resolver
  getTemplatePath = templateId: ./. + "/${templateId}";
  
  # Template loader
  loadTemplate = templateId: 
    let
      templatePath = getTemplatePath templateId;
      templateFile = templatePath + "/default.nix";
    in
    if builtins.pathExists templateFile
    then import templateFile { inherit lib pkgs; }
    else throw "Template not found: ${templateId}";

  # List all available templates
  listTemplates = lib.mapAttrs (path: template: {
    inherit (template) name description category tags maturity platforms dependencies;
    path = path;
  }) templates;

  # Search templates
  searchTemplates = query: 
    let
      queryLower = lib.toLower query;
      matchesQuery = template: 
        lib.hasInfix queryLower (lib.toLower template.name) ||
        lib.hasInfix queryLower (lib.toLower template.description) ||
        lib.any (tag: lib.hasInfix queryLower (lib.toLower tag)) template.tags;
    in
    lib.filterAttrs (path: template: matchesQuery template) templates;

in {
  inherit 
    templates 
    categories
    utils
    getTemplatesByCategory
    getTemplatesByTag  
    getTemplatesByPlatform
    getTemplatePath
    loadTemplate
    listTemplates
    searchTemplates;

  # CLI interface for template management
  templateCli = pkgs.writeShellScriptBin "template" ''
    set -e
    
    case "$1" in
      list)
        echo "📁 Available Development Templates"
        echo "════════════════════════════════════════════════════════════════════════════════"
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: template: ''
        echo "📦 ${template.name}"
        echo "   Path: ${path}"
        echo "   Description: ${template.description}"
        echo "   Category: ${template.category}"
        echo "   Tags: ${lib.concatStringsSep ", " template.tags}"
        echo "   Platforms: ${lib.concatStringsSep ", " template.platforms}"
        echo ""
        '') templates)}
        ;;
      search)
        if [ -z "$2" ]; then
          echo "Usage: template search <query>"
          exit 1
        fi
        echo "🔍 Searching templates for: $2"
        echo "Results will be shown here..."
        ;;
      use)
        if [ -z "$2" ]; then
          echo "Usage: template use <template-path>"
          echo ""
          echo "Available templates:"
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: _: "echo \"  ${path}\"") templates)}
          exit 1
        fi
        
        template_path="${toString (./.)}"/"$2"
        if [ -f "$template_path/default.nix" ]; then
          echo "🚀 Entering development environment: $2"
          nix develop "$template_path"
        else
          echo "❌ Template not found: $2"
          exit 1
        fi
        ;;
      health)
        echo "🩺 Running environment health check..."
        ${toString ./_shared/scripts/health-check.sh}
        ;;
      *)
        echo "📁 Development Template Manager"
        echo ""
        echo "Usage: template <command> [args]"
        echo ""
        echo "Commands:"
        echo "  list              List all available templates"
        echo "  search <query>    Search templates by name, description, or tags"
        echo "  use <path>        Enter a template development environment"
        echo "  health            Run environment health check"
        echo ""
        echo "Examples:"
        echo "  template list"
        echo "  template search react"
        echo "  template use web/nextjs-fullstack"
        echo ""
        echo "Available template categories:"
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (key: desc: "echo \"  ${key} - ${desc}\"") categories)}
        ;;
    esac
  '';
}