// Package appenv answers one question in one place: is this a development
// deploy? Dev-only behaviour (the /dev impersonation routes, verification
// codes and password-reset tokens echoed in API responses, a built-in JWT
// secret) is enabled ONLY when APP_ENV explicitly names a dev environment.
// Unset, "production", "staging" or anything else is treated as a real
// deploy, so forgetting to set APP_ENV fails safe.
package appenv

import (
	"os"
	"strings"
)

// IsDev reports whether APP_ENV is development, dev, local or test.
func IsDev() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("APP_ENV"))) {
	case "development", "dev", "local", "test":
		return true
	}
	return false
}
