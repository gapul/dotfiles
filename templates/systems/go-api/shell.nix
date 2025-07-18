# Go Web API Development Environment
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Go toolchain
    go
    gopls
    golangci-lint
    goimports
    godoc
    
    # Development tools
    air                    # Live reload
    migrate               # Database migrations
    mockgen               # Mock generation
    
    # Database tools
    postgresql
    sqlite
    
    # HTTP tools
    curl
    httpie
    
    # Debugging
    delve                 # Go debugger
  ];

  shellHook = ''
    echo "🐹 Go Web API Development Environment"
    echo "====================================="
    echo "🐹 Go: $(go version)"
    echo "📦 Modules: $(go env GOMOD)"
    echo "🔧 Tools: air, golangci-lint, gopls available"
    echo ""
    echo "Available commands:"
    echo "  go run main.go              - Start the server"
    echo "  air                         - Start with live reload"
    echo "  go test ./...               - Run all tests"
    echo "  go test -v ./...            - Run tests (verbose)"
    echo "  go test -cover ./...        - Run tests with coverage"
    echo "  golangci-lint run           - Run linter"
    echo "  gofmt -s -w .               - Format code"
    echo "  go mod tidy                 - Clean up dependencies"
    echo "  go build -o bin/app main.go - Build binary"
    echo ""
    echo "🚀 Server endpoints (when running):"
    echo "  http://localhost:8080/health        - Health check"
    echo "  http://localhost:8080/api/v1/status - API status"
    echo ""
    echo "📁 Project structure:"
    echo "  main.go                     - Application entry point"
    echo "  internal/                   - Private application code"
    echo "  pkg/                        - Public library code"
    echo "  tests/                      - Test files"
    echo ""
  '';

  # Environment variables
  CGO_ENABLED = "1";
  GOOS = "darwin";
  GOARCH = "amd64";
}