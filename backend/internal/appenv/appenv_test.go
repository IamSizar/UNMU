package appenv

import "testing"

// Dev-only behaviour (impersonation routes, verification codes and reset
// tokens in API responses) must be OFF unless APP_ENV explicitly says dev.
// Before 2026-11-27 an unset APP_ENV counted as dev.
func TestIsDev(t *testing.T) {
	cases := map[string]bool{
		"":              false,
		"production":    false,
		"staging":       false,
		"prod":          false,
		"development":   true,
		"dev":           true,
		"local":         true,
		"test":          true,
		" Development ": true,
	}
	for env, want := range cases {
		t.Setenv("APP_ENV", env)
		if got := IsDev(); got != want {
			t.Errorf("APP_ENV=%q: IsDev()=%v, want %v", env, got, want)
		}
	}
}
