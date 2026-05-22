package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	// Database
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSSLMode  string

	// Server
	ServerPort string
	JWTSecret  string

	// Stock API (FMP, Alpha Vantage, or DataJockey)
	StockAPIKey      string
	StockAPIBaseURL  string
	StockAPIProvider string
	AlphaVantageAPIKey string // For Alpha Vantage provider
	DataJockeyAPIKey string   // For DataJockey provider

	// AI Service
	AIServiceURL string
	AIServiceKey string

	// Rate Limiting
	RateLimitRequests int
	RateLimitWindow   int
}

func Load() (*Config, error) {
	// Load .env file if it exists (ignore error if file doesn't exist)
	_ = godotenv.Load()

	cfg := &Config{
		// Database defaults
		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", os.Getenv("USER")),
		DBPassword: getEnv("DB_PASSWORD", ""),
		DBName:     getEnv("DB_NAME", "halalstocks"),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),

		// Server defaults
		ServerPort: getEnv("SERVER_PORT", "8080"),
		JWTSecret:  getEnv("JWT_SECRET", "change-me-in-production"),

		// Stock API (FMP, Alpha Vantage, or DataJockey)
		StockAPIKey:        getEnv("STOCK_API_KEY", ""),
		StockAPIBaseURL:    getEnv("STOCK_API_BASE_URL", "https://financialmodelingprep.com/api/v3"),
		StockAPIProvider:   getEnv("STOCK_API_PROVIDER", "alphavantage"), // Default to Alpha Vantage
		AlphaVantageAPIKey: getEnv("ALPHA_VANTAGE_API_KEY", ""),
		DataJockeyAPIKey:   getEnv("DATAJOCKEY_API_KEY", ""),

		// AI Service
		AIServiceURL: getEnv("AI_SERVICE_URL", "http://localhost:8000"),
		AIServiceKey: getEnv("AI_SERVICE_KEY", ""),

		// Rate Limiting
		RateLimitRequests: 100,
		RateLimitWindow:   60,
	}

	// Validate API key based on provider
	if cfg.StockAPIProvider == "alphavantage" || cfg.StockAPIProvider == "alpha" {
		if cfg.AlphaVantageAPIKey == "" {
			return nil, fmt.Errorf("ALPHA_VANTAGE_API_KEY is required when using Alpha Vantage provider")
		}
	} else if cfg.StockAPIProvider == "fmp" {
		if cfg.StockAPIKey == "" {
			return nil, fmt.Errorf("STOCK_API_KEY is required when using FMP provider")
		}
	} else if cfg.StockAPIProvider == "datajockey" {
		if cfg.DataJockeyAPIKey == "" {
			return nil, fmt.Errorf("DATAJOCKEY_API_KEY is required when using DataJockey provider")
		}
	}

	return cfg, nil
}

func (c *Config) DatabaseDSN() string {
	if c.DBPassword == "" {
		return fmt.Sprintf("host=%s port=%s user=%s dbname=%s sslmode=%s",
			c.DBHost, c.DBPort, c.DBUser, c.DBName, c.DBSSLMode)
	}
	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName, c.DBSSLMode)
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
