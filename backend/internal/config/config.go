package config

import (
	"fmt"
	"os"
	"strconv"

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
	EODHDAPIKey      string   // For EODHD provider (eodhd.com)

	// AI Service
	AIServiceURL string
	AIServiceKey string

	// Rate Limiting
	RateLimitRequests int
	RateLimitWindow   int

	// AWS S3 — when AWSS3Bucket is non-empty the upload handler stores
	// media in S3 and returns pre-signed URLs. Empty bucket = local-disk
	// fallback (the original behavior), so dev machines without AWS keys
	// keep working without any changes.
	AWSRegion            string
	AWSS3Bucket          string
	AWSAccessKeyID       string
	AWSSecretAccessKey   string
	AWSS3PresignGetHours int
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
		EODHDAPIKey:        getEnv("EODHD_API_KEY", ""),

		// AI Service
		AIServiceURL: getEnv("AI_SERVICE_URL", "http://localhost:8000"),
		AIServiceKey: getEnv("AI_SERVICE_KEY", ""),

		// Rate Limiting
		RateLimitRequests: 100,
		RateLimitWindow:   60,

		// AWS S3 — all four are optional; the upload handler falls back
		// to on-disk storage when AWSS3Bucket is empty. TTL of 168h is
		// the SigV4 maximum for pre-signed GETs (7 days).
		AWSRegion:            getEnv("AWS_REGION", ""),
		AWSS3Bucket:          getEnv("AWS_S3_BUCKET", ""),
		AWSAccessKeyID:       getEnv("AWS_ACCESS_KEY_ID", ""),
		AWSSecretAccessKey:   getEnv("AWS_SECRET_ACCESS_KEY", ""),
		AWSS3PresignGetHours: getEnvInt("AWS_S3_PRESIGN_GET_TTL_HOURS", 168),
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
	} else if cfg.StockAPIProvider == "eodhd" {
		if cfg.EODHDAPIKey == "" {
			return nil, fmt.Errorf("EODHD_API_KEY is required when using EODHD provider")
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

// getEnvInt reads an env var as int, falling back to defaultValue when the
// var is unset or unparseable. Used for tunables (TTLs, limits) that are
// optional knobs on top of sensible defaults.
func getEnvInt(key string, defaultValue int) int {
	raw := os.Getenv(key)
	if raw == "" {
		return defaultValue
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return defaultValue
	}
	return n
}
