# {{PROJECT_NAME}}

Modern fullstack web application built with Docker containerization, featuring a complete development and production environment setup.

## 🚀 Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.0+)

### Development Setup

1. **Clone and setup**
   ```bash
   git clone <repository-url>
   cd {{PROJECT_NAME}}
   cp .env.example .env
   ```

2. **Start development environment**
   ```bash
   # Using helper script
   ./scripts/setup.sh

   # Or manually
   docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build
   ```

3. **Access the application**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000
   - Database Admin (Adminer): http://localhost:8080
   - Redis Admin: http://localhost:8081

### Production Deployment

```bash
# Deploy to production
./scripts/deploy.sh

# Or manually
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

## 🏗️ Architecture

### Services Overview

| Service | Description | Port | Technology |
|---------|-------------|------|------------|
| **Frontend** | React/Vue.js SPA | 3000 | Node.js + Vite/Webpack |
| **Backend** | RESTful API Server | 8000 | Node.js/Python/Go |
| **Database** | PostgreSQL Database | 5432 | PostgreSQL 15 |
| **Redis** | Cache & Session Store | 6379 | Redis 7 |
| **Nginx** | Reverse Proxy & SSL | 80/443 | Nginx Alpine |

### Development Tools

| Tool | Description | Port | Access |
|------|-------------|------|--------|
| **Adminer** | Database Administration | 8080 | Web UI |
| **Redis Commander** | Redis Management | 8081 | Web UI |
| **Prometheus** | Metrics Collection | 9090 | Web UI (optional) |
| **Grafana** | Monitoring Dashboard | 3001 | Web UI (optional) |

## 📁 Project Structure

```
{{PROJECT_NAME}}/
├── frontend/                 # Frontend application
│   ├── src/                 # Source code
│   ├── public/              # Static assets
│   ├── package.json         # Dependencies
│   └── Dockerfile           # Frontend container
├── backend/                 # Backend API
│   ├── src/                 # Source code
│   ├── package.json         # Dependencies
│   └── Dockerfile           # Backend container
├── database/                # Database configuration
│   └── init.sql            # Initial schema
├── nginx/                   # Nginx configuration
│   ├── nginx.conf          # Main config
│   ├── frontend.conf       # Frontend config
│   └── Dockerfile          # Nginx container
├── scripts/                 # Helper scripts
│   ├── setup.sh            # Project setup
│   ├── deploy.sh           # Production deployment
│   ├── dev.sh              # Development start
│   └── clean.sh            # Cleanup resources
├── monitoring/              # Monitoring configuration
├── docker-compose.yml       # Base compose file
├── docker-compose.dev.yml   # Development overrides
├── docker-compose.prod.yml  # Production overrides
├── .env.example            # Environment template
└── README.md               # This file
```

## 🛠️ Development

### Available Scripts

```bash
# Development
./scripts/dev.sh                    # Start development environment
./scripts/logs.sh [service]         # View logs
./scripts/clean.sh                  # Clean up resources

# Production
./scripts/deploy.sh                 # Deploy to production
./scripts/deploy.sh myapp staging   # Deploy to staging

# Docker Commands
docker-compose ps                   # View service status
docker-compose build [service]     # Rebuild specific service
docker-compose exec [service] bash # Access service shell
```

### Environment Configuration

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

Key configuration options:

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_NAME` | Application name | {{PROJECT_NAME}} |
| `DATABASE_URL` | PostgreSQL connection | postgresql://... |
| `REDIS_URL` | Redis connection | redis://redis:6379 |
| `JWT_SECRET` | JWT signing key | change-in-production |
| `NODE_ENV` | Environment mode | development |

### Database Management

```bash
# Connect to PostgreSQL
docker-compose exec database psql -U postgres -d {{PROJECT_NAME}}

# Run migrations (if applicable)
docker-compose exec backend npm run migrate

# Seed database
docker-compose exec backend npm run seed

# Backup database
docker-compose exec database pg_dump -U postgres {{PROJECT_NAME}} > backup.sql
```

### Redis Management

```bash
# Connect to Redis CLI
docker-compose exec redis redis-cli

# View Redis data via web interface
open http://localhost:8081
```

## 🚀 Production

### Deployment Process

1. **Prepare environment**
   ```bash
   # Copy production environment
   cp .env.example .env.production
   # Edit production values
   ```

2. **Deploy application**
   ```bash
   ./scripts/deploy.sh {{PROJECT_NAME}} production
   ```

3. **Verify deployment**
   ```bash
   # Check service health
   curl -f http://localhost/health
   curl -f http://localhost/api/health
   ```

### Production Features

- **SSL/TLS**: Automatic HTTPS with self-signed certificates
- **Health Checks**: Built-in health monitoring for all services
- **Resource Limits**: Memory and CPU constraints
- **Auto Restart**: Services restart on failure
- **Backup System**: Automated database backups
- **Monitoring**: Optional Prometheus + Grafana integration

### Monitoring (Optional)

Enable monitoring with:

```bash
# Start with monitoring profile
docker-compose --profile monitoring -f docker-compose.yml -f docker-compose.prod.yml up -d

# Access monitoring
open http://localhost:9090  # Prometheus
open http://localhost:3001  # Grafana (admin/admin)
```

## 🔧 Troubleshooting

### Common Issues

**Port Conflicts**
```bash
# Check if ports are in use
sudo lsof -i :80,443,3000,8000,5432,6379

# Stop conflicting services
sudo systemctl stop nginx  # If system nginx is running
```

**Permission Issues**
```bash
# Fix Docker permissions
sudo usermod -aG docker $USER
newgrp docker

# Fix file permissions
sudo chown -R $USER:$USER .
```

**Build Failures**
```bash
# Clean Docker cache
docker system prune -a

# Rebuild without cache
docker-compose build --no-cache
```

**Database Connection Issues**
```bash
# Check database logs
docker-compose logs database

# Reset database
docker-compose down -v
docker-compose up database
```

### Health Checks

```bash
# Check all services
docker-compose ps

# Test endpoints
curl http://localhost/health          # Frontend health
curl http://localhost/api/health      # Backend health

# Check database
docker-compose exec database pg_isready -U postgres

# Check Redis
docker-compose exec redis redis-cli ping
```

### Performance Optimization

**Database Optimization**
```sql
-- Check database performance
SELECT * FROM pg_stat_activity;
SELECT * FROM pg_stat_statements;
```

**Redis Optimization**
```bash
# Redis memory usage
docker-compose exec redis redis-cli info memory

# Redis performance
docker-compose exec redis redis-cli info stats
```

## 📝 API Documentation

### Backend Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/api/users` | List users |
| POST | `/api/users` | Create user |
| GET | `/api/users/:id` | Get user |
| PUT | `/api/users/:id` | Update user |
| DELETE | `/api/users/:id` | Delete user |

### Authentication

```javascript
// Login
POST /api/auth/login
{
  "email": "user@example.com",
  "password": "password"
}

// Register
POST /api/auth/register
{
  "name": "User Name",
  "email": "user@example.com",
  "password": "password"
}
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make changes and test locally
4. Commit changes: `git commit -am 'Add new feature'`
5. Push to branch: `git push origin feature/new-feature`
6. Submit a pull request

### Development Guidelines

- Follow the existing code style
- Add tests for new features
- Update documentation as needed
- Ensure Docker builds pass
- Test in both development and production modes

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- Documentation: Check this README and inline code comments
- Issues: Create an issue on GitHub
- Discussions: Use GitHub Discussions for questions

---

Built with ❤️ using Docker, React, Node.js, PostgreSQL, and Redis.