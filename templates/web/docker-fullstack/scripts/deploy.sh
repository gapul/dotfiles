#!/bin/bash

# Docker Fullstack Deployment Script
# Deploys the application to production environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="${1:-$(basename $(pwd))}"
DEPLOYMENT_ENV="${2:-production}"
BACKUP_ENABLED="${3:-true}"

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

check_prerequisites() {
    print_status "Checking deployment prerequisites..."
    
    if [ ! -f .env ]; then
        print_error ".env file not found. Please create one from .env.example"
        exit 1
    fi
    
    if [ ! -f docker-compose.yml ]; then
        print_error "docker-compose.yml not found"
        exit 1
    fi
    
    if [ ! -f docker-compose.prod.yml ]; then
        print_error "docker-compose.prod.yml not found"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

backup_database() {
    if [ "$BACKUP_ENABLED" = "true" ]; then
        print_status "Creating database backup..."
        
        local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Backup PostgreSQL
        if docker-compose ps database | grep -q "Up"; then
            docker-compose exec -T database pg_dump -U postgres "$PROJECT_NAME" > "$backup_dir/postgres_backup.sql"
            print_success "PostgreSQL backup created: $backup_dir/postgres_backup.sql"
        else
            print_warning "Database container not running, skipping backup"
        fi
        
        # Backup Redis if running
        if docker-compose ps redis | grep -q "Up"; then
            docker-compose exec -T redis redis-cli BGSAVE
            docker cp "$(docker-compose ps -q redis):/data/dump.rdb" "$backup_dir/redis_backup.rdb"
            print_success "Redis backup created: $backup_dir/redis_backup.rdb"
        else
            print_warning "Redis container not running, skipping backup"
        fi
    else
        print_status "Database backup disabled"
    fi
}

build_images() {
    print_status "Building production images..."
    
    # Build all services
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml build --no-cache
    
    if [ $? -eq 0 ]; then
        print_success "Images built successfully"
    else
        print_error "Image build failed"
        exit 1
    fi
}

run_health_checks() {
    print_status "Running health checks..."
    
    local max_attempts=30
    local attempt=1
    
    # Check if all services are healthy
    while [ $attempt -le $max_attempts ]; do
        print_status "Health check attempt $attempt/$max_attempts"
        
        local healthy_services=0
        local total_services=0
        
        # Check each service
        for service in frontend backend database redis nginx; do
            total_services=$((total_services + 1))
            
            if docker-compose ps "$service" | grep -q "Up"; then
                # Additional health checks for specific services
                case $service in
                    "frontend"|"nginx")
                        if curl -f http://localhost/health > /dev/null 2>&1; then
                            healthy_services=$((healthy_services + 1))
                        fi
                        ;;
                    "backend")
                        if curl -f http://localhost/api/health > /dev/null 2>&1; then
                            healthy_services=$((healthy_services + 1))
                        fi
                        ;;
                    "database")
                        if docker-compose exec -T database pg_isready -U postgres > /dev/null 2>&1; then
                            healthy_services=$((healthy_services + 1))
                        fi
                        ;;
                    "redis")
                        if docker-compose exec -T redis redis-cli ping | grep -q "PONG"; then
                            healthy_services=$((healthy_services + 1))
                        fi
                        ;;
                esac
            fi
        done
        
        if [ $healthy_services -eq $total_services ]; then
            print_success "All services are healthy"
            return 0
        fi
        
        print_status "Healthy services: $healthy_services/$total_services"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    print_error "Health checks failed after $max_attempts attempts"
    return 1
}

deploy_application() {
    print_status "Deploying application..."
    
    # Stop existing services gracefully
    docker-compose down --timeout 30
    
    # Start production services
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
    
    if [ $? -eq 0 ]; then
        print_success "Application deployed successfully"
    else
        print_error "Deployment failed"
        exit 1
    fi
}

cleanup_old_images() {
    print_status "Cleaning up old Docker images..."
    
    # Remove dangling images
    docker image prune -f
    
    # Remove old images (keep last 3 versions)
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.CreatedAt}}" | \
    grep "$PROJECT_NAME" | \
    sort -k2 -r | \
    tail -n +4 | \
    awk '{print $1}' | \
    xargs -r docker rmi -f
    
    print_success "Cleanup completed"
}

generate_deployment_report() {
    print_status "Generating deployment report..."
    
    local report_file="deployment_$(date +%Y%m%d_%H%M%S).log"
    
    cat > "$report_file" << EOF
Deployment Report - ${PROJECT_NAME}
Generated: $(date)
Environment: ${DEPLOYMENT_ENV}

=== Docker Images ===
$(docker images | grep "$PROJECT_NAME" || echo "No project images found")

=== Running Services ===
$(docker-compose ps)

=== Service Health ===
EOF
    
    # Add health check results
    for service in frontend backend database redis nginx; do
        echo "=== $service ===" >> "$report_file"
        docker-compose logs --tail=10 "$service" >> "$report_file" 2>/dev/null || echo "Service not running" >> "$report_file"
        echo "" >> "$report_file"
    done
    
    print_success "Deployment report saved: $report_file"
}

rollback_deployment() {
    print_error "Deployment failed, initiating rollback..."
    
    # Stop current deployment
    docker-compose down
    
    # Try to restore from backup if available
    local latest_backup=$(ls -t backups/ | head -1)
    if [ -n "$latest_backup" ] && [ "$BACKUP_ENABLED" = "true" ]; then
        print_status "Restoring from backup: $latest_backup"
        
        # Start database
        docker-compose up -d database
        sleep 10
        
        # Restore PostgreSQL backup
        if [ -f "backups/$latest_backup/postgres_backup.sql" ]; then
            docker-compose exec -T database psql -U postgres -d "$PROJECT_NAME" < "backups/$latest_backup/postgres_backup.sql"
            print_success "PostgreSQL backup restored"
        fi
        
        # Restore Redis backup
        if [ -f "backups/$latest_backup/redis_backup.rdb" ]; then
            docker cp "backups/$latest_backup/redis_backup.rdb" "$(docker-compose ps -q redis):/data/dump.rdb"
            docker-compose restart redis
            print_success "Redis backup restored"
        fi
    fi
    
    print_error "Rollback completed. Please check your configuration and try again."
    exit 1
}

main() {
    print_status "Starting deployment of ${PROJECT_NAME} to ${DEPLOYMENT_ENV}"
    
    # Trap errors for automatic rollback
    trap rollback_deployment ERR
    
    check_prerequisites
    backup_database
    build_images
    deploy_application
    
    # Wait for services to start
    sleep 30
    
    if run_health_checks; then
        cleanup_old_images
        generate_deployment_report
        
        print_success "Deployment completed successfully!"
        print_status "Application is available at:"
        echo "  - Frontend: http://localhost or https://localhost"
        echo "  - Backend API: http://localhost/api"
        echo "  - Health check: http://localhost/health"
    else
        rollback_deployment
    fi
}

# Run main function with all arguments
main "$@"