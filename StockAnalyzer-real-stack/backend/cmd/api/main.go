package main

import (
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/handlers"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/middleware"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"halalstocks/pkg/jwt"
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize JWT
	jwt.Init(cfg.JWTSecret)

	// Connect to database
	database, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer database.Close()

	// Initialize repositories
	userRepo := repositories.NewUserRepository(database)
	stockRepo := repositories.NewStockRepository(database)
	fundamentalRepo := repositories.NewFundamentalRepository(database)
	shariahRepo := repositories.NewShariahStatusRepository(database)
	portfolioRepo := repositories.NewPortfolioRepository(database)
	notificationRepo := repositories.NewNotificationRepository(database)
	analystRepo := repositories.NewAnalystRatingRepository(database)
	adRepo := repositories.NewAdRepository(database)
	promoRepo := repositories.NewPromoCodeRepository(database)
	marketRepo := repositories.NewMarketRepository(database)

	// Initialize Services
	shariahEngine := services.NewShariahEngineService()

	// Initialize Market Provider
	var marketProvider marketdata.MarketDataProvider
	switch cfg.StockAPIProvider {
	case "alphavantage", "alpha":
		avp := marketdata.NewAlphaVantageProvider(cfg.AlphaVantageAPIKey)
		avp.SetStore(marketRepo)
		marketProvider = avp
	case "fmp":
		marketProvider = marketdata.NewFMPProvider(cfg.StockAPIKey)
	case "datajockey":
		marketProvider = marketdata.NewDataJockeyProvider(cfg.DataJockeyAPIKey)
	default:
		avp := marketdata.NewAlphaVantageProvider(cfg.AlphaVantageAPIKey)
		avp.SetStore(marketRepo)
		marketProvider = avp
	}

	// Initialize handlers
	authHandler := handlers.NewAuthHandler(userRepo)
	publicHandler := handlers.NewPublicHandler(stockRepo, fundamentalRepo, shariahRepo, analystRepo, shariahEngine)
	userHandler := handlers.NewUserHandler(portfolioRepo, notificationRepo)
	toolsHandler := handlers.NewToolsHandler(portfolioRepo, stockRepo, shariahRepo, fundamentalRepo)
	adsHandler := handlers.NewAdsHandler(adRepo)
	promoHandler := handlers.NewPromoHandler(promoRepo)
	marketHandler := handlers.NewMarketHandler(marketProvider)
	subscriptionHandler := handlers.NewSubscriptionHandler(userRepo)

	// Start background refresh for market provider if it supports it
	if avp, ok := marketProvider.(*marketdata.AlphaVantageProvider); ok {
		avp.StartBackgroundRefresh()
	}

	// Setup router
	router := gin.Default()

	// Compression middleware (gzip responses)
	router.Use(middleware.CompressionMiddleware())

	// CORS middleware
	router.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	})

	// Public routes
	api := router.Group("/api")
	{
		// Health check
		api.GET("/health", func(c *gin.Context) {
			c.JSON(200, gin.H{"status": "ok"})
		})

		// Auth (no caching)
		api.POST("/auth/register", authHandler.Register)
		api.POST("/auth/login", authHandler.Login)

		// Public stock data (with caching)
		stockData := api.Group("")
		stockData.Use(middleware.CacheMiddleware(5 * time.Minute)) // Cache for 5 minutes
		{
			stockData.GET("/search", publicHandler.SearchStocks)
			stockData.GET("/stocks/:ticker", publicHandler.GetStockDetails)
			stockData.GET("/regions/:code/stocks", publicHandler.GetStocksByRegion)
		}

		// Ads (with caching)
		api.GET("/ads", middleware.CacheMiddleware(15*time.Minute), adsHandler.GetAds)

		// Market Data
		api.GET("/market/fear-greed", middleware.CacheMiddleware(1*time.Minute), marketHandler.GetFearAndGreedIndex)
		api.GET("/market/indexes", middleware.CacheMiddleware(1*time.Minute), marketHandler.GetIndexes)
		api.GET("/market/exchange-rate", middleware.CacheMiddleware(1*time.Hour), marketHandler.GetExchangeRate)

		// Public Tools
		tools := api.Group("/tools")
		{
			tools.GET("/dca", toolsHandler.CalculateDCA)
		}
	}

	// Protected routes
	protected := api.Group("/")
	protected.Use(middleware.AuthMiddleware())
	{
		// User
		protected.GET("/user/portfolio", userHandler.GetPortfolio)
		protected.POST("/user/portfolio", userHandler.AddToPortfolio)
		protected.DELETE("/user/portfolio/:stock_id", userHandler.RemoveFromPortfolio)
		protected.GET("/user/notifications", userHandler.GetNotifications)
		protected.PUT("/user/notifications/:id/read", userHandler.MarkNotificationRead)

		// Tools
		protected.GET("/tools/zakat", toolsHandler.CalculateZakat)

		// Promo codes
		protected.POST("/promo/validate", promoHandler.ValidatePromo)

		// Subscriptions
		protected.POST("/subscription/upgrade", subscriptionHandler.Upgrade)
		protected.POST("/subscription/cancel", subscriptionHandler.Cancel)
	}

	// Start server
	log.Printf("Starting server on port %s", cfg.ServerPort)
	if err := router.Run(":" + cfg.ServerPort); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
