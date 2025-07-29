# Web Development Deployment Automation
# Advanced deployment pipelines and infrastructure management

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.web.deployment;
in
{
  options.dotfiles.development.web.deployment = {
    enable = mkEnableOption "Web development deployment automation";
    
    profile = mkOption {
      type = types.enum [ "development" "staging" "production" "enterprise" ];
      default = "development";
      description = "Deployment environment profile";
    };
    
    features = {
      containerization = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Docker containerization";
      };
      
      orchestration = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Kubernetes orchestration";
      };
      
      zeroDowntime = mkOption {
        type = types.bool;
        default = true;
        description = "Enable zero-downtime deployment strategies";
      };
      
      rollback = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic rollback capabilities";
      };
      
      monitoring = mkOption {
        type = types.bool;
        default = true;
        description = "Enable deployment monitoring and health checks";
      };
    };
    
    targets = mkOption {
      type = types.listOf (types.enum [ "vercel" "netlify" "aws" "gcp" "azure" "docker" "kubernetes" ]);
      default = [ "docker" "vercel" ];
      description = "Supported deployment targets";
    };
  };

  config = mkIf cfg.enable {
    # Deployment tools
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core deployment tools
      docker
      docker-compose
      
      # Cloud platform CLIs
      nodePackages.vercel
      nodePackages.netlify-cli
      awscli2
      google-cloud-sdk
      azure-cli
      
      # Infrastructure as Code
      terraform
      ansible
      
      # Container orchestration
    ] ++ optionals cfg.features.orchestration [
      kubectl
      kubernetes-helm
      kustomize
    ] ++ optionals cfg.features.monitoring [
      # Monitoring tools
      prometheus
      grafana
    ];

    # Docker configuration for web applications
    home-manager.users.yuki.home.file."Dockerfile.template" = mkIf cfg.features.containerization {
      text = ''
        # Multi-stage Dockerfile template for web applications
        # Optimized for Next.js, but adaptable for other frameworks
        
        ARG NODE_VERSION=20
        ARG ALPINE_VERSION=alpine3.19
        
        # Dependencies stage
        FROM node:$NODE_VERSION-$ALPINE_VERSION AS deps
        RUN apk add --no-cache libc6-compat
        WORKDIR /app
        
        # Copy package files
        COPY package.json pnpm-lock.yaml* ./
        COPY .npmrc* ./
        
        # Install dependencies
        RUN corepack enable pnpm && \
            pnpm install --frozen-lockfile --prod=false
        
        # Builder stage
        FROM node:$NODE_VERSION-$ALPINE_VERSION AS builder
        WORKDIR /app
        
        COPY --from=deps /app/node_modules ./node_modules
        COPY . .
        
        # Build application
        ENV NODE_ENV=production
        ENV NEXT_TELEMETRY_DISABLED=1
        
        RUN corepack enable pnpm && \
            pnpm build
        
        # Production stage
        FROM node:$NODE_VERSION-$ALPINE_VERSION AS runner
        WORKDIR /app
        
        ENV NODE_ENV=production
        ENV NEXT_TELEMETRY_DISABLED=1
        
        # Create non-root user
        RUN addgroup --system --gid 1001 nodejs && \
            adduser --system --uid 1001 nextjs
        
        # Copy build artifacts
        COPY --from=builder /app/public ./public
        COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
        COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
        
        USER nextjs
        
        EXPOSE 3000
        ENV PORT=3000
        ENV HOSTNAME="0.0.0.0"
        
        # Health check
        HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
          CMD curl -f http://localhost:3000/api/health || exit 1
        
        CMD ["node", "server.js"]
      '';
    };

    # Docker Compose for development and production
    home-manager.users.yuki.home.file."docker-compose.yml" = mkIf cfg.features.containerization {
      text = ''
        version: '3.8'
        
        services:
          web:
            build:
              context: .
              dockerfile: Dockerfile
              target: runner
            ports:
              - "3000:3000"
            environment:
              - NODE_ENV=production
              - DATABASE_URL=$DATABASE_URL
              - REDIS_URL=$REDIS_URL
            depends_on:
              - db
              - redis
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
              interval: 30s
              timeout: 10s
              retries: 3
              start_period: 40s
        
          db:
            image: postgres:16-alpine
            environment:
              POSTGRES_DB: myapp
              POSTGRES_USER: postgres
              POSTGRES_PASSWORD: postgres
            volumes:
              - postgres_data:/var/lib/postgresql/data
            ports:
              - "5432:5432"
            restart: unless-stopped
        
          redis:
            image: redis:7-alpine
            ports:
              - "6379:6379"
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "redis-cli", "ping"]
              interval: 30s
              timeout: 3s
              retries: 3
        
        volumes:
          postgres_data:
        
        networks:
          default:
            driver: bridge
      '';
    };

    # Production Docker Compose with load balancing
    home-manager.users.yuki.home.file."docker-compose.prod.yml" = mkIf (cfg.features.containerization && cfg.features.zeroDowntime) {
      text = ''
        version: '3.8'
        
        services:
          nginx:
            image: nginx:alpine
            ports:
              - "80:80"
              - "443:443"
            volumes:
              - ./nginx.conf:/etc/nginx/nginx.conf:ro
              - ./ssl:/etc/nginx/ssl:ro
            depends_on:
              - web-1
              - web-2
            restart: unless-stopped
        
          web-1:
            build:
              context: .
              dockerfile: Dockerfile
              target: runner
            environment:
              - NODE_ENV=production
              - DATABASE_URL=$DATABASE_URL
              - REDIS_URL=$REDIS_URL
              - INSTANCE_ID=web-1
            depends_on:
              - db
              - redis
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
              interval: 30s
              timeout: 10s
              retries: 3
              start_period: 40s
        
          web-2:
            build:
              context: .
              dockerfile: Dockerfile
              target: runner
            environment:
              - NODE_ENV=production
              - DATABASE_URL=$DATABASE_URL
              - REDIS_URL=$REDIS_URL
              - INSTANCE_ID=web-2
            depends_on:
              - db
              - redis
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
              interval: 30s
              timeout: 10s
              retries: 3
              start_period: 40s
        
          db:
            image: postgres:16-alpine
            environment:
              POSTGRES_DB: $DB_NAME
              POSTGRES_USER: $DB_USER
              POSTGRES_PASSWORD: $DB_PASSWORD
            volumes:
              - postgres_data:/var/lib/postgresql/data
              - ./db/init:/docker-entrypoint-initdb.d
            restart: unless-stopped
            healthcheck:
              test: ["CMD-SHELL", "pg_isready -U $DB_USER -d $DB_NAME"]
              interval: 30s
              timeout: 5s
              retries: 3
        
          redis:
            image: redis:7-alpine
            command: redis-server --requirepass $REDIS_PASSWORD
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "redis-cli", "--pass", "$REDIS_PASSWORD", "ping"]
              interval: 30s
              timeout: 3s
              retries: 3
        
        volumes:
          postgres_data:
        
        networks:
          default:
            driver: bridge
      '';
    };

    # Nginx configuration for load balancing
    home-manager.users.yuki.home.file."nginx.conf" = mkIf cfg.features.zeroDowntime {
      text = ''
        events {
            worker_connections 1024;
        }
        
        http {
            upstream web_backend {
                least_conn;
                server web-1:3000 max_fails=3 fail_timeout=30s;
                server web-2:3000 max_fails=3 fail_timeout=30s;
            }
        
            server {
                listen 80;
                server_name localhost;
        
                # Health check endpoint
                location /health {
                    access_log off;
                    return 200 "healthy\n";
                    add_header Content-Type text/plain;
                }
        
                # Main application
                location / {
                    proxy_pass http://web_backend;
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    
                    # Timeouts
                    proxy_connect_timeout 30s;
                    proxy_send_timeout 30s;
                    proxy_read_timeout 30s;
                    
                    # Health check
                    proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
                }
        
                # Static files (if serving from nginx)
                location /_next/static/ {
                    proxy_pass http://web_backend;
                    proxy_cache_valid 200 1y;
                    add_header Cache-Control "public, immutable";
                }
            }
        }
      '';
    };

    # Deployment scripts
    home-manager.users.yuki.home.file."bin/deploy" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        ENVIRONMENT="''${1:-development}"
        STRATEGY="''${2:-rolling}"
        
        echo "🚀 Deploying to $ENVIRONMENT using $STRATEGY strategy"
        
        case "$ENVIRONMENT" in
          development)
            deploy_development
            ;;
          staging)
            deploy_staging
            ;;
          production)
            deploy_production "$STRATEGY"
            ;;
          *)
            echo "❌ Unknown environment: $ENVIRONMENT"
            exit 1
            ;;
        esac
        
        deploy_development() {
          echo "📦 Building development environment..."
          docker-compose down
          docker-compose build
          docker-compose up -d
          
          echo "🔍 Running health checks..."
          sleep 10
          curl -f http://localhost:3000/api/health || {
            echo "❌ Health check failed"
            docker-compose logs web
            exit 1
          }
          
          echo "✅ Development deployment completed"
        }
        
        deploy_staging() {
          echo "📦 Building staging environment..."
          
          # Build and tag
          docker build -t myapp:staging .
          docker tag myapp:staging myapp:latest
          
          # Deploy with staging compose
          docker-compose -f docker-compose.staging.yml down
          docker-compose -f docker-compose.staging.yml up -d
          
          # Health checks
          wait_for_health "http://staging.localhost:3000/api/health"
          
          echo "✅ Staging deployment completed"
        }
        
        deploy_production() {
          local strategy="$1"
          
          case "$strategy" in
            blue-green)
              deploy_blue_green
              ;;
            rolling)
              deploy_rolling
              ;;
            canary)
              deploy_canary
              ;;
            *)
              echo "❌ Unknown deployment strategy: $strategy"
              exit 1
              ;;
          esac
        }
        
        deploy_blue_green() {
          echo "🔵 Starting Blue-Green deployment..."
          
          # Build new version
          docker build -t myapp:new .
          
          # Deploy to green environment
          docker-compose -f docker-compose.green.yml down
          docker-compose -f docker-compose.green.yml up -d
          
          # Health check green environment
          wait_for_health "http://green.localhost:3000/api/health"
          
          # Switch traffic (update load balancer)
          echo "🔀 Switching traffic to green environment..."
          docker-compose -f docker-compose.prod.yml exec nginx nginx -s reload
          
          # Health check after switch
          wait_for_health "http://localhost:3000/api/health"
          
          # Cleanup old environment
          docker-compose -f docker-compose.blue.yml down
          
          echo "✅ Blue-Green deployment completed"
        }
        
        deploy_rolling() {
          echo "🔄 Starting Rolling deployment..."
          
          # Build new version
          docker build -t myapp:new .
          
          # Update instances one by one
          for instance in web-1 web-2; do
            echo "📦 Updating $instance..."
            
            # Stop instance
            docker-compose -f docker-compose.prod.yml stop $instance
            
            # Update and restart
            docker-compose -f docker-compose.prod.yml up -d $instance
            
            # Wait for health
            wait_for_instance_health "$instance"
            
            echo "✅ $instance updated successfully"
          done
          
          echo "✅ Rolling deployment completed"
        }
        
        deploy_canary() {
          echo "🐤 Starting Canary deployment..."
          
          # Build new version
          docker build -t myapp:canary .
          
          # Deploy canary instance
          docker-compose -f docker-compose.canary.yml up -d
          
          # Health check canary
          wait_for_health "http://canary.localhost:3000/api/health"
          
          # Gradual traffic increase (requires load balancer config)
          echo "📊 Starting gradual traffic migration..."
          for percentage in 10 25 50 75 100; do
            echo "🔀 Routing $percentage% traffic to canary..."
            update_traffic_split "$percentage"
            sleep 60
            
            # Monitor metrics
            if ! check_canary_metrics; then
              echo "❌ Canary metrics failed, rolling back..."
              rollback_canary
              exit 1
            fi
          done
          
          # Complete migration
          docker-compose -f docker-compose.prod.yml down
          docker-compose -f docker-compose.canary.yml up -d
          
          echo "✅ Canary deployment completed"
        }
        
        wait_for_health() {
          local url="$1"
          local retries=30
          local count=0
          
          while [ $count -lt $retries ]; do
            if curl -f "$url" >/dev/null 2>&1; then
              echo "✅ Health check passed"
              return 0
            fi
            
            echo "⏳ Waiting for health check... ($((count + 1))/$retries)"
            sleep 10
            count=$((count + 1))
          done
          
          echo "❌ Health check failed after $retries attempts"
          return 1
        }
        
        wait_for_instance_health() {
          local instance="$1"
          local container_ip
          container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(docker-compose -f docker-compose.prod.yml ps -q $instance)")
          
          wait_for_health "http://$container_ip:3000/api/health"
        }
        
        update_traffic_split() {
          local percentage="$1"
          # This would integrate with your load balancer
          # For example, updating nginx upstream weights
          echo "Traffic split updated to $percentage%"
        }
        
        check_canary_metrics() {
          # Check error rates, response times, etc.
          # This would integrate with your monitoring system
          echo "Canary metrics are healthy"
          return 0
        }
        
        rollback_canary() {
          echo "🔄 Rolling back canary deployment..."
          docker-compose -f docker-compose.canary.yml down
          update_traffic_split "0"
          echo "✅ Rollback completed"
        }
      '';
    };

    # Rollback script
    home-manager.users.yuki.home.file."bin/rollback" = mkIf cfg.features.rollback {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        ENVIRONMENT="''${1:-production}"
        VERSION="''${2:-previous}"
        
        echo "🔄 Rolling back $ENVIRONMENT to $VERSION"
        
        case "$ENVIRONMENT" in
          production)
            rollback_production "$VERSION"
            ;;
          staging)
            rollback_staging "$VERSION"
            ;;
          *)
            echo "❌ Rollback not supported for environment: $ENVIRONMENT"
            exit 1
            ;;
        esac
        
        rollback_production() {
          local version="$1"
          
          echo "🔍 Finding rollback target..."
          
          if [ "$version" = "previous" ]; then
            # Get previous working version
            version=$(docker images myapp --format "table {{.Tag}}" | grep -v TAG | head -2 | tail -1)
          fi
          
          if [ -z "$version" ]; then
            echo "❌ No rollback target found"
            exit 1
          fi
          
          echo "📦 Rolling back to version: $version"
          
          # Update compose file to use rollback version
          sed -i "s/image: myapp:.*/image: myapp:$version/" docker-compose.prod.yml
          
          # Deploy with rolling strategy to minimize downtime
          for instance in web-1 web-2; do
            echo "🔄 Rolling back $instance..."
            
            docker-compose -f docker-compose.prod.yml stop $instance
            docker-compose -f docker-compose.prod.yml up -d $instance
            
            # Wait for health
            wait_for_instance_health "$instance"
            
            echo "✅ $instance rolled back successfully"
          done
          
          # Verify rollback
          if wait_for_health "http://localhost:3000/api/health"; then
            echo "✅ Rollback completed successfully"
          else
            echo "❌ Rollback health check failed"
            exit 1
          fi
        }
        
        rollback_staging() {
          local version="$1"
          
          echo "🔄 Rolling back staging environment to $version"
          
          docker-compose -f docker-compose.staging.yml down
          docker tag "myapp:$version" myapp:staging
          docker-compose -f docker-compose.staging.yml up -d
          
          wait_for_health "http://staging.localhost:3000/api/health"
          
          echo "✅ Staging rollback completed"
        }
        
        wait_for_health() {
          local url="$1"
          local retries=30
          local count=0
          
          while [ $count -lt $retries ]; do
            if curl -f "$url" >/dev/null 2>&1; then
              echo "✅ Health check passed"
              return 0
            fi
            
            echo "⏳ Waiting for health check... ($((count + 1))/$retries)"
            sleep 10
            count=$((count + 1))
          done
          
          echo "❌ Health check failed after $retries attempts"
          return 1
        }
        
        wait_for_instance_health() {
          local instance="$1"
          local container_ip
          container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(docker-compose -f docker-compose.prod.yml ps -q $instance)")
          
          wait_for_health "http://$container_ip:3000/api/health"
        }
      '';
    };

    # Environment configuration templates
    home-manager.users.yuki.home.file.".env.example" = {
      text = ''
        # Application Configuration
        NODE_ENV=development
        PORT=3000
        APP_NAME=myapp
        APP_VERSION=1.0.0
        
        # Database Configuration
        DATABASE_URL=postgresql://postgres:postgres@localhost:5432/myapp
        DB_HOST=localhost
        DB_PORT=5432
        DB_NAME=myapp
        DB_USER=postgres
        DB_PASSWORD=postgres
        
        # Redis Configuration
        REDIS_URL=redis://localhost:6379
        REDIS_PASSWORD=
        
        # Authentication
        JWT_SECRET=your-super-secret-jwt-key
        SESSION_SECRET=your-session-secret
        
        # External Services
        GOOGLE_ANALYTICS_ID=
        SENTRY_DSN=
        
        # Feature Flags
        FEATURE_NEW_UI=false
        FEATURE_ANALYTICS=true
        FEATURE_MONITORING=true
        
        # Deployment
        DEPLOYMENT_STRATEGY=rolling
        HEALTH_CHECK_PATH=/api/health
        HEALTH_CHECK_TIMEOUT=30
        
        # Monitoring
        PROMETHEUS_METRICS=true
        LOG_LEVEL=info
      '';
    };

    # Health check API template
    home-manager.users.yuki.home.file."api/health/route.ts" = {
      text = ''
        import { NextRequest, NextResponse } from 'next/server';
        
        export async function GET(request: NextRequest) {
          try {
            // Check database connection
            const dbHealth = await checkDatabase();
            
            // Check Redis connection
            const redisHealth = await checkRedis();
            
            // Check external services
            const servicesHealth = await checkExternalServices();
            
            const health = {
              status: 'healthy',
              timestamp: new Date().toISOString(),
              uptime: process.uptime(),
              version: process.env.APP_VERSION || '1.0.0',
              environment: process.env.NODE_ENV || 'development',
              checks: {
                database: dbHealth,
                redis: redisHealth,
                services: servicesHealth,
              },
            };
            
            const allHealthy = Object.values(health.checks).every(check => check.status === 'healthy');
            
            return NextResponse.json(health, {
              status: allHealthy ? 200 : 503,
            });
          } catch (error) {
            return NextResponse.json({
              status: 'unhealthy',
              timestamp: new Date().toISOString(),
              error: error instanceof Error ? error.message : 'Unknown error',
            }, {
              status: 503,
            });
          }
        }
        
        async function checkDatabase() {
          try {
            // Replace with your actual database health check
            // Example: await prisma.$queryRaw`SELECT 1`;
            return { status: 'healthy', responseTime: 10 };
          } catch (error) {
            return { 
              status: 'unhealthy', 
              error: error instanceof Error ? error.message : 'Database connection failed' 
            };
          }
        }
        
        async function checkRedis() {
          try {
            // Replace with your actual Redis health check
            // Example: await redis.ping();
            return { status: 'healthy', responseTime: 5 };
          } catch (error) {
            return { 
              status: 'unhealthy', 
              error: error instanceof Error ? error.message : 'Redis connection failed' 
            };
          }
        }
        
        async function checkExternalServices() {
          try {
            // Check external APIs, services, etc.
            const checks = await Promise.allSettled([
              // Add your external service checks here
              // fetch('https://api.external-service.com/health'),
            ]);
            
            return { 
              status: 'healthy', 
              external: checks.length,
              healthy: checks.filter(result => result.status === 'fulfilled').length 
            };
          } catch (error) {
            return { 
              status: 'unhealthy', 
              error: error instanceof Error ? error.message : 'External services check failed' 
            };
          }
        }
      '';
    };

    # Shell aliases for deployment commands
    home-manager.users.yuki.programs.zsh.shellAliases = {
      "deploy-dev" = "deploy development";
      "deploy-staging" = "deploy staging";
      "deploy-prod" = "deploy production";
      "deploy-blue-green" = "deploy production blue-green";
      "deploy-canary" = "deploy production canary";
      "rollback-prod" = "rollback production";
      "rollback-staging" = "rollback staging";
    };

    # Environment variables for deployment
    home-manager.users.yuki.home.sessionVariables = {
      # Docker optimization
      DOCKER_BUILDKIT = "1";
      COMPOSE_DOCKER_CLI_BUILD = "1";
      
      # Deployment configuration
      DEPLOYMENT_STRATEGY = mkDefault "rolling";
      HEALTH_CHECK_TIMEOUT = mkDefault "30";
      ROLLBACK_ON_FAILURE = mkDefault "true";
    };
  };
}