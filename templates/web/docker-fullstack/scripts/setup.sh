#!/bin/bash

# Docker Fullstack Project Setup Script
# Initializes a new Docker-based fullstack application

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="${1:-$(basename $(pwd))}"
BACKEND_TYPE="${2:-nodejs}"  # nodejs, python, go
FRONTEND_TYPE="${3:-react}"  # react, vue

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    print_success "All dependencies are available"
}

create_directory_structure() {
    print_status "Creating directory structure..."
    
    mkdir -p {frontend,backend,database,nginx,scripts,logs}
    
    # Create placeholder files
    touch .env
    touch .env.example
    touch .dockerignore
    
    print_success "Directory structure created"
}

setup_environment_files() {
    print_status "Setting up environment files..."
    
    cat > .env.example << EOF
# Database Configuration
POSTGRES_DB=${PROJECT_NAME}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=password
DATABASE_URL=postgresql://postgres:password@database:5432/${PROJECT_NAME}

# Redis Configuration
REDIS_URL=redis://redis:6379

# Backend Configuration
NODE_ENV=development
API_PORT=8000
JWT_SECRET=your-jwt-secret-here

# Frontend Configuration
REACT_APP_API_URL=http://localhost:8000

# SSL Configuration (for production)
SSL_CERT_PATH=/etc/nginx/ssl/nginx.crt
SSL_KEY_PATH=/etc/nginx/ssl/nginx.key
EOF

    if [ ! -f .env ]; then
        cp .env.example .env
        print_success "Environment files created"
    else
        print_warning ".env file already exists, skipping"
    fi
}

setup_dockerignore() {
    print_status "Creating .dockerignore..."
    
    cat > .dockerignore << EOF
# Dependencies
node_modules/
__pycache__/
*.pyc
vendor/

# Build outputs
dist/
build/
target/

# Environment files
.env
.env.local
.env.*.local

# Version control
.git/
.gitignore

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Logs
logs/
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Runtime data
pids/
*.pid
*.seed
*.pid.lock

# Coverage directory used by tools like istanbul
coverage/

# nyc test coverage
.nyc_output/

# Dependency directories
jspm_packages/

# Optional npm cache directory
.npm

# Optional REPL history
.node_repl_history

# Output of 'npm pack'
*.tgz

# Yarn Integrity file
.yarn-integrity
EOF

    print_success ".dockerignore created"
}

setup_database_init() {
    print_status "Setting up database initialization..."
    
    mkdir -p database
    cat > database/init.sql << EOF
-- Database initialization script for ${PROJECT_NAME}

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create tables
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- Insert sample data
INSERT INTO users (email, password_hash, name) VALUES
    ('admin@example.com', crypt('admin123', gen_salt('bf')), 'Admin User'),
    ('user@example.com', crypt('user123', gen_salt('bf')), 'Regular User')
ON CONFLICT (email) DO NOTHING;
EOF

    print_success "Database initialization script created"
}

create_development_compose() {
    print_status "Creating development docker-compose configuration..."
    
    cat > docker-compose.dev.yml << EOF
version: '3.8'

services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile.frontend
      target: development
    volumes:
      - ./frontend:/app
      - /app/node_modules
    environment:
      - CHOKIDAR_USEPOLLING=true
      - FAST_REFRESH=true

  backend:
    build:
      context: .
      dockerfile: Dockerfile.backend
      target: ${BACKEND_TYPE}-base
    volumes:
      - ./backend:/app
    environment:
      - NODE_ENV=development
      - DEBUG=*

  database:
    ports:
      - "5432:5432"
    volumes:
      - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql:ro

  redis:
    ports:
      - "6379:6379"
EOF

    print_success "Development configuration created"
}

create_production_compose() {
    print_status "Creating production docker-compose configuration..."
    
    cat > docker-compose.prod.yml << EOF
version: '3.8'

services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile.frontend
      target: production
    restart: unless-stopped

  backend:
    build:
      context: .
      dockerfile: Dockerfile.backend
      target: ${BACKEND_TYPE}-base
    restart: unless-stopped
    environment:
      - NODE_ENV=production

  database:
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    restart: unless-stopped
    volumes:
      - redis_data:/data

  nginx:
    restart: unless-stopped
EOF

    print_success "Production configuration created"
}

create_helper_scripts() {
    print_status "Creating helper scripts..."
    
    # Development script
    cat > scripts/dev.sh << 'EOF'
#!/bin/bash
echo "Starting development environment..."
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build
EOF

    # Production script
    cat > scripts/prod.sh << 'EOF'
#!/bin/bash
echo "Starting production environment..."
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
EOF

    # Clean script
    cat > scripts/clean.sh << 'EOF'
#!/bin/bash
echo "Cleaning up Docker resources..."
docker-compose down -v --rmi all --remove-orphans
docker system prune -f
EOF

    # Logs script
    cat > scripts/logs.sh << 'EOF'
#!/bin/bash
SERVICE=${1:-}
if [ -z "$SERVICE" ]; then
    docker-compose logs -f
else
    docker-compose logs -f "$SERVICE"
fi
EOF

    # Make scripts executable
    chmod +x scripts/*.sh
    
    print_success "Helper scripts created"
}

create_readme() {
    print_status "Creating README.md..."
    
    cat > README.md << EOF
# ${PROJECT_NAME}

Docker-based fullstack application with ${FRONTEND_TYPE} frontend and ${BACKEND_TYPE} backend.

## 🚀 Quick Start

### Development
\`\`\`bash
# Start development environment
./scripts/dev.sh

# Or manually
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build
\`\`\`

### Production
\`\`\`bash
# Start production environment
./scripts/prod.sh

# Or manually
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
\`\`\`

## 📋 Services

- **Frontend**: ${FRONTEND_TYPE} application (port 3000)
- **Backend**: ${BACKEND_TYPE} API server (port 8000)
- **Database**: PostgreSQL (port 5432)
- **Redis**: Cache server (port 6379)
- **Nginx**: Reverse proxy (ports 80/443)

## 🛠️ Development

### Available Scripts

\`\`\`bash
# Start development environment
./scripts/dev.sh

# View logs
./scripts/logs.sh [service]

# Clean up resources
./scripts/clean.sh
\`\`\`

### Environment Variables

Copy \`.env.example\` to \`.env\` and configure:

\`\`\`bash
cp .env.example .env
\`\`\`

### Database Access

\`\`\`bash
# Connect to PostgreSQL
docker-compose exec database psql -U postgres -d ${PROJECT_NAME}

# Connect to Redis
docker-compose exec redis redis-cli
\`\`\`

## 🌐 Access Points

- Frontend: http://localhost (or https://localhost)
- Backend API: http://localhost/api
- Database: localhost:5432
- Redis: localhost:6379

## 📁 Project Structure

\`\`\`
${PROJECT_NAME}/
├── frontend/          # Frontend application
├── backend/           # Backend API
├── database/          # Database initialization
├── nginx/             # Nginx configuration
├── scripts/           # Helper scripts
├── docker-compose.yml # Main compose file
├── docker-compose.dev.yml   # Development overrides
├── docker-compose.prod.yml  # Production overrides
└── .env              # Environment variables
\`\`\`

## 🔧 Troubleshooting

### Common Issues

1. **Port conflicts**: Ensure ports 80, 443, 3000, 8000, 5432, 6379 are available
2. **Permission issues**: Check Docker daemon is running and user has permissions
3. **Build failures**: Try \`docker system prune -f\` to clean up cached layers

### Useful Commands

\`\`\`bash
# Rebuild specific service
docker-compose build [service]

# View service status
docker-compose ps

# Execute commands in containers
docker-compose exec [service] [command]

# Follow logs
docker-compose logs -f [service]
\`\`\`
EOF

    print_success "README.md created"
}

main() {
    print_status "Setting up Docker fullstack project: ${PROJECT_NAME}"
    print_status "Backend type: ${BACKEND_TYPE}"
    print_status "Frontend type: ${FRONTEND_TYPE}"
    
    check_dependencies
    create_directory_structure
    setup_environment_files
    setup_dockerignore
    setup_database_init
    create_development_compose
    create_production_compose
    create_helper_scripts
    create_readme
    
    print_success "Project setup completed!"
    print_status "Next steps:"
    echo "  1. Add your frontend code to ./frontend/"
    echo "  2. Add your backend code to ./backend/"
    echo "  3. Run: ./scripts/dev.sh"
    echo "  4. Open: http://localhost"
}

# Run main function with all arguments
main "$@"