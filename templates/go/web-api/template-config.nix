# Go Web API Template Configuration
{
  name = "go-web-api";
  displayName = "Go Web API";
  description = "RESTful web API built with Go and Gin framework";
  
  language = "go";
  framework = "gin";
  type = "web-api";
  
  goVersion = "1.21";
  
  dependencies = [
    "github.com/gin-gonic/gin"
    "github.com/go-playground/validator/v10"
    "github.com/joho/godotenv"
    "github.com/golang-jwt/jwt/v5"
    "golang.org/x/crypto"
    "gorm.io/gorm"
    "gorm.io/driver/postgres"
    "gorm.io/driver/sqlite"
  ];
  
  devDependencies = [
    "github.com/stretchr/testify"
    "github.com/golang/mock"
    "github.com/air-verse/air"
    "golang.org/x/tools/cmd/goimports"
    "honnef.co/go/tools/cmd/staticcheck"
  ];
  
  scripts = {
    dev = "air";
    start = "go run main.go";
    build = "go build -o bin/{{PROJECT_NAME}} main.go";
    test = "go test ./...";
    test-verbose = "go test -v ./...";
    test-coverage = "go test -cover ./...";
    lint = "golangci-lint run";
    format = "gofmt -s -w . && goimports -w .";
    clean = "go clean && rm -rf bin/";
  };
  
  files = [
    "main.go"
    "go.mod"
    ".air.toml"
    ".env.example"
    "internal/handlers/health.go"
    "internal/handlers/api.go"
    "internal/middleware/cors.go"
    "internal/middleware/auth.go"
    "internal/models/user.go"
    "internal/config/config.go"
    "pkg/database/database.go"
    "pkg/utils/response.go"
    "tests/handlers_test.go"
  ];
  
  nixPackages = [
    "go"
    "gopls"
    "golangci-lint"
    "air"
  ];
}