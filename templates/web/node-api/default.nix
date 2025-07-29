# TypeScript Node.js API Development Environment
# Complete setup for backend API development with TypeScript, databases, and testing

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
  setupScript = pkgs.writeShellScriptBin "setup-node-api" ''
    set -e
    
    echo "🚀 Setting up TypeScript Node.js API development environment..."
    
    # Install global tools
    npm install -g typescript@latest
    npm install -g ts-node@latest
    npm install -g nodemon@latest
    npm install -g prisma@latest
    npm install -g pm2@latest
    
    # Verify installations
    echo "🔍 Verifying installations..."
    node --version
    npm --version
    tsc --version
    ts-node --version
    
    echo ""
    echo "🎯 Quick start:"
    echo "  mkdir myapi && cd myapi"
    echo "  npm init -y"
    echo "  npm install express @types/express typescript ts-node nodemon"
    echo "  api-dev init"
    echo "  api-dev dev"
    echo ""
    echo "✅ Node.js API environment ready!"
  '';

  devScript = pkgs.writeShellScriptBin "api-dev" ''
    case "$1" in
      init)
        echo "🆕 Initializing TypeScript Node.js API project..."
        
        # Create tsconfig.json
        cat > tsconfig.json << 'EOF'
    {
      "compilerOptions": {
        "target": "ES2022",
        "module": "commonjs",
        "lib": ["ES2022"],
        "outDir": "./dist",
        "rootDir": "./src",
        "strict": true,
        "moduleResolution": "node",
        "esModuleInterop": true,
        "skipLibCheck": true,
        "forceConsistentCasingInFileNames": true,
        "resolveJsonModule": true,
        "declaration": true,
        "declarationMap": true,
        "sourceMap": true,
        "experimentalDecorators": true,
        "emitDecoratorMetadata": true
      },
      "include": ["src/**/*"],
      "exclude": ["node_modules", "dist", "**/*.test.ts"]
    }
    EOF
        
        # Create basic package.json scripts
        npm pkg set scripts.dev="nodemon src/index.ts"
        npm pkg set scripts.build="tsc"
        npm pkg set scripts.start="node dist/index.js"
        npm pkg set scripts.test="jest"
        npm pkg set scripts.lint="eslint src/**/*.ts"
        npm pkg set scripts.format="prettier --write src/**/*.ts"
        
        # Create src directory structure
        mkdir -p src/{controllers,middleware,routes,services,models,utils,types}
        
        echo "✅ Project initialized!"
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
      test)
        echo "🧪 Running tests..."
        npm test
        ;;
      test:watch)
        echo "👀 Running tests in watch mode..."
        npm run test -- --watch
        ;;
      lint)
        echo "🔍 Running ESLint..."
        npm run lint
        ;;
      format)
        echo "💅 Formatting code..."
        npm run format
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
      db:seed)
        echo "🌱 Seeding database..."
        npx prisma db seed
        ;;
      docker:build)
        echo "🐳 Building Docker image..."
        docker build -t api-app .
        ;;
      docker:run)
        echo "🐳 Running Docker container..."
        docker run -p 3000:3000 api-app
        ;;
      pm2:start)
        echo "🔄 Starting with PM2..."
        pm2 start ecosystem.config.js
        ;;
      pm2:stop)
        echo "🛑 Stopping PM2..."
        pm2 stop all
        ;;
      clean)
        echo "🧹 Cleaning project..."
        rm -rf dist
        rm -rf node_modules
        npm install
        ;;
      *)
        echo "🟦 TypeScript Node.js API Commands"
        echo ""
        echo "Usage: api-dev <command>"
        echo ""
        echo "Commands:"
        echo "  init          Initialize new API project"
        echo "  dev           Start development server"
        echo "  build         Build for production"
        echo "  start         Start production server"
        echo "  test          Run tests"
        echo "  test:watch    Run tests in watch mode"
        echo "  lint          Run ESLint"
        echo "  format        Format code with Prettier"
        echo "  db:generate   Generate Prisma client"
        echo "  db:migrate    Run database migrations"
        echo "  db:studio     Open Prisma Studio"
        echo "  db:seed       Seed database"
        echo "  docker:build  Build Docker image"
        echo "  docker:run    Run Docker container"
        echo "  pm2:start     Start with PM2"
        echo "  pm2:stop      Stop PM2"
        echo "  clean         Clean project"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "typescript-node-api-dev";
  
  buildInputs = with pkgs; [
    # Core development tools
    nodejs_20
    npm
    yarn
    pnpm
    git
    
    # Database systems
    postgresql
    mysql80
    redis
    mongodb
    sqlite
    
    # Development utilities
    setupScript
    devScript
    
    # Process management
    pm2
    
    # Container tools
    docker
    docker-compose
    
    # Testing and debugging
    chromium
    
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
    # Database setup
    export PGDATA="$PWD/.postgres"
    export PGHOST="localhost"
    export PGPORT="5432"
    export PGUSER="postgres"
    
    # Redis setup
    export REDIS_URL="redis://localhost:6379"
    
    # MongoDB setup
    export MONGODB_URL="mongodb://localhost:27017"
    
    # Node.js environment
    export NODE_ENV="development"
    export PORT="3000"
    
    # TypeScript environment
    export TS_NODE_PROJECT="./tsconfig.json"
    
    # Initialize PostgreSQL if not exists
    if [ ! -d "$PGDATA" ]; then
      echo "🗄️ Initializing PostgreSQL database..."
      initdb "$PGDATA" --auth-host=trust --auth-local=trust
      echo "port = $PGPORT" >> "$PGDATA/postgresql.conf"
    fi
    
    # Service management functions
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
    
    stop_services() {
      echo "🛑 Stopping development services..."
      
      if pg_ctl status > /dev/null 2>&1; then
        pg_ctl stop
        echo "✅ PostgreSQL stopped"
      fi
      
      if redis-cli ping > /dev/null 2>&1; then
        redis-cli shutdown
        echo "✅ Redis stopped"
      fi
    }
    
    trap stop_services EXIT
    
    echo "🟦 TypeScript Node.js API Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Node.js: $(node --version)"
    echo "🟦 TypeScript: $(tsc --version)"
    echo "🗄️ PostgreSQL: $(postgres --version | head -n1)"
    echo "🔴 Redis: $(redis-server --version)"
    echo "🐳 Docker: $(docker --version)"
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-node-api    # Initial environment setup"
    echo "  api-dev           # Development commands"
    echo "  start_services    # Start PostgreSQL and Redis"
    echo "  stop_services     # Stop PostgreSQL and Redis"
    echo ""
    echo "📚 Quick start:"
    echo "  start_services"
    echo "  mkdir myapi && cd myapi"
    echo "  npm init -y"
    echo "  api-dev init"
    echo "  api-dev dev"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';
}