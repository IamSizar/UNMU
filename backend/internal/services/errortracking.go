package services

import (
	"log"
	"os"
	"strings"
	"time"

	sentry "github.com/getsentry/sentry-go"
	sentrygin "github.com/getsentry/sentry-go/gin"
	"github.com/gin-gonic/gin"
)

// InitErrorTracking wires Sentry for the backend. Soft-fail: when
// SENTRY_DSN isn't set, this logs one line and returns a no-op gin
// middleware — matching the same graceful-degrade pattern used for FCM
// (NewFCMSender) and email (NewEmailSender) elsewhere in this codebase,
// so a missing API key never blocks the server from starting.
//
// Env vars:
//
//	SENTRY_DSN          (required to actually report — no-op without it)
//	SENTRY_ENVIRONMENT  (optional, default "development")
//	APP_VERSION         (optional — tags events with a release identifier
//	                      if set; falls back to "unknown" otherwise)
func InitErrorTracking() gin.HandlerFunc {
	dsn := strings.TrimSpace(os.Getenv("SENTRY_DSN"))
	if dsn == "" {
		log.Println("[errortracking] SENTRY_DSN not set — error monitoring disabled")
		return func(c *gin.Context) { c.Next() } // no-op passthrough
	}

	env := strings.TrimSpace(os.Getenv("SENTRY_ENVIRONMENT"))
	if env == "" {
		env = "development"
	}
	release := strings.TrimSpace(os.Getenv("APP_VERSION"))
	if release == "" {
		release = "unknown"
	}

	err := sentry.Init(sentry.ClientOptions{
		Dsn:              dsn,
		Environment:      env,
		Release:          release,
		AttachStacktrace: true,
		// SendDefaultPII defaults to false, but sentrygin's request capture
		// still attaches request headers regardless — Authorization/Cookie/
		// API-key headers must be scrubbed explicitly (Section 8: never log
		// tokens, passwords, or PII). BeforeSend runs on every event,
		// including ones from panics captured by sentrygin.
		BeforeSend: func(event *sentry.Event, hint *sentry.EventHint) *sentry.Event {
			scrubHeaders(event)
			return event
		},
		// Traces are expensive relative to their value here — this is
		// error monitoring, not performance monitoring. Leave sampling at
		// its zero value (no tracing) unless that need arises separately.
	})
	if err != nil {
		log.Printf("[errortracking] Sentry init failed, error monitoring disabled: %v", err)
		return func(c *gin.Context) { c.Next() }
	}

	log.Printf("[errortracking] Sentry initialized (environment=%s, release=%s)", env, release)

	// NOTE: there is no sentry.Flush() on shutdown — main.go currently
	// runs via router.Run() with no graceful-shutdown handler (no
	// signal.Notify/http.Server.Shutdown), so there's no hook to flush
	// from. WaitForDelivery:false below means the last few events before
	// a SIGTERM could be dropped. Add a flush call if/when main.go grows
	// a graceful shutdown path.

	// Repanic: true re-raises after capturing so gin.Recovery() (already
	// registered via gin.Default() in main.go) still returns the usual
	// 500 — this middleware's only job is to report, not to replace
	// existing panic-recovery behavior.
	return sentrygin.New(sentrygin.Options{Repanic: true, WaitForDelivery: false, Timeout: 3 * time.Second})
}

// sensitiveHeaders are stripped from every event before it leaves the
// process — sentrygin attaches request headers regardless of
// SendDefaultPII, so this is the actual enforcement point, not that flag.
var sensitiveHeaders = []string{
	"Authorization", "Cookie", "X-Api-Key", "X-Auth-Token", "X-Csrf-Token",
}

// scrubHeaders removes auth-bearing headers/cookies and the raw request
// body from an event's Request block. The body (event.Request.Data) is
// dropped entirely rather than selectively redacted — login/password-
// change/payment endpoints could carry credentials in the body, and this
// service has no per-route knowledge of which fields are sensitive.
func scrubHeaders(event *sentry.Event) {
	if event == nil || event.Request == nil {
		return
	}
	for _, h := range sensitiveHeaders {
		delete(event.Request.Headers, h)
	}
	event.Request.Cookies = ""
	event.Request.Data = ""
}

// CaptureError reports a non-panic error from a background job (the
// ingestion crons, the weekly digest, etc.) that isn't running inside a
// gin request and so never passes through the middleware above. Safe to
// call even when Sentry was never initialized — sentry-go's global hub is
// a no-op until Init succeeds.
func CaptureError(err error, tags map[string]string) {
	if err == nil {
		return
	}
	sentry.WithScope(func(scope *sentry.Scope) {
		for k, v := range tags {
			scope.SetTag(k, v)
		}
		sentry.CaptureException(err)
	})
}
