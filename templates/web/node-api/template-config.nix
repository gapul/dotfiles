# TypeScript Node.js API Template Configuration
{
  name = "typescript-node-api";
  displayName = "TypeScript Node.js API";
  description = "Modern TypeScript API with Express, Prisma, and comprehensive tooling";
  
  type = "backend";
  framework = "express";
  language = "typescript";
  
  features = [
    "express"        # Web framework
    "prisma"         # ORM and database toolkit
    "jwt-auth"       # Authentication
    "validation"     # Request validation
    "swagger"        # API documentation
    "testing"        # Jest + Supertest
    "logging"        # Structured logging
    "docker"         # Containerization
  ];
  
  dependencies = [
    "express"
    "@types/express"
    "prisma"
    "@prisma/client"
    "jsonwebtoken"
    "@types/jsonwebtoken"
    "bcryptjs"
    "@types/bcryptjs"
    "zod"
    "helmet"
    "cors"
    "@types/cors"
    "dotenv"
    "winston"
    "swagger-jsdoc"
    "swagger-ui-express"
    "@types/swagger-jsdoc"
    "@types/swagger-ui-express"
  ];
  
  devDependencies = [
    "typescript"
    "@types/node"
    "ts-node"
    "ts-node-dev"
    "jest"
    "@types/jest"
    "supertest"
    "@types/supertest"
    "eslint"
    "@typescript-eslint/parser"
    "@typescript-eslint/eslint-plugin"
    "prettier"
    "husky"
    "lint-staged"
  ];
  
  scripts = {
    dev = "ts-node-dev --respawn --transpile-only src/index.ts";
    build = "tsc";
    start = "node dist/index.js";
    test = "jest";
    "test:watch" = "jest --watch";
    "test:coverage" = "jest --coverage";
    lint = "eslint src/**/*.ts";
    "lint:fix" = "eslint src/**/*.ts --fix";
    format = "prettier --write src/**/*.ts";
    "db:generate" = "prisma generate";
    "db:push" = "prisma db push";
    "db:migrate" = "prisma migrate dev";
    "db:studio" = "prisma studio";
    "db:seed" = "ts-node prisma/seed.ts";
  };
  
  files = [
    "package.json"
    "tsconfig.json"
    ".eslintrc.js"
    ".prettierrc"
    "jest.config.js"
    "Dockerfile"
    ".dockerignore"
    "src/index.ts"
    "src/app.ts"
    "src/config/database.ts"
    "src/config/logger.ts"
    "src/middleware/auth.ts"
    "src/middleware/validation.ts"
    "src/middleware/errorHandler.ts"
    "src/routes/auth.ts"
    "src/routes/users.ts"
    "src/controllers/authController.ts"
    "src/controllers/userController.ts"
    "src/services/authService.ts"
    "src/services/userService.ts"
    "src/types/index.ts"
    "src/utils/jwt.ts"
    "src/utils/password.ts"
    "prisma/schema.prisma"
    "prisma/seed.ts"
    ".env.example"
    "README.md"
  ];
  
  nixPackages = [
    "nodejs_20"
    "typescript"
    "postgresql"
  ];
}