# Next.js Fullstack Development Environment
# Complete setup for modern React development with TypeScript, databases, and deployment tools

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
  setupScript = pkgs.writeShellScriptBin "setup-nextjs" ''
    set -e
    
    echo "🚀 Setting up Next.js fullstack development environment..."
    
    # Install global tools
    npm install -g create-next-app@latest
    npm install -g vercel@latest
    npm install -g prisma@latest
    npm install -g @next/codemod@latest
    
    # Verify installations
    echo "🔍 Verifying installations..."
    node --version
    npm --version
    npx --version
    
    # Database setup help
    echo ""
    echo "📊 Database setup:"
    echo "  PostgreSQL: $(which psql)"
    echo "  Redis: $(which redis-server)"
    echo "  Create database: createdb myapp_dev"
    echo ""
    echo "🎯 Quick start:"
    echo "  npx create-next-app@latest myapp --typescript --tailwind --eslint --app --src-dir --import-alias '@/*'"
    echo "  cd myapp"
    echo "  npm run dev"
    echo ""
    echo "✅ Next.js environment ready!"
  '';

  devScript = pkgs.writeShellScriptBin "nextjs-dev" ''
    case "$1" in
      create)
        echo "🆕 Creating new Next.js project..."
        npx create-next-app@latest "$2" --typescript --tailwind --eslint --app --src-dir --import-alias '@/*'
        ;;
      dev)
        echo "🔥 Starting development server..."
        npm run dev
        ;;
      build)
        echo "🏗️ Building for production..."
        npm run build
        ;;
      start)
        echo "🚀 Starting production server..."
        npm run start
        ;;
      db:generate)
        echo "🗃️ Generating Prisma client..."
        npx prisma generate
        ;;
      db:migrate)
        echo "🔄 Running database migrations..."
        npx prisma migrate dev
        ;;
      db:studio)
        echo "👀 Opening Prisma Studio..."
        npx prisma studio
        ;;
      db:reset)
        echo "🔄 Resetting database..."
        npx prisma migrate reset
        ;;
      deploy)
        echo "🚀 Deploying to Vercel..."
        vercel --prod
        ;;
      lint)
        echo "🔍 Running ESLint..."
        npm run lint
        ;;
      type-check)
        echo "🔧 Running TypeScript check..."
        npm run type-check
        ;;
      test)
        echo "🧪 Running tests..."
        npm test
        ;;
      clean)
        echo "🧹 Cleaning project..."
        rm -rf .next
        rm -rf node_modules
        npm install
        ;;
      *)
        echo "🌐 Next.js Development Commands"
        echo ""
        echo "Usage: nextjs-dev <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create <name>  Create new Next.js project"
        echo "  dev           Start development server"
        echo "  build         Build for production"
        echo "  start         Start production server"
        echo "  db:generate   Generate Prisma client"
        echo "  db:migrate    Run database migrations"
        echo "  db:studio     Open Prisma Studio"
        echo "  db:reset      Reset database"
        echo "  deploy        Deploy to Vercel"
        echo "  lint          Run ESLint"
        echo "  type-check    Run TypeScript check"
        echo "  test          Run tests"
        echo "  clean         Clean project"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "nextjs-fullstack-dev";
  
  buildInputs = with pkgs; [
    # Core development tools
    nodejs_20
    npm
    yarn
    pnpm
    git
    
    # Database systems
    postgresql
    redis
    sqlite
    
    # Development utilities
    setupScript
    devScript
    
    # Build and deployment tools
    docker
    docker-compose
    
    # Additional tools
    jq
    curl
    openssl
    
    # Language servers and formatters
    nodePackages.typescript-language-server
    nodePackages.prettier
    nodePackages.eslint
  ];

  shellHook = ''
    # PostgreSQL setup
    export PGDATA="$PWD/.postgres"
    export PGHOST="localhost"
    export PGPORT="5432"
    export PGUSER="postgres"
    
    # Redis setup
    export REDIS_URL="redis://localhost:6379"
    
    # Next.js environment
    export NODE_ENV="development"
    export NEXT_TELEMETRY_DISABLED=1
    
    # Initialize PostgreSQL if not exists
    if [ ! -d "$PGDATA" ]; then
      echo "🗄️ Initializing PostgreSQL database..."
      initdb "$PGDATA" --auth-host=trust --auth-local=trust
      echo "port = $PGPORT" >> "$PGDATA/postgresql.conf"
    fi
    
    # Auto-start services function
    start_services() {
      echo "🚀 Starting development services..."
      
      # Start PostgreSQL
      if ! pg_ctl status > /dev/null 2>&1; then
        pg_ctl start -l "$PGDATA/server.log"
        echo "✅ PostgreSQL started on port $PGPORT"
      fi
      
      # Start Redis
      if ! redis-cli ping > /dev/null 2>&1; then
        redis-server --daemonize yes --port 6379
        echo "✅ Redis started on port 6379"
      fi
    }
    
    # Auto-stop services function
    stop_services() {
      echo "🛑 Stopping development services..."
      
      # Stop PostgreSQL
      if pg_ctl status > /dev/null 2>&1; then
        pg_ctl stop
        echo "✅ PostgreSQL stopped"
      fi
      
      # Stop Redis
      if redis-cli ping > /dev/null 2>&1; then
        redis-cli shutdown
        echo "✅ Redis stopped"
      fi
    }
    
    # Cleanup on shell exit
    trap stop_services EXIT
    
    echo "🌐 Next.js Fullstack Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Node.js: $(node --version)"
    echo "🗄️ PostgreSQL: $(postgres --version | head -n1)"
    echo "🔴 Redis: $(redis-server --version)"
    echo "🐳 Docker: $(docker --version)"
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-nextjs      # Initial environment setup"
    echo "  nextjs-dev        # Development commands"
    echo "  start_services    # Start PostgreSQL and Redis"
    echo "  stop_services     # Stop PostgreSQL and Redis"
    echo ""
    echo "📚 Quick start:"
    echo "  start_services"
    echo "  nextjs-dev create myapp"
    echo "  cd myapp && nextjs-dev dev"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';
}