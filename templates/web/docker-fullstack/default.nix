# Docker Fullstack Development Environment
# Complete setup for containerized application development with multi-service orchestration

{ pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  }
, lib ? pkgs.lib
, stdenv ? pkgs.stdenv
}:

let
  # Development scripts
  setupScript = pkgs.writeShellScriptBin "setup-docker-stack" ''
    set -e
    
    echo "🚀 Setting up Docker fullstack development environment..."
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
      echo "❌ Docker not found. Please install Docker first."
      exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
      echo "❌ Docker Compose not found. Please install Docker Compose first."
      exit 1
    fi
    
    # Install additional tools
    npm install -g @docker/compose@latest || true
    
    # Verify installations
    echo "🔍 Verifying installations..."
    docker --version
    docker-compose --version
    
    echo ""
    echo "🎯 Quick start:"
    echo "  docker-dev init    # Initialize project structure"
    echo "  docker-dev up      # Start all services"
    echo "  docker-dev logs    # View logs"
    echo ""
    echo "✅ Docker environment ready!"
  '';

  devScript = pkgs.writeShellScriptBin "docker-dev" ''
    case "$1" in
      init)
        echo "🆕 Initializing Docker fullstack project..."
        
        # Create project structure
        mkdir -p {frontend,backend,database,nginx,scripts}
        
        # Create docker-compose.yml
        cat > docker-compose.yml << 'EOF'
    version: '3.8'
    
    services:
      # Frontend (React/Vue/Angular)
      frontend:
        build:
          context: ./frontend
          dockerfile: Dockerfile
        ports:
          - "3000:3000"
        volumes:
          - ./frontend:/app
          - /app/node_modules
        environment:
          - NODE_ENV=development
          - REACT_APP_API_URL=http://localhost:8000
        depends_on:
          - backend
    
      # Backend API (Node.js/Python/Go)
      backend:
        build:
          context: ./backend
          dockerfile: Dockerfile
        ports:
          - "8000:8000"
        volumes:
          - ./backend:/app
        environment:
          - NODE_ENV=development
          - DATABASE_URL=postgresql://postgres:password@postgres:5432/appdb
          - REDIS_URL=redis://redis:6379
        depends_on:
          - postgres
          - redis
    
      # PostgreSQL Database
      postgres:
        image: postgres:15-alpine
        ports:
          - "5432:5432"
        environment:
          - POSTGRES_DB=appdb
          - POSTGRES_USER=postgres
          - POSTGRES_PASSWORD=password
        volumes:
          - postgres_data:/var/lib/postgresql/data
          - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql
    
      # Redis Cache
      redis:
        image: redis:7-alpine
        ports:
          - "6379:6379"
        volumes:
          - redis_data:/data
    
      # Nginx Reverse Proxy
      nginx:
        image: nginx:alpine
        ports:
          - "80:80"
          - "443:443"
        volumes:
          - ./nginx/nginx.conf:/etc/nginx/nginx.conf
          - ./nginx/certs:/etc/nginx/certs
        depends_on:
          - frontend
          - backend
    
    volumes:
      postgres_data:
      redis_data:
    
    networks:
      default:
        name: fullstack_network
    EOF
        
        # Create .env file
        cat > .env << 'EOF'
    # Environment Configuration
    NODE_ENV=development
    
    # Database
    POSTGRES_DB=appdb
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=password
    DATABASE_URL=postgresql://postgres:password@localhost:5432/appdb
    
    # Redis
    REDIS_URL=redis://localhost:6379
    
    # API
    API_PORT=8000
    API_URL=http://localhost:8000
    
    # Frontend
    FRONTEND_PORT=3000
    REACT_APP_API_URL=http://localhost:8000
    EOF
        
        # Create basic Dockerfiles
        mkdir -p frontend backend
        
        cat > frontend/Dockerfile << 'EOF'
    FROM node:18-alpine
    
    WORKDIR /app
    
    COPY package*.json ./
    RUN npm install
    
    COPY . .
    
    EXPOSE 3000
    
    CMD ["npm", "start"]
    EOF
        
        cat > backend/Dockerfile << 'EOF'
    FROM node:18-alpine
    
    WORKDIR /app
    
    COPY package*.json ./
    RUN npm install
    
    COPY . .
    
    EXPOSE 8000
    
    CMD ["npm", "run", "dev"]
    EOF
        
        echo "✅ Project structure initialized!"
        ;;
      up)
        echo "🚀 Starting all services..."
        docker-compose up -d
        ;;
      down)
        echo "🛑 Stopping all services..."
        docker-compose down
        ;;
      restart)
        echo "🔄 Restarting all services..."
        docker-compose restart
        ;;
      logs)
        echo "📋 Viewing logs..."
        if [ -n "$2" ]; then
          docker-compose logs -f "$2"
        else
          docker-compose logs -f
        fi
        ;;
      build)
        echo "🏗️ Building all services..."
        docker-compose build
        ;;
      rebuild)
        echo "🔨 Rebuilding all services..."
        docker-compose build --no-cache
        ;;
      ps)
        echo "📋 Listing running containers..."
        docker-compose ps
        ;;
      exec)
        echo "🔧 Executing command in container..."
        docker-compose exec "$2" "${@:3}"
        ;;
      shell)
        echo "🐚 Opening shell in container..."
        docker-compose exec "$2" /bin/sh
        ;;
      clean)
        echo "🧹 Cleaning up..."
        docker-compose down -v
        docker system prune -f
        ;;
      db:migrate)
        echo "🗃️ Running database migrations..."
        docker-compose exec backend npm run db:migrate
        ;;
      db:seed)
        echo "🌱 Seeding database..."
        docker-compose exec backend npm run db:seed
        ;;
      backup)
        echo "💾 Creating database backup..."
        docker-compose exec postgres pg_dump -U postgres appdb > backup_$(date +%Y%m%d_%H%M%S).sql
        ;;
      restore)
        echo "📥 Restoring database from backup..."
        if [ -n "$2" ]; then
          docker-compose exec -T postgres psql -U postgres appdb < "$2"
        else
          echo "Usage: docker-dev restore <backup_file>"
        fi
        ;;
      *)
        echo "🐳 Docker Fullstack Development Commands"
        echo ""
        echo "Usage: docker-dev <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init             Initialize project structure"
        echo "  up               Start all services"
        echo "  down             Stop all services"
        echo "  restart          Restart all services"
        echo "  logs [service]   View logs (all or specific service)"
        echo "  build            Build all services"
        echo "  rebuild          Rebuild all services (no cache)"
        echo "  ps               List running containers"
        echo "  exec <service>   Execute command in container"
        echo "  shell <service>  Open shell in container"
        echo "  clean            Clean up containers and volumes"
        echo "  db:migrate       Run database migrations"
        echo "  db:seed          Seed database"
        echo "  backup           Create database backup"
        echo "  restore <file>   Restore database from backup"
        echo ""
        echo "Examples:"
        echo "  docker-dev up"
        echo "  docker-dev logs frontend"
        echo "  docker-dev exec backend npm test"
        echo "  docker-dev shell postgres"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "docker-fullstack-dev";
  
  buildInputs = with pkgs; [
    # Core development tools
    git
    
    # Container tools
    docker
    docker-compose
    docker-buildx
    
    # Development utilities
    setupScript
    devScript
    
    # Monitoring and debugging
    ctop
    dive
    
    # Additional tools
    jq
    curl
    netcat-gnu
    
    # Optional: Node.js for development
    nodejs_20
    npm
  ];

  shellHook = ''
    # Docker environment
    export DOCKER_BUILDKIT=1
    export COMPOSE_DOCKER_CLI_BUILD=1
    
    # Development environment
    export NODE_ENV="development"
    
    # Check Docker daemon
    if ! docker info > /dev/null 2>&1; then
      echo "⚠️  Docker daemon is not running. Please start Docker first."
    fi
    
    echo "🐳 Docker Fullstack Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐳 Docker: $(docker --version)"
    echo "🔧 Compose: $(docker-compose --version)"
    echo "📊 ctop: Container monitoring tool available"
    echo "🔍 dive: Image analysis tool available"
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-docker-stack  # Initial environment setup"
    echo "  docker-dev          # Development commands"
    echo ""
    echo "📚 Quick start:"
    echo "  docker-dev init     # Initialize project"
    echo "  docker-dev up       # Start all services"
    echo "  docker-dev logs     # View logs"
    echo ""
    echo "🔧 Useful commands:"
    echo "  ctop                # Monitor containers"
    echo "  dive <image>        # Analyze image layers"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';
}