{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.automation.cicd;
in
{
  options.dotfiles.automation.cicd = {
    enable = mkEnableOption "CI/CD Pipeline automation";
    
    githubActionsSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GitHub Actions tools and templates";
    };
    
    gitlabCISupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GitLab CI tools";
    };
    
    jenkinsSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Jenkins tools";
    };
    
    tektonSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Tekton Pipelines support";
    };
    
    argocdSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable ArgoCD GitOps";
    };
    
    qualityGates = mkOption {
      type = types.bool;
      default = true;
      description = "Enable quality gates and code analysis";
    };
    
    securityScanning = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security scanning in pipelines";
    };
    
    containerRegistry = mkOption {
      type = types.bool;
      default = true;
      description = "Enable container registry tools";
    };
  };

  config = mkIf cfg.enable {
    # CI/CD tools
    home.packages = with pkgs; [
      # Git and version control
      git
      git-lfs
      gh  # GitHub CLI
      
      # Build tools
      just
      make
      
      # Container tools
      docker
      docker-compose
      buildah
      skopeo
      
      # Quality and testing
      shellcheck
      
    ] ++ optionals cfg.githubActionsSupport [
      act  # Run GitHub Actions locally
      actionlint
    ] ++ optionals cfg.gitlabCISupport [
      gitlab-runner
    ] ++ optionals cfg.argocdSupport [
      argocd
      argo-rollouts
    ] ++ optionals cfg.qualityGates [
      sonarqube-scanner
    ] ++ optionals cfg.securityScanning [
      trivy
      grype
      syft
    ];

    # GitHub Actions templates
    home.file.".github/workflow-templates" = mkIf cfg.githubActionsSupport {
      recursive = true;
      source = ./github-templates;
    };

    # CI/CD pipeline generator
    home.file."bin/cicd-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # CI/CD Pipeline Generator
        set -euo pipefail
        
        PROJECT_TYPE="''${1:-nodejs}"
        CI_PLATFORM="''${2:-github}"
        PROJECT_NAME="''${3:-$(basename $(pwd))}"
        
        echo "🚀 CI/CD Pipeline Initialization"
        echo "==============================="
        echo "Project Type: $PROJECT_TYPE"
        echo "CI Platform: $CI_PLATFORM"
        echo "Project Name: $PROJECT_NAME"
        echo ""
        
        case "$CI_PLATFORM" in
          "github")
            mkdir -p .github/workflows
            
            # Main CI workflow
            cat > .github/workflows/ci.yml << 'END_OF_WORKFLOW'
name: CI Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: \$\{\{ github.repository \}\}
        
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [18, 20]

    steps:
    - uses: actions/checkout@v4
        
            - name: Use Node.js \$\{\{ matrix.node-version \}\}
              uses: actions/setup-node@v4
              with:
                node-version: \$\{\{ matrix.node-version \}\}
                cache: 'npm'
        
            - name: Install dependencies
              run: npm ci
        
            - name: Run linting
              run: npm run lint
        
            - name: Run tests
              run: npm test
        
            - name: Run security audit
              run: npm audit --audit-level high
        
          quality-gate:
            runs-on: ubuntu-latest
            needs: test
            
            steps:
            - uses: actions/checkout@v4
              with:
                fetch-depth: 0
        
            - name: SonarCloud Scan
              uses: SonarSource/sonarcloud-github-action@master
              env:
                GITHUB_TOKEN: \$\{\{ secrets.GITHUB_TOKEN \}\}
                SONAR_TOKEN: \$\{\{ secrets.SONAR_TOKEN \}\}
        
          security-scan:
            runs-on: ubuntu-latest
            needs: test
            
            steps:
            - uses: actions/checkout@v4
        
            - name: Run Trivy vulnerability scanner
              uses: aquasecurity/trivy-action@master
              with:
                scan-type: 'fs'
                scan-ref: '.'
                format: 'sarif'
                output: 'trivy-results.sarif'
        
            - name: Upload Trivy scan results
              uses: github/codeql-action/upload-sarif@v3
              with:
                sarif_file: 'trivy-results.sarif'
        
          build:
            runs-on: ubuntu-latest
            needs: [test, quality-gate, security-scan]
            if: github.ref == 'refs/heads/main'
            
            permissions:
              contents: read
              packages: write
        
            steps:
            - uses: actions/checkout@v4
        
            - name: Log in to Container Registry
              uses: docker/login-action@v3
              with:
                registry: \$\{\{ env.REGISTRY \}\}
                username: \$\{\{ github.actor \}\}
                password: \$\{\{ secrets.GITHUB_TOKEN \}\}
        
            - name: Extract metadata
              id: meta
              uses: docker/metadata-action@v5
              with:
                images: \$\{\{ env.REGISTRY \}\}/\$\{\{ env.IMAGE_NAME \}\}
                tags: |
                  type=ref,event=branch
                  type=ref,event=pr
                  type=sha
        
            - name: Build and push Docker image
              uses: docker/build-push-action@v5
              with:
                context: .
                push: true
                tags: \$\{\{ steps.meta.outputs.tags \}\}
                labels: \$\{\{ steps.meta.outputs.labels \}\}
        
          deploy-staging:
            runs-on: ubuntu-latest
            needs: build
            if: github.ref == 'refs/heads/main'
            environment: staging
            
            steps:
            - uses: actions/checkout@v4
        
            - name: Deploy to staging
              run: |
                echo "Deploying to staging environment..."
                # Add your deployment commands here
        
          deploy-production:
            runs-on: ubuntu-latest
            needs: deploy-staging
            if: github.ref == 'refs/heads/main'
            environment: production
            
            steps:
            - uses: actions/checkout@v4
        
            - name: Deploy to production
              run: |
                echo "Deploying to production environment..."
                # Add your deployment commands here
        END_OF_WORKFLOW
            
            # Release workflow
            cat > .github/workflows/release.yml << 'EOF'
        name: Release
        
        on:
          push:
            tags:
              - 'v*.*.*'
        
        jobs:
          release:
            runs-on: ubuntu-latest
            permissions:
              contents: write
              packages: write
        
            steps:
            - uses: actions/checkout@v4
              with:
                fetch-depth: 0
        
            - name: Generate changelog
              id: changelog
              run: |
                # Generate changelog from git commits
                echo "changelog<<EOF" >> $GITHUB_OUTPUT
                git log --pretty=format:"- %s" $(git describe --tags --abbrev=0 HEAD~1)..HEAD >> $GITHUB_OUTPUT
                echo "EOF" >> $GITHUB_OUTPUT
        
            - name: Create Release
              uses: actions/create-release@v1
              env:
                GITHUB_TOKEN: \$\{\{ secrets.GITHUB_TOKEN \}\}
              with:
                tag_name: \$\{\{ github.ref_name \}\}
                release_name: Release \$\{\{ github.ref_name \}\}
                body: |
                  ## Changes
                  \$\{\{ steps.changelog.outputs.changelog \}\}
                draft: false
                prerelease: false
        EOF
            
            # Dependabot configuration
            cat > .github/dependabot.yml << 'EOF'
        version: 2
        updates:
          - package-ecosystem: "npm"
            directory: "/"
            schedule:
              interval: "weekly"
            open-pull-requests-limit: 10
        
          - package-ecosystem: "docker"
            directory: "/"
            schedule:
              interval: "weekly"
        
          - package-ecosystem: "github-actions"
            directory: "/"
            schedule:
              interval: "weekly"
        EOF
            
            echo "✅ GitHub Actions workflows created"
            ;;
            
          "gitlab")
            cat > .gitlab-ci.yml << 'EOF'
        stages:
          - test
          - quality
          - security
          - build
          - deploy
        
        variables:
          DOCKER_DRIVER: overlay2
          DOCKER_TLS_CERTDIR: "/certs"
        
        before_script:
          - echo "Starting CI/CD pipeline for $CI_PROJECT_NAME"
        
        test:
          stage: test
          image: node:18
          script:
            - npm ci
            - npm run lint
            - npm test
          coverage: '/Lines\s*:\s*(\d+\.\d+)%/'
          artifacts:
            reports:
              coverage_report:
                coverage_format: cobertura
                path: coverage/cobertura-coverage.xml
        
        quality:
          stage: quality
          image: sonarsource/sonar-scanner-cli:latest
          script:
            - sonar-scanner
          only:
            - main
            - merge_requests
        
        security:
          stage: security
          image: aquasec/trivy:latest
          script:
            - trivy fs --format table .
        
        build:
          stage: build
          image: docker:latest
          services:
            - docker:dind
          script:
            - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
            - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
          only:
            - main
        
        deploy_staging:
          stage: deploy
          image: alpine:latest
          script:
            - echo "Deploying to staging..."
          environment:
            name: staging
            url: https://staging.example.com
          only:
            - main
        
        deploy_production:
          stage: deploy
          image: alpine:latest
          script:
            - echo "Deploying to production..."
          environment:
            name: production
            url: https://example.com
          when: manual
          only:
            - main
        EOF
            
            echo "✅ GitLab CI configuration created"
            ;;
        esac
        
        # Create Dockerfile if it doesn't exist
        if [[ ! -f Dockerfile ]]; then
          case "$PROJECT_TYPE" in
            "nodejs")
              cat > Dockerfile << 'EOF'
        FROM node:18-alpine AS base
        
        # Install dependencies only when needed
        FROM base AS deps
        WORKDIR /app
        COPY package.json package-lock.json* ./
        RUN npm ci --only=production && npm cache clean --force
        
        # Rebuild the source code only when needed
        FROM base AS builder
        WORKDIR /app
        COPY package.json package-lock.json* ./
        RUN npm ci
        COPY . .
        RUN npm run build
        
        # Production image, copy all the files and run next
        FROM base AS runner
        WORKDIR /app
        
        ENV NODE_ENV production
        
        RUN addgroup --system --gid 1001 nodejs
        RUN adduser --system --uid 1001 nextjs
        
        COPY --from=deps --chown=nextjs:nodejs /app/node_modules ./node_modules
        COPY --from=builder --chown=nextjs:nodejs /app/dist ./dist
        COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
        
        USER nextjs
        
        EXPOSE 3000
        
        ENV PORT 3000
        
        CMD ["npm", "start"]
        EOF
              ;;
              
            "python")
              cat > Dockerfile << 'EOF'
        FROM python:3.11-slim AS base
        
        # Set environment variables
        ENV PYTHONDONTWRITEBYTECODE=1 \
            PYTHONUNBUFFERED=1 \
            PIP_NO_CACHE_DIR=1 \
            PIP_DISABLE_PIP_VERSION_CHECK=1
        
        # Install system dependencies
        RUN apt-get update && apt-get install -y \
            gcc \
            && rm -rf /var/lib/apt/lists/*
        
        # Create user
        RUN groupadd -r appuser && useradd -r -g appuser appuser
        
        # Set work directory
        WORKDIR /app
        
        # Install Python dependencies
        COPY requirements.txt .
        RUN pip install --no-cache-dir -r requirements.txt
        
        # Copy project
        COPY . .
        
        # Change ownership of the app directory
        RUN chown -R appuser:appuser /app
        USER appuser
        
        # Expose port
        EXPOSE 8000
        
        # Run the application
        CMD ["python", "app.py"]
        EOF
              ;;
          esac
          
          echo "✅ Dockerfile created for $PROJECT_TYPE"
        fi
        
        # Create docker-compose for local development
        if [[ ! -f docker-compose.yml ]]; then
          cat > docker-compose.yml << EOF
        version: '3.8'
        
        services:
          app:
            build: .
            ports:
              - "3000:3000"
            environment:
              - NODE_ENV=development
            volumes:
              - .:/app
              - /app/node_modules
            depends_on:
              - redis
              - postgres
        
          redis:
            image: redis:7-alpine
            ports:
              - "6379:6379"
        
          postgres:
            image: postgres:15-alpine
            environment:
              POSTGRES_DB: $PROJECT_NAME
              POSTGRES_USER: postgres
              POSTGRES_PASSWORD: postgres
            ports:
              - "5432:5432"
            volumes:
              - postgres_data:/var/lib/postgresql/data
        
        volumes:
          postgres_data:
        EOF
          
          echo "✅ Docker Compose configuration created"
        fi
        
        echo ""
        echo "🎉 CI/CD pipeline initialization completed!"
        echo ""
        echo "Next steps:"
        echo "1. Review and customize the generated configurations"
        echo "2. Set up required secrets in your CI/CD platform"
        echo "3. Configure deployment targets"
        echo "4. Test the pipeline with a commit"
      '';
    };

    # Monitoring and logging tools
    home.file."bin/cicd-monitor" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # CI/CD Pipeline Monitoring
        set -euo pipefail
        
        COMMAND="''${1:-status}"
        
        case "$COMMAND" in
          "status")
            echo "📊 CI/CD Pipeline Status"
            echo "======================="
            
            # GitHub Actions status
            ${if cfg.githubActionsSupport then ''
              if command -v gh &> /dev/null && gh auth status &> /dev/null; then
                echo "🔄 GitHub Actions:"
                gh run list --limit 5 --json status,conclusion,workflowName,createdAt \
                  --template '{{range .}}{{.workflowName}}: {{.status}} ({{.conclusion}}) - {{timeago .createdAt}}{{"\n"}}{{end}}'
                echo ""
              fi
            '' else ""}
            
            # ArgoCD status
            ${if cfg.argocdSupport then ''
              if command -v argocd &> /dev/null; then
                echo "🚀 ArgoCD Applications:"
                argocd app list -o wide 2>/dev/null || echo "  Not connected to ArgoCD server"
                echo ""
              fi
            '' else ""}
            
            # Local Docker status
            if command -v docker &> /dev/null; then
              echo "🐳 Local Containers:"
              docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Docker not running"
            fi
            ;;
            
          "logs")
            local service="''${2:-all}"
            echo "📋 CI/CD Logs for: $service"
            
            if [[ "$service" == "github" ]] || [[ "$service" == "all" ]]; then
              ${if cfg.githubActionsSupport then ''
                if command -v gh &> /dev/null; then
                  echo "🔄 GitHub Actions Logs:"
                  gh run list --limit 1 --json databaseId \
                    --template '{{range .}}{{.databaseId}}{{end}}' | \
                    xargs -I {} gh run view {} --log
                fi
              '' else ""}
            fi
            ;;
            
          "metrics")
            echo "📈 CI/CD Metrics"
            echo "==============="
            
            # Pipeline success rate
            ${if cfg.githubActionsSupport then ''
              if command -v gh &> /dev/null; then
                echo "🎯 GitHub Actions Success Rate (last 10 runs):"
                TOTAL=$(gh run list --limit 10 --json conclusion | jq length)
                SUCCESS=$(gh run list --limit 10 --json conclusion | jq '[.[] | select(.conclusion == "success")] | length')
                if [[ $TOTAL -gt 0 ]]; then
                  RATE=$(echo "scale=1; $SUCCESS * 100 / $TOTAL" | bc)
                  echo "  Success: $SUCCESS/$TOTAL ($RATE%)"
                else
                  echo "  No recent runs found"
                fi
                echo ""
              fi
            '' else ""}
            
            # Build times
            echo "⏱️  Average Build Times:"
            echo "  (Use your CI/CD platform's analytics for detailed metrics)"
            ;;
            
          "health")
            echo "🏥 CI/CD Health Check"
            echo "===================="
            
            ISSUES=0
            
            # Check GitHub Actions
            ${if cfg.githubActionsSupport then ''
              if command -v gh &> /dev/null; then
                if gh auth status &> /dev/null; then
                  echo "✅ GitHub CLI: Authenticated"
                  
                  # Check for failed workflows
                  FAILED=$(gh run list --limit 5 --json conclusion | jq '[.[] | select(.conclusion == "failure")] | length')
                  if [[ $FAILED -gt 0 ]]; then
                    echo "⚠️  GitHub Actions: $FAILED recent failures"
                    ((ISSUES++))
                  else
                    echo "✅ GitHub Actions: No recent failures"
                  fi
                else
                  echo "❌ GitHub CLI: Not authenticated"
                  ((ISSUES++))
                fi
              else
                echo "⚪ GitHub CLI: Not installed"
              fi
            '' else ""}
            
            # Check Docker
            if command -v docker &> /dev/null; then
              if docker info &> /dev/null; then
                echo "✅ Docker: Running"
              else
                echo "❌ Docker: Not running"
                ((ISSUES++))
              fi
            else
              echo "⚪ Docker: Not installed"
            fi
            
            # Check container registry access
            ${if cfg.containerRegistry then ''
              echo ""
              echo "🏪 Container Registry Access:"
              if docker info | grep -q "Registry:"; then
                echo "✅ Registry: Configured"
              else
                echo "⚠️  Registry: Check authentication"
              fi
            '' else ""}
            
            echo ""
            if [[ $ISSUES -eq 0 ]]; then
              echo "✅ CI/CD health: Good"
            else
              echo "⚠️  CI/CD health: $ISSUES issues found"
            fi
            ;;
            
          *)
            echo "Usage: cicd-monitor <command>"
            echo ""
            echo "Commands:"
            echo "  status    Show pipeline status"
            echo "  logs      Show recent logs"
            echo "  metrics   Show pipeline metrics"
            echo "  health    Perform health check"
            ;;
        esac
      '';
    };

    # Shell aliases for CI/CD
    programs.zsh.shellAliases = {
      # GitHub Actions
      gha = mkIf cfg.githubActionsSupport "gh run list";
      gha-watch = mkIf cfg.githubActionsSupport "gh run watch";
      gha-logs = mkIf cfg.githubActionsSupport "gh run view --log";
      
      # Docker shortcuts
      d = "docker";
      dc = "docker-compose";
      dps = "docker ps";
      dl = "docker logs";
      
      # CI/CD management
      cicd = "cicd-monitor";
      pipeline = "cicd-monitor status";
    };

    # Shell functions for CI/CD
    programs.zsh.initContent = ''
      # Quick pipeline trigger
      trigger-pipeline() {
        local branch="''${1:-$(git branch --show-current)}"
        
        echo "🚀 Triggering pipeline for branch: $branch"
        
        if git status --porcelain | grep -q .; then
          echo "⚠️  You have uncommitted changes"
          read -p "Commit changes first? (y/N): " -n 1 -r
          echo
          if [[ $REPLY =~ ^[Yy]$ ]]; then
            git add .
            git commit -m "Auto-commit before pipeline trigger"
          fi
        fi
        
        git push origin "$branch"
        
        ${if cfg.githubActionsSupport then ''
          if command -v gh &> /dev/null; then
            echo "📋 Watching pipeline..."
            sleep 5
            gh run watch
          fi
        '' else ""}
      }
      
      # Pipeline status overview
      pipeline-overview() {
        echo "📊 Pipeline Overview"
        echo "=================="
        
        # Current branch info
        if git rev-parse --git-dir > /dev/null 2>&1; then
          echo "🌿 Branch: $(git branch --show-current)"
          echo "📝 Last commit: $(git log -1 --pretty=format:'%h - %s')"
          echo ""
        fi
        
        # CI/CD status
        cicd-monitor status
      }
      
      # Quick deployment
      deploy-env() {
        local env="''${1:-staging}"
        local confirm="''${2:-prompt}"
        
        echo "🚀 Deploying to: $env"
        
        if [[ "$confirm" == "prompt" ]]; then
          read -p "Continue with deployment to $env? (y/N): " -n 1 -r
          echo
          if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled"
            return 1
          fi
        fi
        
        case "$env" in
          "staging")
            echo "Deploying to staging environment..."
            # Add staging deployment commands
            ;;
          "production")
            echo "Deploying to production environment..."
            echo "⚠️  Production deployment requires manual approval"
            # Add production deployment commands
            ;;
          *)
            echo "Unknown environment: $env"
            return 1
            ;;
        esac
      }
    '';
  };
}