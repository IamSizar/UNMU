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

// Env vars shared by every Sentry entry point in this package:
//
//	SENTRY_DSN          (required to actually report — no-op without it)
//	SENTRY_ENVIRONMENT  (optional, default "development")
//	APP_VERSION         (optional — tags events with a release identifier
//	                      if set; falls back to "unknown" otherwise)

// InitErrorTracking wires Sentry for the API server. Soft-fail: when
// SENTRY_DSN isn't set, this logs one line and returns a no-op gin
// middleware — matching the same graceful-degrade pattern used for FCM
// (NewFCMSender) and email (NewEmailSender) elsewhere in this codebase,
// so a missing API key never blocks the server from starting.
func InitErrorTracking() gin.HandlerFunc {
	if !initSentry() {
		return func(c *gin.Context) { c.Next() } // no-op passthrough
	}

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

// InitStandaloneErrorTracking wires Sentry for a non-HTTP process (the
// cron jobs — ingest_eodhd, weekly_digest, etc.). Same soft-fail behavior
// and env vars as InitErrorTracking, just without the gin middleware:
// call this once near the top of main(), then use CaptureError for
// individual failures and FlushErrorTracking before the process exits
// (including right before any log.Fatalf, which calls os.Exit and would
// otherwise drop whatever hasn't been sent yet).
//
// Returns whether Sentry actually initialized, so callers can decide
// whether calling FlushErrorTracking is worth the wait.
func InitStandaloneErrorTracking() bool {
	return initSentry()
}

// FlushErrorTracking blocks up to timeout for any queued events to be
// sent. A cron process that just calls CaptureError and then exits (or
// os.Exit via log.Fatalf) needs this — there's no long-running gin server
// keeping the process alive for Sentry's background sender to catch up.
func FlushErrorTracking(timeout time.Duration) {
	sentry.Flush(timeout)
}

func initSentry() bool {
	dsn := strings.TrimSpace(os.Getenv("SENTRY_DSN"))
	if dsn == "" {
		log.Println("[errortracking] SENTRY_DSN not set — error monitoring disabled")
		return false
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
		return false
	}

	log.Printf("[errortracking] Sentry initialized (environment=%s, release=%s)", env, release)
	return true
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
