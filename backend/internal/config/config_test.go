package config

import (
	"strings"
	"testing"
)

// setBase gives Load a provider that needs no API key.
func setBase(t *testing.T) {
	t.Setenv("STOCK_API_PROVIDER", "mock")
}

func TestLoad_RefusesMissingJWTSecretOutsideDev(t *testing.T) {
	setBase(t)
	t.Setenv("APP_ENV", "")
	t.Setenv("JWT_SECRET", "")
	if _, err := Load(); err == nil || !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Fatalf("want JWT_SECRET error, got %v", err)
	}
}

func TestLoad_RefusesDefaultOrShortJWTSecret(t *testing.T) {
	setBase(t)
	t.Setenv("APP_ENV", "production")
	for _, s := range []string{"change-me-in-production", "short-secret"} {
		t.Setenv("JWT_SECRET", s)
		if _, err := Load(); err == nil {
			t.Errorf("JWT_SECRET=%q accepted, want error", s)
		}
	}
}

func TestLoad_AcceptsStrongJWTSecret(t *testing.T) {
	setBase(t)
	t.Setenv("APP_ENV", "production")
	t.Setenv("JWT_SECRET", strings.Repeat("k", 32))
	if _, err := Load(); err != nil {
		t.Fatalf("strong secret rejected: %v", err)
	}
}

func TestLoad_DevKeepsDefaultSecret(t *testing.T) {
	setBase(t)
	t.Setenv("APP_ENV", "development")
	t.Setenv("JWT_SECRET", "")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("dev load failed: %v", err)
	}
	if cfg.JWTSecret == "" {
		t.Fatal("dev should fall back to a local secret")
	}
}

func TestLoad_ParsesCORSOrigins(t *testing.T) {
	setBase(t)
	t.Setenv("APP_ENV", "development")
	t.Setenv("CORS_ALLOWED_ORIGINS", " https://a.example , https://b.example/ ,,")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"https://a.example", "https://b.example"}
	if strings.Join(cfg.CORSAllowedOrigins, "|") != strings.Join(want, "|") {
		t.Fatalf("origins = %v, want %v", cfg.CORSAllowedOrigins, want)
	}
}

func TestLoad_ClientIPHeader(t *testing.T) {
	setBase(t)
	t.Setenv("APP_ENV", "development")
	cases := map[string]string{"": "X-Real-IP", "none": "", "NONE": "", " CF-Connecting-IP ": "CF-Connecting-IP"}
	for raw, want := range cases {
		t.Setenv("TRUSTED_CLIENT_IP_HEADER", raw)
		cfg, err := Load()
		if err != nil {
			t.Fatal(err)
		}
		if cfg.TrustedClientIPHeader != want {
			t.Errorf("TRUSTED_CLIENT_IP_HEADER=%q → %q, want %q", raw, cfg.TrustedClientIPHeader, want)
		}
	}
}
