#!/usr/bin/env bash
# Project Type Detection Script
# Auto-detects project type based on files and configurations in the directory
set -euo pipefail

# Default to current directory if no argument provided
PROJECT_DIR="${1:-.}"

# Check if directory exists
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "unknown"
  exit 1
fi

# Change to project directory for easier file detection
cd "$PROJECT_DIR"

# Detection logic based on key files and configurations
detect_project_type() {
  # Node.js ecosystem detection
  if [[ -f "package.json" ]]; then
    # Check for specific frameworks in package.json
    if grep -q '"next"' package.json 2>/dev/null; then
      echo "nextjs"
      return
    elif grep -q '"@angular/core"' package.json 2>/dev/null; then
      echo "angular"
      return
    elif grep -q '"react"' package.json 2>/dev/null; then
      echo "react"
      return
    elif grep -q '"vue"' package.json 2>/dev/null; then
      echo "vue"
      return
    elif grep -q '"nuxt"' package.json 2>/dev/null; then
      echo "nuxt"
      return
    elif grep -q '"svelte"' package.json 2>/dev/null; then
      echo "svelte"
      return
    elif grep -q '"electron"' package.json 2>/dev/null; then
      echo "electron"
      return
    else
      echo "nodejs"
      return
    fi
  fi

  # Rust project detection
  if [[ -f "Cargo.toml" ]]; then
    echo "rust"
    return
  fi

  # Go project detection
  if [[ -f "go.mod" ]] || [[ -f "go.sum" ]]; then
    echo "go"
    return
  fi

  # Python project detection
  if [[ -f "pyproject.toml" ]]; then
    echo "python"
    return
  elif [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]] || [[ -f "Pipfile" ]]; then
    echo "python"
    return
  elif [[ -f "poetry.lock" ]]; then
    echo "python"
    return
  fi

  # Java/JVM ecosystem
  if [[ -f "pom.xml" ]]; then
    echo "java"
    return
  elif [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
    if grep -q "kotlin" build.gradle* 2>/dev/null; then
      echo "kotlin"
      return
    else
      echo "java"
      return
    fi
  elif [[ -f "project.clj" ]]; then
    echo "clojure"
    return
  fi

  # PHP project detection
  if [[ -f "composer.json" ]]; then
    echo "php"
    return
  fi

  # Ruby project detection
  if [[ -f "Gemfile" ]] || [[ -f "*.gemspec" ]]; then
    echo "ruby"
    return
  fi

  # C/C++ project detection
  if [[ -f "CMakeLists.txt" ]]; then
    echo "cpp"
    return
  elif [[ -f "Makefile" ]] && [[ -f "*.c" || -f "*.cpp" || -f "*.cc" ]]; then
    echo "cpp"
    return
  fi

  # .NET project detection
  if [[ -f "*.csproj" ]] || [[ -f "*.sln" ]] || [[ -f "project.json" ]]; then
    echo "dotnet"
    return
  fi

  # Swift project detection
  if [[ -f "Package.swift" ]]; then
    echo "swift"
    return
  fi

  # Flutter/Dart project detection
  if [[ -f "pubspec.yaml" ]]; then
    if grep -q "flutter:" pubspec.yaml 2>/dev/null; then
      echo "flutter"
      return
    else
      echo "dart"
      return
    fi
  fi

  # Docker project detection
  if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
    echo "docker"
    return
  fi

  # Infrastructure as Code detection
  if [[ -f "main.tf" ]] || [[ -f "*.tf" ]]; then
    echo "terraform"
    return
  elif [[ -f "ansible.cfg" ]] || [[ -f "playbook.yml" ]] || [[ -f "site.yml" ]]; then
    echo "ansible"
    return
  fi

  # Kubernetes detection
  if [[ -f "kustomization.yaml" ]] || [[ -f "Chart.yaml" ]]; then
    echo "kubernetes"
    return
  fi

  # Web frameworks and static sites
  if [[ -f "gatsby-config.js" ]]; then
    echo "gatsby"
    return
  elif [[ -f "_config.yml" ]] || [[ -f "_config.yaml" ]]; then
    echo "jekyll"
    return
  elif [[ -f "hugo.toml" ]] || [[ -f "config.toml" ]]; then
    echo "hugo"
    return
  fi

  # R project detection
  if [[ -f "*.R" ]] || [[ -f "*.Rmd" ]] || [[ -f "DESCRIPTION" ]]; then
    echo "r"
    return
  fi

  # LaTeX project detection
  if [[ -f "*.tex" ]]; then
    echo "latex"
    return
  fi

  # Unity project detection
  if [[ -d "Assets" ]] && [[ -d "ProjectSettings" ]]; then
    echo "unity"
    return
  fi

  # Unknown project type
  echo "unknown"
}

# Execute detection
detect_project_type