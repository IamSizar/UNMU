// Package handlers — Firebase-OAuth sign-in bridge.
//
// The mobile app signs the user in with Google or Apple via the
// firebase_auth SDK, receives a Firebase ID token, and POSTs it to
//
//	POST /api/auth/oauth/firebase
//	{ "idToken": "<jwt>" }
//
// We verify that token against Firebase's public keys using the Firebase
// Admin SDK for Go, then either:
//
//  1. Find the user already linked to that Firebase UID (`firebase_uid`
//     column from migration 0031) — return our normal JWT.
//  2. Find a user with the same email — stamp their firebase_uid for
//     next time, return our JWT (lets existing email/password users adopt
//     Google/Apple without re-registering).
//  3. Create a brand-new user row with the verified email + name + UID
//     — return our JWT.
//
// In all three cases the response shape matches `/api/auth/login` so the
// mobile auth controller doesn't need to know what kind of credential
// produced the session.
package handlers

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	firebaseauth "firebase.google.com/go/v4/auth"
	"github.com/gin-gonic/gin"
	"google.golang.org/api/option"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/pkg/jwt"
)

// FirebaseAuthHandler — wraps the Admin SDK auth client + user repo.
// Constructed once in main.go and registered on the public auth routes.
type FirebaseAuthHandler struct {
	authClient *firebaseauth.Client
	userRepo   *repositories.UserRepository
	audits     *repositories.AuditRepository
}

// NewFirebaseAuthHandler boots the Firebase Admin SDK using one of two
// credential strategies:
//
//   - GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
//     (recommended — the canonical Firebase pattern)
//   - FIREBASE_PROJECT_ID + Application Default Credentials
//     (works on GCP runtime where metadata server provides creds)
//
// If neither is configured we return (nil, err) and main.go logs a
// warning but keeps the rest of the server up. That way you can keep
// running the old email/password endpoints while you finish setting up
// Firebase — only the new /api/auth/oauth/firebase route fails.
func NewFirebaseAuthHandler(
	userRepo *repositories.UserRepository,
	audits *repositories.AuditRepository,
) (*FirebaseAuthHandler, error) {
	projectID := strings.TrimSpace(os.Getenv("FIREBASE_PROJECT_ID"))
	if projectID == "" {
		return nil, fmt.Errorf("FIREBASE_PROJECT_ID env var is required")
	}

	ctx := context.Background()
	cfg := &firebase.Config{ProjectID: projectID}

	var app *firebase.App
	var err error
	if path := strings.TrimSpace(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")); path != "" {
		app, err = firebase.NewApp(ctx, cfg, option.WithCredentialsFile(path))
	} else {
		// Falls back to Application Default Credentials — works on Cloud
		// Run / GCE / GKE without any extra env var.
		app, err = firebase.NewApp(ctx, cfg)
	}
	if err != nil {
		return nil, fmt.Errorf("firebase init: %w", err)
	}

	client, err := app.Auth(ctx)
	if err != nil {
		return nil, fmt.Errorf("firebase auth client: %w", err)
	}

	return &FirebaseAuthHandler{
		authClient: client,
		userRepo:   userRepo,
		audits:     audits,
	}, nil
}

// FirebaseOAuthRequest — the mobile app's idToken landing here.
type FirebaseOAuthRequest struct {
	IDToken string `json:"idToken" binding:"required"`
}

// OAuth — POST /api/auth/oauth/firebase
//
//	{ "idToken": "<jwt from firebase_auth>" }
//
// Returns the same AuthResponse shape as /api/auth/login.
func (h *FirebaseAuthHandler) OAuth(c *gin.Context) {
	var req FirebaseOAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 5-second cap on the verification round-trip. Firebase's pubkey
	// fetch is cached so successive calls are sub-ms; the 5s is for the
	// rare cold-cache scenario.
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	tok, err := h.authClient.VerifyIDToken(ctx, req.IDToken)
	if err != nil {
		// Don't leak the underlying parse error to the client — it
		// includes timing details that aren't useful and may confuse a
		// well-meaning user. Server logs get the real message.
		log.Printf("[firebase_oauth] VerifyIDToken failed: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{
			"error": "Invalid or expired Firebase token",
			"code":  "FIREBASE_TOKEN_INVALID",
		})
		return
	}

	// Pull the verified claims. Firebase wraps email + name + picture
	// in a `firebase.identities` substructure too, but the top-level
	// `email` / `name` claims are the same values and easier to read.
	uid := tok.UID
	email, _ := tok.Claims["email"].(string)
	name, _ := tok.Claims["name"].(string)
	emailVerified, _ := tok.Claims["email_verified"].(bool)
	// SignInProvider is one of "google.com" / "apple.com" /
	// "password" / "anonymous" — surfaced in audit metadata so we can
	// later answer "how many users sign in with Apple vs Google?"
	provider := tok.Firebase.SignInProvider

	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		// Apple in particular can omit the email after the first sign-in
		// (the user has the option to hide their email and Apple only
		// surfaces it once). We require a non-empty email because every
		// user row in our DB has email NOT NULL.
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Firebase token has no email claim — re-link with email scope",
			"code":  "FIREBASE_NO_EMAIL",
		})
		return
	}

	// 1. Existing user already linked to this UID — fast path.
	user, err := h.userRepo.GetByFirebaseUID(uid)
	if err != nil {
		log.Printf("[firebase_oauth] GetByFirebaseUID: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Lookup failed"})
		return
	}

	// 2. No row by UID yet — see if a row exists by email, and adopt it.
	if user == nil {
		existing, err := h.userRepo.GetByEmail(email)
		if err != nil {
			log.Printf("[firebase_oauth] GetByEmail: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Lookup failed"})
			return
		}
		if existing != nil {
			// Pass `name` through so LinkFirebaseUID can opportunistically
			// fill in users.name when the existing row had no display name
			// set (a common case for users who registered via email but
			// never edited their profile).
			if err := h.userRepo.LinkFirebaseUID(existing.ID, uid, name); err != nil {
				log.Printf("[firebase_oauth] LinkFirebaseUID: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Link failed"})
				return
			}
			// Reflect the freshly-stamped name in the response without
			// a second DB round-trip — only when the original row had
			// none and the OAuth provider gave us one.
			if (!existing.Name.Valid || existing.Name.String == "") && name != "" {
				existing.Name = sql.NullString{String: name, Valid: true}
			}
			user = existing
		}
	}

	// 3. Brand-new user — create the row.
	if user == nil {
		// Only accept email-verified tokens for fresh signups. Email/
		// password users go through our 6-digit verification flow; for
		// OAuth we trust Google + Apple to have verified the address.
		// (Anonymous Firebase sign-in would have email_verified=false —
		// reject it.)
		if !emailVerified {
			c.JSON(http.StatusForbidden, gin.H{
				"error": "Firebase identity has unverified email",
				"code":  "FIREBASE_EMAIL_UNVERIFIED",
			})
			return
		}
		newUser, err := h.userRepo.CreateFromFirebase(email, name, uid)
		if err != nil {
			log.Printf("[firebase_oauth] CreateFromFirebase: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
			return
		}
		user = newUser
	}

	// Issue our own JWT — same generator and TTL as /api/auth/login so
	// the rest of the API (middleware, refresh logic, etc.) stays
	// unchanged.
	tokenStr, err := jwt.GenerateToken(user.ID, user.Email)
	if err != nil {
		log.Printf("[firebase_oauth] GenerateToken: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to issue session"})
		return
	}

	// Audit — same event type as a regular login. The metadata
	// distinguishes OAuth from password sign-in so downstream reports
	// can break it down by provider.
	if h.audits != nil {
		_, _ = h.audits.Write(
			models.AuditAuthLogin, models.SeverityInfo,
			&user.ID, ptrStr(fmt.Sprintf("%d", user.ID)), ptrStr("user"),
			fmt.Sprintf("%s logged in via Firebase (%s)", user.Email, provider),
			map[string]any{
				"role":     user.Role,
				"provider": provider,
				"method":   "firebase_oauth",
			},
		)
	}

	displayName := ""
	if user.Name.Valid {
		displayName = user.Name.String
	}
	expertID := ""
	if user.ExpertID.Valid {
		expertID = user.ExpertID.String
	}

	// needsOnboarding is true when this OAuth user has never set a local
	// password (still carries the sentinel). The app routes them to the
	// onboarding screen to set a name + password (so they can later sign
	// in with email/password too). Returning users — and email/password
	// users who adopted OAuth — already have a real hash, so it's false
	// and they drop straight into the app. Survives a mid-onboarding app
	// kill: the sentinel is only replaced once onboarding completes, so
	// the next OAuth sign-in re-prompts.
	needsOnboarding := user.PasswordHash == repositories.OAuthOnlyPasswordSentinel

	c.JSON(http.StatusOK, gin.H{
		"token": tokenStr,
		"user": UserResponse{
			ID:       user.ID,
			Email:    user.Email,
			Name:     displayName,
			Role:     user.Role,
			ExpertID: expertID,
			Tier:     user.SubscriptionTier,
		},
		"needsOnboarding": needsOnboarding,
	})
}
