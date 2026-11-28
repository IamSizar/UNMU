package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"halalstocks/internal/appenv"

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

	// CORSAllowedOrigins are the browser origins (the admin dashboard) that
	// may call the API, from CORS_ALLOWED_ORIGINS (comma-separated). Native
	// apps send no Origin and are unaffected.
	CORSAllowedOrigins []string

	// TrustedClientIPHeader is the ONE header believed for the caller's IP
	// (rate limiting). Railway's edge sets and overwrites X-Real-IP. Set
	// TRUSTED_CLIENT_IP_HEADER to another platform's header, or to "none"
	// to use only the TCP peer address.
	TrustedClientIPHeader string

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

	// Daily jobs (docs/pulse/AUTODRAFT.md). Both are off unless set to "true".
	DailyScreeningEnabled bool
	DailyScreeningHourUTC int
	PulseAutodraftEnabled bool
	PulseAutodraftHourUTC int
	PulseAutodraftModel   string
	GeminiAPIKey          string

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
		JWTSecret:  getEnv("JWT_SECRET", ""),

		CORSAllowedOrigins: parseOrigins(os.Getenv("CORS_ALLOWED_ORIGINS")),

		TrustedClientIPHeader: parseClientIPHeader(os.Getenv("TRUSTED_CLIENT_IP_HEADER")),

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

		DailyScreeningEnabled: getEnv("DAILY_SCREENING_ENABLED", "") == "true",
		DailyScreeningHourUTC: getEnvInt("DAILY_SCREENING_HOUR_UTC", 2),
		PulseAutodraftEnabled: getEnv("PULSE_AUTODRAFT_ENABLED", "") == "true",
		PulseAutodraftHourUTC: getEnvInt("PULSE_AUTODRAFT_HOUR_UTC", 3),
		PulseAutodraftModel:   getEnv("PULSE_AUTODRAFT_MODEL", ""),
		GeminiAPIKey:          getEnv("GEMINI_API_KEY", ""),

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

	if err := cfg.checkJWTSecret(); err != nil {
		return nil, err
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

// devJWTSecret is used only when APP_ENV is a dev environment and no
// JWT_SECRET is set, so a local API starts without setup.
const devJWTSecret = "dev-only-jwt-secret-not-for-real-deploys"

// minJWTSecretLen: HS256 keys shorter than 32 bytes are brute-forceable.
const minJWTSecretLen = 32

// checkJWTSecret refuses to start a real deploy without a strong secret.
// Before 2026-11-27 a missing JWT_SECRET silently became a public default,
// which would let anyone mint tokens for any user.
func (c *Config) checkJWTSecret() error {
	if appenv.IsDev() {
		if c.JWTSecret == "" {
			c.JWTSecret = devJWTSecret
		}
		return nil
	}
	switch {
	case c.JWTSecret == "":
		return fmt.Errorf("JWT_SECRET is required (set APP_ENV=development for local runs)")
	case c.JWTSecret == "change-me-in-production" || c.JWTSecret == devJWTSecret:
		return fmt.Errorf("JWT_SECRET is a known default; set a random secret")
	case len(c.JWTSecret) < minJWTSecretLen:
		return fmt.Errorf("JWT_SECRET must be at least %d characters", minJWTSecretLen)
	}
	return nil
}

// parseOrigins splits a comma-separated origin list, trimming spaces and a
// trailing slash (browsers send origins without one).
func parseOrigins(raw string) []string {
	var out []string
	for _, part := range strings.Split(raw, ",") {
		o := strings.TrimSuffix(strings.TrimSpace(part), "/")
		if o != "" {
			out = append(out, o)
		}
	}
	return out
}

// defaultClientIPHeader is what Railway's public edge sets for the client.
const defaultClientIPHeader = "X-Real-IP"

// parseClientIPHeader: unset → Railway's header; "none" → trust no header.
func parseClientIPHeader(raw string) string {
	v := strings.TrimSpace(raw)
	switch {
	case v == "":
		return defaultClientIPHeader
	case strings.EqualFold(v, "none"):
		return ""
	}
	return v
}
