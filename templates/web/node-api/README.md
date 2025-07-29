# {{PROJECT_NAME}}

Modern TypeScript Node.js API built with Express, Prisma, and comprehensive tooling for scalable backend development.

## 🚀 Features

- **TypeScript**: Full type safety with strict configuration
- **Express.js**: Fast, minimalist web framework
- **Prisma**: Modern database toolkit with type-safe client
- **JWT Authentication**: Secure user authentication and authorization
- **Input Validation**: Comprehensive request validation with Zod
- **API Documentation**: Auto-generated Swagger/OpenAPI docs
- **Testing**: Jest setup with comprehensive test utilities
- **Code Quality**: ESLint, Prettier, and Husky pre-commit hooks
- **Security**: Helmet, CORS, rate limiting, and security headers
- **Logging**: Structured logging with Winston
- **Error Handling**: Centralized error handling with custom error types
- **Docker**: Multi-stage Docker builds for development and production

## 📋 Prerequisites

- [Node.js](https://nodejs.org/) (v18 or higher)
- [PostgreSQL](https://postgresql.org/) (v12 or higher)
- [npm](https://npmjs.com/) or [yarn](https://yarnpkg.com/)

## 🛠️ Quick Start

### 1. Environment Setup

```bash
# Copy environment variables
cp .env.example .env

# Edit the environment variables
nano .env
```

Key environment variables to configure:
```env
DATABASE_URL="postgresql://username:password@localhost:5432/{{PROJECT_NAME}}_dev"
JWT_SECRET="your-super-secret-jwt-key-change-this-in-production"
```

### 2. Database Setup

```bash
# Install dependencies
npm install

# Generate Prisma client
npm run db:generate

# Run database migrations
npm run db:migrate

# Seed the database with sample data
npm run db:seed
```

### 3. Development

```bash
# Start development server
npm run dev

# The server will start at http://localhost:3000
# API documentation available at http://localhost:3000/api-docs
```

### 4. Testing

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage
```

## 📁 Project Structure

```
{{PROJECT_NAME}}/
├── src/
│   ├── config/              # Configuration files
│   │   ├── database.ts      # Database connection
│   │   └── logger.ts        # Logging configuration
│   ├── controllers/         # Route controllers
│   │   ├── authController.ts
│   │   └── userController.ts
│   ├── middleware/          # Express middleware
│   │   ├── auth.ts          # Authentication middleware
│   │   ├── validation.ts    # Request validation
│   │   └── errorHandler.ts  # Error handling
│   ├── routes/              # API routes
│   │   ├── auth.ts          # Authentication routes
│   │   └── users.ts         # User management routes
│   ├── services/            # Business logic
│   │   ├── authService.ts   # Authentication service
│   │   └── userService.ts   # User service
│   ├── types/               # TypeScript type definitions
│   │   └── index.ts         # Shared types
│   ├── utils/               # Utility functions
│   │   ├── jwt.ts           # JWT utilities
│   │   └── password.ts      # Password utilities
│   ├── app.ts               # Express app configuration
│   └── index.ts             # Application entry point
├── prisma/
│   ├── schema.prisma        # Database schema
│   └── seed.ts              # Database seeding
├── tests/                   # Test files
│   ├── setup.ts             # Test setup
│   ├── globalSetup.ts       # Global test setup
│   └── globalTeardown.ts    # Global test teardown
├── Dockerfile               # Docker configuration
├── docker-compose.yml       # Docker Compose setup
├── package.json             # Dependencies and scripts
├── tsconfig.json            # TypeScript configuration
├── jest.config.js           # Jest configuration
├── .eslintrc.js             # ESLint configuration
└── .prettierrc              # Prettier configuration
```

## 🔐 Authentication

The API uses JWT (JSON Web Tokens) for authentication. Here's how to use it:

### Register a new user
```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com",
    "password": "password123",
    "confirmPassword": "password123"
  }'
```

### Login
```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john@example.com",
    "password": "password123"
  }'
```

### Use the token
```bash
curl -X GET http://localhost:3000/api/auth/me \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## 📊 API Endpoints

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Register new user |
| POST | `/api/auth/login` | Login user |
| POST | `/api/auth/logout` | Logout user |
| GET | `/api/auth/me` | Get current user |
| PUT | `/api/auth/change-password` | Change password |
| POST | `/api/auth/forgot-password` | Request password reset |
| POST | `/api/auth/reset-password` | Reset password |
| POST | `/api/auth/refresh` | Refresh access token |

### Users (Admin only)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/users` | Get all users |
| GET | `/api/users/:id` | Get user by ID |
| POST | `/api/users` | Create new user |
| PUT | `/api/users/:id` | Update user |
| PUT | `/api/users/:id/profile` | Update user profile |
| DELETE | `/api/users/:id` | Delete user |
| PATCH | `/api/users/:id/activate` | Activate user |
| PATCH | `/api/users/:id/deactivate` | Deactivate user |

### System
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/api-docs` | API documentation |

## 🧪 Testing

The project includes comprehensive testing setup:

```bash
# Run all tests
npm test

# Run specific test file
npm test -- auth.test.ts

# Run tests in watch mode
npm run test:watch

# Generate coverage report
npm run test:coverage
```

## 🚀 Deployment

### Using Docker

```bash
# Build the image
docker build -t {{PROJECT_NAME}} .

# Run the container
docker run -p 3000:3000 --env-file .env {{PROJECT_NAME}}
```

### Using Docker Compose

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop all services
docker-compose down
```

### Environment Variables for Production

```env
NODE_ENV=production
DATABASE_URL="postgresql://username:password@host:port/database"
JWT_SECRET="your-production-jwt-secret"
CORS_ORIGIN="https://yourdomain.com"
LOG_LEVEL=info
```

## 🔧 Development

### Available Scripts

```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run start        # Start production server
npm test            # Run tests
npm run lint        # Run ESLint
npm run lint:fix    # Fix ESLint issues
npm run format      # Format code with Prettier
npm run typecheck   # Run TypeScript type checking
```

### Database Commands

```bash
npm run db:generate  # Generate Prisma client
npm run db:push     # Push schema changes to database
npm run db:migrate  # Run database migrations
npm run db:studio   # Open Prisma Studio
npm run db:seed     # Seed database with sample data
npm run db:reset    # Reset database and reseed
```

## 📝 Code Quality

The project enforces code quality through:

- **TypeScript**: Strict type checking
- **ESLint**: Code linting with TypeScript rules
- **Prettier**: Code formatting
- **Husky**: Pre-commit hooks
- **Jest**: Unit and integration testing

### Pre-commit Hooks

The project automatically runs these checks before each commit:
- ESLint (with auto-fix)
- Prettier formatting
- TypeScript type checking

## 🛡️ Security

Security features included:

- **Helmet**: Security headers
- **CORS**: Cross-origin resource sharing configuration
- **Rate Limiting**: Request rate limiting
- **Input Validation**: Request validation with Zod
- **Password Hashing**: bcrypt with salt rounds
- **JWT**: Secure token-based authentication
- **SQL Injection Protection**: Prisma ORM with parameterized queries

## 📚 API Documentation

Interactive API documentation is available at `/api-docs` when the server is running. The documentation is automatically generated from OpenAPI/Swagger annotations in the code.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make your changes and add tests
4. Run the test suite: `npm test`
5. Run linting: `npm run lint`
6. Commit your changes: `git commit -am 'Add new feature'`
7. Push to the branch: `git push origin feature/new-feature`
8. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- Check the [API documentation](http://localhost:3000/api-docs)
- Review the test files for usage examples
- Create an issue for bug reports or feature requests

---

Built with ❤️ using TypeScript, Express, Prisma, and modern development tools.