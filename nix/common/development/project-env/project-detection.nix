{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.dotfiles.development.project-env.project-detection;

  # プロジェクト検出スクリプト
  projectDetectionScript = pkgs.writeShellScript "detect-project-type" ''
    #!/usr/bin/env bash
    # Advanced Project Type Detection with Nix Integration
    set -euo pipefail

    # デフォルトは現在のディレクトリ
    PROJECT_DIR="''${1:-.}"
    OUTPUT_FORMAT="''${2:-simple}"  # simple, json, verbose

    # ディレクトリ存在チェック
    if [[ ! -d "$PROJECT_DIR" ]]; then
      case "$OUTPUT_FORMAT" in
        "json")
          echo '{"type": "unknown", "error": "Directory not found"}'
          ;;
        *)
          echo "unknown"
          ;;
      esac
      exit 1
    fi

    # プロジェクトディレクトリに移動
    cd "$PROJECT_DIR"

    # プロジェクト情報を格納する連想配列
    declare -A project_info
    project_info[type]="unknown"
    project_info[framework]=""
    project_info[language]=""
    project_info[build_tool]=""
    project_info[package_manager]=""
    project_info[features]=""

    # 検出ロジック
    detect_project_type() {
      # Node.js エコシステム検出
      if [[ -f "package.json" ]]; then
        project_info[language]="javascript"
        project_info[package_manager]="npm"
        
        # yarn.lock や pnpm-lock.yaml の存在チェック
        if [[ -f "yarn.lock" ]]; then
          project_info[package_manager]="yarn"
        elif [[ -f "pnpm-lock.yaml" ]]; then
          project_info[package_manager]="pnpm"
        fi

        # フレームワーク検出
        if grep -q '"next"' package.json 2>/dev/null; then
          project_info[type]="nextjs"
          project_info[framework]="Next.js"
        elif grep -q '"@angular/core"' package.json 2>/dev/null; then
          project_info[type]="angular"
          project_info[framework]="Angular"
        elif grep -q '"react"' package.json 2>/dev/null; then
          project_info[type]="react"
          project_info[framework]="React"
        elif grep -q '"vue"' package.json 2>/dev/null; then
          project_info[type]="vue"
          project_info[framework]="Vue.js"
        elif grep -q '"nuxt"' package.json 2>/dev/null; then
          project_info[type]="nuxt"
          project_info[framework]="Nuxt.js"
        elif grep -q '"svelte"' package.json 2>/dev/null; then
          project_info[type]="svelte"
          project_info[framework]="Svelte"
        elif grep -q '"electron"' package.json 2>/dev/null; then
          project_info[type]="electron"
          project_info[framework]="Electron"
        elif grep -q '"express"' package.json 2>/dev/null; then
          project_info[type]="nodejs"
          project_info[framework]="Express"
        else
          project_info[type]="nodejs"
          project_info[framework]="Node.js"
        fi

        # TypeScript チェック
        if [[ -f "tsconfig.json" ]] || grep -q '"typescript"' package.json 2>/dev/null; then
          project_info[language]="typescript"
          project_info[features]+="typescript "
        fi

        # Build tools チェック
        if [[ -f "webpack.config.js" ]]; then
          project_info[build_tool]="webpack"
        elif [[ -f "vite.config.js" ]] || [[ -f "vite.config.ts" ]]; then
          project_info[build_tool]="vite"
        elif [[ -f "rollup.config.js" ]]; then
          project_info[build_tool]="rollup"
        fi

        return
      fi

      # Rust プロジェクト検出
      if [[ -f "Cargo.toml" ]]; then
        project_info[type]="rust"
        project_info[language]="rust"
        project_info[package_manager]="cargo"
        
        # ワークスペース検出
        if grep -q '\[workspace\]' Cargo.toml 2>/dev/null; then
          project_info[features]+="workspace "
        fi

        # Webアプリケーション検出
        if grep -q 'wasm-pack\|web-sys\|js-sys' Cargo.toml 2>/dev/null; then
          project_info[features]+="wasm "
        fi

        return
      fi

      # Go プロジェクト検出
      if [[ -f "go.mod" ]] || [[ -f "go.sum" ]]; then
        project_info[type]="go"
        project_info[language]="go"
        project_info[package_manager]="go"
        
        if [[ -f "go.mod" ]]; then
          local module_name=$(grep "^module " go.mod | cut -d' ' -f2)
          project_info[features]+="module:$module_name "
        fi

        return
      fi

      # Python プロジェクト検出
      if [[ -f "pyproject.toml" ]]; then
        project_info[type]="python"
        project_info[language]="python"
        project_info[package_manager]="pip"
        
        # Poetry 検出
        if grep -q '\[tool.poetry\]' pyproject.toml 2>/dev/null; then
          project_info[package_manager]="poetry"
        fi

        # PDM 検出
        if grep -q '\[tool.pdm\]' pyproject.toml 2>/dev/null; then
          project_info[package_manager]="pdm"
        fi

        return
      elif [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]] || [[ -f "Pipfile" ]]; then
        project_info[type]="python"
        project_info[language]="python"
        
        if [[ -f "Pipfile" ]]; then
          project_info[package_manager]="pipenv"
        elif [[ -f "poetry.lock" ]]; then
          project_info[package_manager]="poetry"
        else
          project_info[package_manager]="pip"
        fi

        # Django/Flask 検出
        if [[ -f "manage.py" ]] || grep -q 'django' requirements.txt 2>/dev/null; then
          project_info[framework]="Django"
        elif grep -q 'flask' requirements.txt 2>/dev/null; then
          project_info[framework]="Flask"
        elif grep -q 'fastapi' requirements.txt 2>/dev/null; then
          project_info[framework]="FastAPI"
        fi

        return
      fi

      # Java/JVM エコシステム
      if [[ -f "pom.xml" ]]; then
        project_info[type]="java"
        project_info[language]="java"
        project_info[build_tool]="maven"
        project_info[package_manager]="maven"
        return
      elif [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
        project_info[build_tool]="gradle"
        project_info[package_manager]="gradle"
        
        if grep -q "kotlin" build.gradle* 2>/dev/null; then
          project_info[type]="kotlin"
          project_info[language]="kotlin"
        else
          project_info[type]="java"
          project_info[language]="java"
        fi
        return
      elif [[ -f "project.clj" ]]; then
        project_info[type]="clojure"
        project_info[language]="clojure"
        project_info[build_tool]="leiningen"
        return
      fi

      # その他の言語
      if [[ -f "composer.json" ]]; then
        project_info[type]="php"
        project_info[language]="php"
        project_info[package_manager]="composer"
      elif [[ -f "Gemfile" ]] || [[ -f *.gemspec ]]; then
        project_info[type]="ruby"
        project_info[language]="ruby"
        project_info[package_manager]="bundler"
      elif [[ -f "CMakeLists.txt" ]]; then
        project_info[type]="cpp"
        project_info[language]="cpp"
        project_info[build_tool]="cmake"
      elif [[ -f "Makefile" ]] && [[ -f *.c || -f *.cpp || -f *.cc ]]; then
        project_info[type]="cpp"
        project_info[language]="cpp"
        project_info[build_tool]="make"
      elif [[ -f *.csproj ]] || [[ -f *.sln ]] || [[ -f "project.json" ]]; then
        project_info[type]="dotnet"
        project_info[language]="csharp"
        project_info[build_tool]="dotnet"
      elif [[ -f "Package.swift" ]]; then
        project_info[type]="swift"
        project_info[language]="swift"
        project_info[package_manager]="swift"
      elif [[ -f "pubspec.yaml" ]]; then
        if grep -q "flutter:" pubspec.yaml 2>/dev/null; then
          project_info[type]="flutter"
          project_info[framework]="Flutter"
        else
          project_info[type]="dart"
        fi
        project_info[language]="dart"
        project_info[package_manager]="pub"
      fi

      # インフラ系
      if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        project_info[features]+="docker "
      fi

      if [[ -f "main.tf" ]] || [[ -f *.tf ]]; then
        project_info[type]="terraform"
        project_info[language]="hcl"
      elif [[ -f "ansible.cfg" ]] || [[ -f "playbook.yml" ]] || [[ -f "site.yml" ]]; then
        project_info[type]="ansible"
        project_info[language]="yaml"
      elif [[ -f "kustomization.yaml" ]] || [[ -f "Chart.yaml" ]]; then
        project_info[type]="kubernetes"
        project_info[language]="yaml"
      fi

      # Web frameworks
      if [[ -f "gatsby-config.js" ]]; then
        project_info[type]="gatsby"
        project_info[framework]="Gatsby"
      elif [[ -f "_config.yml" ]] || [[ -f "_config.yaml" ]]; then
        project_info[type]="jekyll"
        project_info[framework]="Jekyll"
      elif [[ -f "hugo.toml" ]] || [[ -f "config.toml" ]]; then
        project_info[type]="hugo"
        project_info[framework]="Hugo"
      fi

      # その他
      if [[ -f *.R ]] || [[ -f *.Rmd ]] || [[ -f "DESCRIPTION" ]]; then
        project_info[type]="r"
        project_info[language]="r"
      elif [[ -f *.tex ]]; then
        project_info[type]="latex"
        project_info[language]="latex"
      elif [[ -d "Assets" ]] && [[ -d "ProjectSettings" ]]; then
        project_info[type]="unity"
        project_info[language]="csharp"
      fi

      # Nix検出
      if [[ -f "flake.nix" ]] || [[ -f "default.nix" ]] || [[ -f "shell.nix" ]]; then
        project_info[features]+="nix "
      fi
    }

    # 出力形式に応じた表示
    output_result() {
      case "$OUTPUT_FORMAT" in
        "json")
          echo -n "{"
          echo -n "\"type\":\"''${project_info[type]}\""
          [[ -n "''${project_info[language]}" ]] && echo -n ",\"language\":\"''${project_info[language]}\""
          [[ -n "''${project_info[framework]}" ]] && echo -n ",\"framework\":\"''${project_info[framework]}\""
          [[ -n "''${project_info[build_tool]}" ]] && echo -n ",\"build_tool\":\"''${project_info[build_tool]}\""
          [[ -n "''${project_info[package_manager]}" ]] && echo -n ",\"package_manager\":\"''${project_info[package_manager]}\""
          [[ -n "''${project_info[features]}" ]] && echo -n ",\"features\":\"''${project_info[features]}\""
          echo "}"
          ;;
        "verbose")
          echo "Project Type: ''${project_info[type]}"
          [[ -n "''${project_info[language]}" ]] && echo "Language: ''${project_info[language]}"
          [[ -n "''${project_info[framework]}" ]] && echo "Framework: ''${project_info[framework]}"
          [[ -n "''${project_info[build_tool]}" ]] && echo "Build Tool: ''${project_info[build_tool]}"
          [[ -n "''${project_info[package_manager]}" ]] && echo "Package Manager: ''${project_info[package_manager]}"
          [[ -n "''${project_info[features]}" ]] && echo "Features: ''${project_info[features]}"
          ;;
        *)
          echo "''${project_info[type]}"
          ;;
      esac
    }

    # 検出実行
    detect_project_type
    output_result
  '';

  # プロジェクト環境セットアップスクリプト
  projectEnvScript = pkgs.writeShellScript "setup-project-env" ''
    #!/usr/bin/env bash
    # Project Environment Setup based on Detection
    set -euo pipefail

    PROJECT_DIR="''${1:-.}"
    PROJECT_TYPE=$(${projectDetectionScript} "$PROJECT_DIR")

    echo "🚀 Setting up environment for $PROJECT_TYPE project in $PROJECT_DIR"

    cd "$PROJECT_DIR"

    case "$PROJECT_TYPE" in
      "nextjs"|"react"|"nodejs"|"typescript")
        echo "📦 Node.js project detected"
        if [[ ! -f ".nvmrc" ]]; then
          echo "node" > .nvmrc
          echo "✅ Created .nvmrc"
        fi
        
        if [[ ! -f ".env.example" ]]; then
          cat > .env.example << 'EOF'
# Environment Variables
NODE_ENV=development
# Add your environment variables here
EOF
          echo "✅ Created .env.example"
        fi
        ;;

      "rust")
        echo "🦀 Rust project detected"
        if [[ ! -f "rust-toolchain.toml" ]]; then
          cat > rust-toolchain.toml << 'EOF'
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
EOF
          echo "✅ Created rust-toolchain.toml"
        fi
        ;;

      "python")
        echo "🐍 Python project detected"
        if [[ ! -f ".python-version" ]]; then
          echo "3.11" > .python-version
          echo "✅ Created .python-version"
        fi
        ;;

      "go")
        echo "🐹 Go project detected"
        if [[ ! -f ".go-version" ]]; then
          echo "1.21" > .go-version
          echo "✅ Created .go-version"
        fi
        ;;
    esac

    # 共通ファイル作成
    if [[ ! -f ".gitignore" ]]; then
      echo "📄 Creating .gitignore"
      case "$PROJECT_TYPE" in
        "nextjs"|"react"|"nodejs"|"typescript")
          curl -s "https://www.toptal.com/developers/gitignore/api/node" > .gitignore
          ;;
        "rust")
          curl -s "https://www.toptal.com/developers/gitignore/api/rust" > .gitignore
          ;;
        "python")
          curl -s "https://www.toptal.com/developers/gitignore/api/python" > .gitignore
          ;;
        "go")
          curl -s "https://www.toptal.com/developers/gitignore/api/go" > .gitignore
          ;;
        *)
          echo "# Project specific files" > .gitignore
          echo ".DS_Store" >> .gitignore
          echo ".env" >> .gitignore
          ;;
      esac
      echo "✅ Created .gitignore"
    fi

    echo "🎉 Project environment setup completed!"
  '';

in {
  options.dotfiles.development.project-env.project-detection = {
    enable = mkEnableOption "Advanced Project Type Detection System";

    enableAutoSetup = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic project environment setup";
    };

    supportedTypes = mkOption {
      type = types.listOf types.str;
      default = [
        "nextjs" "react" "nodejs" "typescript" "rust" "go" "python"
        "java" "kotlin" "php" "ruby" "cpp" "csharp" "swift" "dart" "flutter"
        "terraform" "ansible" "kubernetes" "docker"
      ];
      description = "List of supported project types";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      projectDetectionScript
    ] ++ optionals cfg.enableAutoSetup [
      projectEnvScript
    ];

    programs.zsh.shellAliases = mkIf cfg.enable {
      "project-type" = "detect-project-type";
      "project-info" = "detect-project-type . verbose";
      "project-json" = "detect-project-type . json";
      "setup-project" = "setup-project-env";
    };

    programs.bash.shellAliases = mkIf cfg.enable {
      "project-type" = "detect-project-type";
      "project-info" = "detect-project-type . verbose";
      "project-json" = "detect-project-type . json";
      "setup-project" = "setup-project-env";
    };
  };
}