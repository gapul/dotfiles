# Quick Start Guide - Development Templates

Get up and running with any development stack in minutes using our Nix-based templates.

## 🚀 One-Command Setup

```bash
# Enter any template environment instantly
nix develop /Users/yuki/dotfiles/templates/web/nextjs-fullstack

# Or use the template manager
template use web/nextjs-fullstack
```

## 📚 Template Quick Reference

### 🌐 Web Development

#### Next.js Fullstack
```bash
# Setup
nix develop ~/dotfiles/templates/web/nextjs-fullstack
setup-nextjs

# Development
nextjs-dev create myapp
cd myapp && nextjs-dev dev    # → http://localhost:3000
```

#### Vue.js + TypeScript
```bash
# Setup  
nix develop ~/dotfiles/templates/web/vue-typescript
setup-vue

# Development
vue-dev create myapp
cd myapp && vue-dev dev       # → http://localhost:5173
```

#### Node.js API
```bash
# Setup
nix develop ~/dotfiles/templates/web/node-api
setup-node-api

# Development
start_services                # PostgreSQL + Redis
api-dev init && api-dev dev   # → http://localhost:3000
```

#### Docker Fullstack
```bash
# Setup
nix develop ~/dotfiles/templates/web/docker-fullstack
setup-docker-stack

# Development
docker-dev init
docker-dev up                 # → Multi-service stack
```

### 📱 Mobile Development

#### React Native
```bash
# Setup
nix develop ~/dotfiles/templates/mobile/react-native
setup-react-native

# Development
rn-dev create MyApp
cd MyApp && rn-dev run        # → Expo development
```

#### Flutter
```bash
# Setup
nix develop ~/dotfiles/templates/mobile/flutter
setup-flutter

# Development
flutter-dev create myapp
cd myapp && flutter-dev run   # → iOS/Android/Web
```

### 🧬 Data Science

#### Python ML
```bash
# Setup
nix develop ~/dotfiles/templates/data/python-ml
setup-datascience

# Development
ds-dev notebook               # → http://localhost:8888 (Jupyter)
ds-dev experiment             # → http://localhost:5000 (MLflow)
```

#### R Analytics
```bash
# Setup
nix develop ~/dotfiles/templates/data/r-analytics  
setup-r-stats

# Development
r-dev console                 # → R console
r-dev shiny                   # → http://localhost:3838
r-dev jupyter                 # → http://localhost:8888
```

### 🛠️ Systems Programming

#### Rust CLI
```bash
# Setup
nix develop ~/dotfiles/templates/systems/rust-cli

# Development
cargo new myapp && cd myapp
cargo run
```

#### Go API
```bash
# Setup
nix develop ~/dotfiles/templates/systems/go-api

# Development
go mod init myapi
go run main.go
```

## 🔧 Common Commands

Every template provides these standard commands:

```bash
# Health check
template health

# Environment info
<template>-dev          # Shows all available commands

# Common workflow
setup-<template>        # Initial setup
<template>-dev dev      # Start development
<template>-dev test     # Run tests
<template>-dev build    # Build for production
<template>-dev clean    # Clean project
```

## ⚡ Power User Tips

### Template Manager
```bash
# List all templates
template list

# Search templates
template search react
template search ml

# Health check
template health
```

### Multiple Projects
```bash
# Different terminals for different projects
terminal1$ nix develop ~/dotfiles/templates/web/nextjs-fullstack
terminal2$ nix develop ~/dotfiles/templates/mobile/react-native
terminal3$ nix develop ~/dotfiles/templates/data/python-ml
```

### Service Management
```bash
# Many templates auto-manage services
start_services    # Start PostgreSQL, Redis, etc.
stop_services     # Stop all services
```

## 🎯 Project Examples

### Full-Stack Web App
```bash
# Backend API
nix develop ~/dotfiles/templates/web/node-api
setup-node-api && start_services
api-dev init myapi && cd myapi && api-dev dev &

# Frontend
nix develop ~/dotfiles/templates/web/nextjs-fullstack  
setup-nextjs
nextjs-dev create myapp && cd myapp && nextjs-dev dev
```

### Mobile + ML
```bash
# ML Backend
nix develop ~/dotfiles/templates/data/python-ml
setup-datascience && ds-dev notebook &

# Mobile App
nix develop ~/dotfiles/templates/mobile/react-native
setup-react-native
rn-dev create MLApp && cd MLApp && rn-dev run
```

### Microservices Stack
```bash
# Container Orchestration
nix develop ~/dotfiles/templates/web/docker-fullstack
setup-docker-stack
docker-dev init && docker-dev up
```

## 🔍 Troubleshooting

### Common Issues

**Command not found**
```bash
# Make sure you're in the right environment
nix develop ~/dotfiles/templates/<category>/<template>
```

**Services not starting**
```bash
# Check health
template health

# Manual service start
start_services
```

**Port conflicts**
```bash
# Check what's running
netstat -tulpn | grep LISTEN
lsof -i :3000  # Check specific port
```

**Permission issues**
```bash
# Fix file permissions
chmod +x scripts/*.sh
```

## 📚 Next Steps

1. **Choose a template** from the categories above
2. **Enter the environment** with `nix develop`
3. **Run setup** with `setup-<template>`
4. **Start developing** with `<template>-dev dev`
5. **Explore commands** with `<template>-dev`

## 💡 Pro Tips

- **Bookmark frequently used templates** in your terminal
- **Combine templates** for complex projects
- **Use health check** to verify your environment
- **Check template docs** for advanced features
- **Customize templates** for your specific needs

Happy coding! 🚀