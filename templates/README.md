# Development Environment Templates

Nix-based development environment templates for rapid project setup and consistent tooling across platforms.

## 📁 Directory Structure

```
templates/
├── README.md                   # This file
├── _shared/                    # Shared utilities and configurations
│   ├── scripts/               # Common setup scripts
│   ├── configs/               # Shared configuration files
│   └── utils.nix              # Shared Nix utilities
│
├── web/                       # Web development templates
│   ├── nextjs-fullstack/     # Next.js with TypeScript, Auth, DB
│   ├── vue-typescript/        # Vue 3 + TypeScript + Vite
│   ├── node-api/             # TypeScript Node.js REST API
│   └── docker-fullstack/     # Multi-service Docker setup
│
├── mobile/                    # Mobile development templates
│   ├── react-native/         # React Native + Expo
│   └── flutter/              # Flutter cross-platform
│
├── data/                      # Data science and analytics
│   ├── python-ml/            # Python ML with Jupyter, PyTorch, TF
│   └── r-analytics/          # R statistical computing
│
├── systems/                   # Systems and infrastructure
│   ├── rust-cli/             # Rust command-line applications
│   ├── go-api/               # Go web services
│   └── container/            # Docker and container orchestration
│
└── experimental/             # Experimental and specialized templates
    ├── blockchain/           # Web3 and blockchain development
    ├── iot/                  # IoT and embedded systems
    └── gamedev/              # Game development
```

## 🚀 Quick Start

### Using a Template

```bash
# Navigate to your project directory
cd ~/projects/myapp

# Enter the development environment
nix develop /path/to/dotfiles/templates/web/nextjs-fullstack

# Initialize the project
setup-nextjs

# Start development
nextjs-dev create myapp
cd myapp && nextjs-dev dev
```

### Available Templates

#### 🌐 Web Development
- **nextjs-fullstack**: Full-stack Next.js with authentication, database, payments
- **vue-typescript**: Modern Vue.js with TypeScript and testing
- **node-api**: TypeScript Node.js REST API with database integration
- **docker-fullstack**: Multi-service containerized applications

#### 📱 Mobile Development  
- **react-native**: Cross-platform mobile with Expo and TypeScript
- **flutter**: Native mobile development with Dart

#### 🧬 Data Science
- **python-ml**: Machine learning with Python, Jupyter, GPU support
- **r-analytics**: Statistical computing and data visualization with R

#### 🛠️ Systems Programming
- **rust-cli**: Command-line applications in Rust
- **go-api**: High-performance web services in Go

## 🎯 Template Features

### Consistent Interface
All templates provide:
- `setup-*` command for initial project setup
- `*-dev` command for development workflows
- Health checks and environment validation
- Automated service management (databases, etc.)

### Development Experience
- **Fast Setup**: One command to get a complete development environment
- **Hot Reload**: Instant feedback during development
- **Testing**: Pre-configured testing frameworks and tools
- **Code Quality**: Linting, formatting, and type checking
- **Debugging**: Integrated debugging tools and profilers

### Production Ready
- **Containerization**: Docker support for all templates
- **CI/CD**: GitHub Actions and deployment configurations
- **Security**: Best practices and security scanning
- **Performance**: Optimized builds and performance monitoring

## 📚 Documentation

Each template includes:
- `default.nix`: Main environment configuration
- `README.md`: Template-specific documentation
- Example configurations and best practices
- Troubleshooting guides

## 🤝 Contributing

When adding new templates:

1. Follow the directory structure conventions
2. Include comprehensive `default.nix` with all dependencies
3. Provide clear setup and development commands
4. Add thorough documentation
5. Test on multiple platforms (macOS, Linux)

## 🔧 Template Development

### Creating a New Template

```bash
# Create template directory
mkdir -p templates/category/template-name

# Create the Nix environment file
touch templates/category/template-name/default.nix

# Add documentation
touch templates/category/template-name/README.md
```

### Template Requirements

1. **Environment Definition**: Complete `default.nix` with all dependencies
2. **Setup Script**: Automated project initialization
3. **Development Commands**: Consistent development workflow
4. **Documentation**: Clear usage instructions and examples
5. **Platform Support**: Works on macOS and Linux

## 📈 Roadmap

### Planned Templates
- **Blockchain**: Ethereum, Solana, NEAR development
- **IoT**: Embedded systems with Rust and C++
- **Game Development**: Unity, Godot, custom engines
- **Desktop**: Electron, Tauri, native applications
- **DevOps**: Terraform, Kubernetes, monitoring

### Improvements
- Template versioning and compatibility
- Template discovery and search
- Automated testing for all templates
- Performance benchmarking
- Community template registry

---

Built with ❤️ using Nix for consistent, reproducible development environments.