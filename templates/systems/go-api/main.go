package main

import (
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"

	"{{PROJECT_NAME}}/internal/config"
	"{{PROJECT_NAME}}/internal/handlers"
	"{{PROJECT_NAME}}/internal/middleware"
	"{{PROJECT_NAME}}/pkg/database"
)

func main() {
	// Load environment variables
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using system environment variables")
	}

	// Load configuration
	cfg := config.Load()

	// Initialize database
	db, err := database.Initialize(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Set Gin mode
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Initialize router
	router := gin.New()

	// Global middleware
	router.Use(gin.Logger())
	router.Use(gin.Recovery())
	router.Use(middleware.CORS())

	// Health check endpoint
	router.GET("/health", handlers.HealthCheck)

	// API routes
	apiV1 := router.Group("/api/v1")
	{
		// Public routes
		apiV1.GET("/status", handlers.GetStatus)
		apiV1.POST("/auth/login", handlers.Login)
		apiV1.POST("/auth/register", handlers.Register)

		// Protected routes
		protected := apiV1.Group("/")
		protected.Use(middleware.AuthRequired())
		{
			protected.GET("/profile", handlers.GetProfile)
			protected.PUT("/profile", handlers.UpdateProfile)
			protected.GET("/users", handlers.GetUsers)
		}
	}

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("🚀 {{PROJECT_NAME}} server starting on port %s", port)
	log.Printf("📚 API Documentation: http://localhost:%s/api/v1/status", port)
	log.Printf("💚 Health Check: http://localhost:%s/health", port)

	if err := router.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}