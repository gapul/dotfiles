# Docker Fullstack Application Template Configuration
{
  name = "docker-fullstack";
  displayName = "Docker Fullstack";
  description = "Full-stack web application with Docker containerization";
  
  type = "fullstack";
  framework = "docker-compose";
  
  services = [
    "frontend"    # React/Vue frontend
    "backend"     # Node.js/Python/Go API
    "database"    # PostgreSQL
    "redis"       # Redis cache
    "nginx"       # Reverse proxy
  ];
  
  dependencies = [
    "docker"
    "docker-compose"
  ];
  
  devDependencies = [
    "docker-buildx"
    "docker-scout"
  ];
  
  scripts = {
    dev = "docker-compose up --build";
    start = "docker-compose up -d";
    stop = "docker-compose down";
    build = "docker-compose build";
    logs = "docker-compose logs -f";
    clean = "docker-compose down -v --rmi all";
    reset = "docker-compose down -v && docker-compose up --build";
  };
  
  files = [
    "docker-compose.yml"
    "docker-compose.dev.yml"
    "docker-compose.prod.yml"
    ".dockerignore"
    "Dockerfile.frontend"
    "Dockerfile.backend"
    "nginx/nginx.conf"
    "nginx/Dockerfile"
    "scripts/setup.sh"
    "scripts/deploy.sh"
    ".env.example"
    "README.md"
  ];
  
  nixPackages = [
    "docker"
    "docker-compose"
    "docker-buildx"
  ];
}