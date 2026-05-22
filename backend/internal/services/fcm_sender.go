package services

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// FCMSender wraps the Firebase Admin SDK's messaging client. It's a
// thin layer because the SDK already handles HTTP / OAuth / retries —
// our job is just to construct the messages, batch them under the
// 500-per-call FCM cap, and surface invalid tokens so the caller can
// prune them.
//
// When Firebase credentials aren't configured (env var not set or
// JSON missing) NewFCMSender returns (nil, err) and main.go logs a
// warning. The HTTP handler then returns 503 for /admin/push/send —
// same graceful-degrade pattern we use for S3.
type FCMSender struct {
	client *messaging.Client
}

// NewFCMSender constructs the messaging client.
//
//   - FIREBASE_PROJECT_ID         (required, e.g. "unmuapp")
//   - GOOGLE_APPLICATION_CREDENTIALS  (optional path to service account
//     JSON. When unset, Application Default Credentials are used —
//     fine on Cloud Run / GCE.)
//
// The same env vars are read by the firebase_auth handler so a single
// service account JSON powers both subsystems.
func NewFCMSender(ctx context.Context) (*FCMSender, error) {
	projectID := strings.TrimSpace(os.Getenv("FIREBASE_PROJECT_ID"))
	if projectID == "" {
		return nil, fmt.Errorf("FIREBASE_PROJECT_ID env var is required")
	}

	cfg := &firebase.Config{ProjectID: projectID}
	var app *firebase.App
	var err error
	if path := strings.TrimSpace(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")); path != "" {
		app, err = firebase.NewApp(ctx, cfg, option.WithCredentialsFile(path))
	} else {
		app, err = firebase.NewApp(ctx, cfg)
	}
	if err != nil {
		return nil, fmt.Errorf("firebase init: %w", err)
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, fmt.Errorf("firebase messaging client: %w", err)
	}
	return &FCMSender{client: client}, nil
}

// SendResult mirrors the per-token outcome of a batch send. The admin
// endpoint exposes these counts in its response so an operator running
// a broadcast can see how many devices got the message AND which
// tokens to consider expired.
type SendResult struct {
	SuccessCount int `json:"success_count"`
	FailureCount int `json:"failure_count"`
	// InvalidTokens carries tokens that came back as
	// registration-token-not-registered / invalid-argument — the
	// caller (admin handler) deletes those from the DB so the next
	// broadcast doesn't waste a quota slot.
	InvalidTokens []string `json:"invalid_tokens,omitempty"`
}

// SendToTokens broadcasts a single (title, body, data) payload to
// many devices. FCM caps multicast at 500 tokens per call, so we
// batch.
//
// data is an arbitrary string map — clients can read it via
// FirebaseMessaging.onMessage `.data` for deep-linking
// ("Open post /p/42" → data: {"post_id":"42"}).
func (s *FCMSender) SendToTokens(
	ctx context.Context,
	tokens []string,
	title, body string,
	data map[string]string,
) (SendResult, error) {
	if s == nil {
		return SendResult{}, fmt.Errorf("fcm: nil sender")
	}
	if len(tokens) == 0 {
		return SendResult{}, nil
	}

	const batchSize = 500
	result := SendResult{}
	for i := 0; i < len(tokens); i += batchSize {
		end := i + batchSize
		if end > len(tokens) {
			end = len(tokens)
		}
		batch := tokens[i:end]
		msg := &messaging.MulticastMessage{
			Tokens: batch,
			Notification: &messaging.Notification{
				Title: title,
				Body:  body,
			},
			Data: data,
			// APS payload for iOS — mirror the title/body so iOS
			// shows the banner even when the app is fully killed.
			APNS: &messaging.APNSConfig{
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{
						Sound: "default",
						Alert: &messaging.ApsAlert{Title: title, Body: body},
					},
				},
			},
			Android: &messaging.AndroidConfig{
				Priority: "high",
				Notification: &messaging.AndroidNotification{
					Sound: "default",
				},
			},
		}
		resp, err := s.client.SendEachForMulticast(ctx, msg)
		if err != nil {
			// SDK-level error — bail out, partial state is fine
			// since each batch is independent.
			return result, fmt.Errorf("fcm batch %d-%d: %w", i, end, err)
		}
		result.SuccessCount += resp.SuccessCount
		result.FailureCount += resp.FailureCount
		// Surface invalid tokens so the caller can prune them.
		for j, r := range resp.Responses {
			if r.Error == nil {
				continue
			}
			if messaging.IsRegistrationTokenNotRegistered(r.Error) ||
				messaging.IsInvalidArgument(r.Error) {
				result.InvalidTokens = append(result.InvalidTokens, batch[j])
			} else {
				log.Printf("[fcm] non-fatal send error for token %s: %v",
					truncToken(batch[j]), r.Error)
			}
		}
	}
	return result, nil
}

// truncToken shortens a FCM token for logging — full tokens are 152+
// chars which clogs logs. First 8 chars are enough to identify a
// device across log lines without leaking the whole secret.
func truncToken(t string) string {
	if len(t) <= 12 {
		return t
	}
	return t[:8] + "…"
}
