package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// ProfileHandler owns every endpoint under /me/* that touches the user's
// row directly: profile updates, change password, change email,
// delete-account, and notification preferences.
//
// We share one handler so we can reuse the same UserRepo + EmailSender
// + audit logger across all flows without re-plumbing them at the
// router layer.
type ProfileHandler struct {
	users        *repositories.UserRepository
	emails       *repositories.EmailVerificationRepository
	emailChanges *repositories.EmailChangeRequestRepository
	prefs        *repositories.NotificationPrefsRepository
	emailSender  *services.EmailSender // nullable — soft-fails when SMTP unset
	audits       *repositories.AuditRepository
}

func NewProfileHandler(
	users *repositories.UserRepository,
	emails *repositories.EmailVerificationRepository,
	emailChanges *repositories.EmailChangeRequestRepository,
	prefs *repositories.NotificationPrefsRepository,
	emailSender *services.EmailSender,
	audits *repositories.AuditRepository,
) *ProfileHandler {
	return &ProfileHandler{
		users:        users,
		emails:       emails,
		emailChanges: emailChanges,
		prefs:        prefs,
		emailSender:  emailSender,
		audits:       audits,
	}
}

// ─── /me/profile (PATCH) ────────────────────────────────────────────────

// profileBody — request body for PATCH /me/profile.
//
//	name      — optional. Sending "" clears the column to NULL.
//	avatarUrl — optional. Sending "" clears. Phase 2.4 will produce S3
//	            URLs here; for now the column exists but is only set
//	            when the client provides a URL (avatar persistence still
//	            happens locally via SharedPreferences in 1.8's scope).
type profileBody struct {
	Name      *string `json:"name"`
	AvatarURL *string `json:"avatarUrl"`
}

// userJSON is the public-facing shape returned by /me/profile. Mirrors
// the AuthResponse.User struct used by /login + /verify-email so the
// Flutter `User` model deserializes both shapes identically.
type userJSON struct {
	ID        int64  `json:"id"`
	Email     string `json:"email"`
	Name      string `json:"name,omitempty"`
	AvatarURL string `json:"avatarUrl,omitempty"`
	Role      string `json:"role,omitempty"`
	ExpertID  string `json:"expertId,omitempty"`
	Tier      string `json:"subscriptionTier,omitempty"`
	Locale    string `json:"locale,omitempty"`
}

func userToJSON(u *models.User) userJSON {
	out := userJSON{
		ID:     u.ID,
		Email:  u.Email,
		Role:   u.Role,
		Tier:   u.SubscriptionTier,
		Locale: u.Locale,
	}
	if u.Name.Valid {
		out.Name = u.Name.String
	}
	if u.AvatarURL.Valid {
		out.AvatarURL = u.AvatarURL.String
	}
	if u.ExpertID.Valid {
		out.ExpertID = u.ExpertID.String
	}
	return out
}

// Update — PATCH /api/me/profile
//
// Partial update. Empty strings clear nullable columns. Returns the
// refreshed user record in the same shape as login / verify-email.
func (h *ProfileHandler) Update(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}

	var body profileBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.Name != nil {
		trimmed := strings.TrimSpace(*body.Name)
		if len(trimmed) > 80 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name must be ≤ 80 chars"})
			return
		}
	}
	if body.AvatarURL != nil {
		trimmed := strings.TrimSpace(*body.AvatarURL)
		// Accept either an absolute http(s) URL (S3-presigned, prod) or
		// a relative `/uploads/...` path (local-disk dev fallback). The
		// /uploads/ mount serves the latter when AWS_S3_BUCKET is unset.
		if trimmed != "" && !looksLikeURL(trimmed) && !strings.HasPrefix(trimmed, "/uploads/") {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "avatarUrl must be an http(s) URL or an /uploads/ path",
			})
			return
		}
		if len(trimmed) > 2048 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "avatarUrl must be ≤ 2048 chars"})
			return
		}
	}

	user, err := h.users.UpdateProfile(userID, repositories.ProfileMutation{
		Name:      body.Name,
		AvatarURL: body.AvatarURL,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	c.JSON(http.StatusOK, userToJSON(user))
}

// ─── /me/locale (PATCH) ─────────────────────────────────────────────────

type localeBody struct {
	Locale string `json:"locale" binding:"required"`
}

// UpdateLocale — PATCH /api/me/locale
//
// Stores the user's UI language so the backend can render notification
// push titles/bodies in the language they actually picked (the choice
// otherwise lives only on the device). The app calls this on every
// language toggle and once after login.
func (h *ProfileHandler) UpdateLocale(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}
	var body localeBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	locale := strings.ToLower(strings.TrimSpace(body.Locale))
	if locale != "en" && locale != "ar" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "locale must be 'en' or 'ar'"})
		return
	}
	if err := h.users.UpdateLocale(userID, locale); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"locale": locale})
}

// ─── /me/change-password (POST) ─────────────────────────────────────────

type changePasswordBody struct {
	CurrentPassword string `json:"currentPassword" binding:"required"`
	NewPassword     string `json:"newPassword"     binding:"required,min=6"`
}

// ChangePassword — POST /api/me/change-password
//
// Verifies the current password with bcrypt, then writes a new hash.
// We do NOT issue a fresh JWT — the existing token stays valid; the
// client just keeps using it. Old tokens issued before the change
// also stay valid (we have no session revocation yet); that's a known
// trade-off documented for the security review.
func (h *ProfileHandler) ChangePassword(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}

	var body changePasswordBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if body.CurrentPassword == body.NewPassword {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new password must differ from current",
		})
		return
	}

	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	// OAuth-only users have the no-password sentinel — they can't change a
	// password they don't have. Tell them to use the onboarding /
	// forgot-password flow which lets them set one.
	if user.PasswordHash == "" || user.PasswordHash == repositories.OAuthOnlyPasswordSentinel {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "This account signs in with Google/Apple. " +
				"Use forgot-password to set a local password.",
			"code": "NO_PASSWORD_SET",
		})
		return
	}

	if err := bcrypt.CompareHashAndPassword(
		[]byte(user.PasswordHash), []byte(body.CurrentPassword),
	); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error": "Current password is incorrect.",
			"code":  "WRONG_PASSWORD",
		})
		return
	}

	newHash, err := bcrypt.GenerateFromPassword(
		[]byte(body.NewPassword), bcrypt.DefaultCost,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "hash failed"})
		return
	}
	if err := h.users.UpdatePassword(userID, string(newHash)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	_, _ = h.audits.Write(
		"AUTH_PASSWORD_CHANGED", models.SeverityWarning,
		&userID, ptrStr(fmt.Sprintf("%d", userID)), ptrStr("user"),
		fmt.Sprintf("%s changed password", user.Email),
		map[string]any{},
	)

	c.JSON(http.StatusOK, gin.H{"message": "Password updated."})
}

// ─── /me/complete-onboarding (POST) ─────────────────────────────────────

type completeOnboardingBody struct {
	Name     string `json:"name"`
	Password string `json:"password" binding:"required,min=6"`
}

// CompleteOnboarding — POST /api/me/complete-onboarding
//
// Finishes setup for a user who just signed in with Google/Apple for the
// first time: sets a display name + a local password so they can also
// sign in with email/password later. Authenticated — the JWT from the
// OAuth sign-in is the proof of identity.
//
// Guarded: only allowed while the account still carries the no-password
// sentinel. Once a real password exists this returns 409, so a stolen
// JWT can't overwrite a password without knowing the old one (that's
// what /me/change-password is for).
func (h *ProfileHandler) CompleteOnboarding(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}
	var body completeOnboardingBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if user.PasswordHash != repositories.OAuthOnlyPasswordSentinel {
		c.JSON(http.StatusConflict, gin.H{
			"error": "This account is already set up.",
			"code":  "ALREADY_ONBOARDED",
		})
		return
	}

	name := strings.TrimSpace(body.Name)
	if len(name) > 80 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name must be ≤ 80 chars"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "hash failed"})
		return
	}
	if err := h.users.UpdatePassword(userID, string(hash)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if name != "" {
		// Non-fatal if the name write fails — the password (the part that
		// flips the account out of the sentinel state) is already saved.
		if _, err := h.users.UpdateProfile(
			userID, repositories.ProfileMutation{Name: &name},
		); err != nil {
			log.Printf("[onboarding] name update failed for user_id=%d: %v", userID, err)
		}
	}

	_, _ = h.audits.Write(
		"AUTH_ONBOARDING_COMPLETED", models.SeverityInfo,
		&userID, ptrStr(fmt.Sprintf("%d", userID)), ptrStr("user"),
		fmt.Sprintf("%s completed onboarding (set password)", user.Email),
		map[string]any{},
	)

	updated, _ := h.users.GetByID(userID)
	if updated == nil {
		updated = user
	}
	c.JSON(http.StatusOK, userToJSON(updated))
}

// ─── /me/change-email/{request,confirm} ─────────────────────────────────

// EmailChangeTTL — how long the emailed code stays valid. 1 hour is
// generous enough for the user to switch inboxes; short enough that a
// leaked email doesn't sit on a token forever.
const EmailChangeTTL = 1 * time.Hour

// EmailChangeResendCooldown — minimum gap between successive /request
// hits for the same user, to keep an attacker from spamming the target
// inbox.
const EmailChangeResendCooldown = 60 * time.Second

type changeEmailRequestBody struct {
	NewEmail string `json:"newEmail" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type changeEmailConfirmBody struct {
	Code string `json:"code" binding:"required"`
}

// ChangeEmailRequest — POST /api/me/change-email/request
//
// Verifies the user's password, checks the new email isn't already in
// use, and emails a 6-digit code to the NEW address. The user types
// that code into /confirm to actually flip users.email.
func (h *ProfileHandler) ChangeEmailRequest(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}
	var body changeEmailRequestBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	newEmail := strings.ToLower(strings.TrimSpace(body.NewEmail))

	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if user.Email == newEmail {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "That's already your email.",
			"code":  "SAME_EMAIL",
		})
		return
	}

	// Verify password.
	if user.PasswordHash == "" || user.PasswordHash == repositories.OAuthOnlyPasswordSentinel {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "OAuth accounts can't change email here — update it " +
				"in your Google/Apple account.",
			"code": "OAUTH_ACCOUNT",
		})
		return
	}
	if err := bcrypt.CompareHashAndPassword(
		[]byte(user.PasswordHash), []byte(body.Password),
	); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error": "Password is incorrect.",
			"code":  "WRONG_PASSWORD",
		})
		return
	}

	// Check the new email isn't taken.
	existing, err := h.users.GetByEmail(newEmail)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing != nil {
		c.JSON(http.StatusConflict, gin.H{
			"error": "That email is already in use.",
			"code":  "EMAIL_TAKEN",
		})
		return
	}

	// Rate-limit: don't re-issue codes faster than the cooldown.
	if age, ok, _ := h.emailChanges.LastActiveAge(userID); ok && age < EmailChangeResendCooldown {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":      "Please wait a moment before requesting another code.",
			"code":       "RESEND_COOLDOWN",
			"retryAfter": int((EmailChangeResendCooldown - age).Seconds()),
		})
		return
	}

	code, err := repositories.GenerateCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "code gen failed"})
		return
	}
	if err := h.emailChanges.Create(userID, newEmail, code, EmailChangeTTL); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	log.Printf("[email-change] code=%s for user_id=%d → %s (dev_mode=%v)",
		code, userID, newEmail, devMode())

	// Fire-and-forget SMTP — only the NEW address receives the code.
	if h.emailSender != nil {
		name := ""
		if user.Name.Valid {
			name = user.Name.String
		}
		go func() {
			if err := h.emailSender.SendVerificationCode(newEmail, name, code); err != nil {
				log.Printf("[email-change] send failed: %v", err)
			}
		}()
	}

	_, _ = h.audits.Write(
		"AUTH_EMAIL_CHANGE_REQUESTED", models.SeverityInfo,
		&userID, ptrStr(fmt.Sprintf("%d", userID)), ptrStr("user"),
		fmt.Sprintf("%s requested email change → %s", user.Email, newEmail),
		map[string]any{"newEmail": newEmail},
	)

	resp := gin.H{
		"message":              "We've sent a verification code to the new address.",
		"newEmail":             newEmail,
		"requiresVerification": true,
		"devMode":              devMode(),
	}
	if devMode() {
		resp["verificationCode"] = code
	}
	c.JSON(http.StatusOK, resp)
}

// ChangeEmailConfirm — POST /api/me/change-email/confirm
//
// Consumes the code minted by /request and flips users.email. Marks
// the new email verified (since the code went to it). The old email
// is freed for re-registration.
func (h *ProfileHandler) ChangeEmailConfirm(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}
	var body changeEmailConfirmBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	newEmail, err := h.emailChanges.Consume(userID, strings.TrimSpace(body.Code))
	if err != nil {
		// Unknown / expired / already used — collapse to one message
		// rather than letting attackers probe which.
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid or expired code. Request a fresh one.",
			"code":  "INVALID_CODE",
		})
		return
	}

	if err := h.users.UpdateEmail(userID, newEmail); err != nil {
		if errors.Is(err, repositories.ErrEmailTaken) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "That email is now in use by another account.",
				"code":  "EMAIL_TAKEN",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	_, _ = h.audits.Write(
		"AUTH_EMAIL_CHANGED", models.SeverityWarning,
		&userID, ptrStr(fmt.Sprintf("%d", userID)), ptrStr("user"),
		fmt.Sprintf("user_id=%d flipped email → %s", userID, newEmail),
		map[string]any{"newEmail": newEmail},
	)

	user, _ := h.users.GetByID(userID)
	if user == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user vanished"})
		return
	}
	c.JSON(http.StatusOK, userToJSON(user))
}

// ─── /me/account (DELETE) ───────────────────────────────────────────────

type deleteAccountBody struct {
	// Password is required for non-OAuth accounts; OAuth users can pass
	// an empty string and we'll accept it (their only auth lives at
	// Google/Apple, so the JWT itself is our proof of identity).
	Password string `json:"password"`
	// Confirmation phrase — the client UI displays "Type DELETE to
	// confirm." Server-side defense against accidental DELETE calls
	// from a stale Postman tab.
	Confirm string `json:"confirm"`
}

// DeleteAccount — DELETE /api/me/account
//
// Soft-deletes the user row (mig 0040): anonymizes PII, frees the old
// email, marks deleted_at. The Flutter app must call /auth/logout
// (clear local token) immediately after — any old JWT is now useless
// because Login + GetByEmail check deleted_at.
//
// Authored content stays — posts and comments remain attached to the
// tombstoned row, the UI renders "Deleted User" for the author.
func (h *ProfileHandler) DeleteAccount(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}
	var body deleteAccountBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if strings.ToUpper(strings.TrimSpace(body.Confirm)) != "DELETE" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Type DELETE in the confirm field to proceed.",
			"code":  "CONFIRM_REQUIRED",
		})
		return
	}

	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}

	// Password gate — required for password-auth accounts, optional for
	// pure-OAuth (where there's no local password to verify against).
	isOAuthOnly := user.PasswordHash == "" || user.PasswordHash == repositories.OAuthOnlyPasswordSentinel
	if !isOAuthOnly {
		if body.Password == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Password is required to delete this account.",
				"code":  "PASSWORD_REQUIRED",
			})
			return
		}
		if err := bcrypt.CompareHashAndPassword(
			[]byte(user.PasswordHash), []byte(body.Password),
		); err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Password is incorrect.",
				"code":  "WRONG_PASSWORD",
			})
			return
		}
	}

	if err := h.users.SoftDelete(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	_, _ = h.audits.Write(
		"AUTH_ACCOUNT_DELETED", models.SeverityWarning,
		&userID, ptrStr(fmt.Sprintf("%d", userID)), ptrStr("user"),
		fmt.Sprintf("%s deleted their account (soft)", user.Email),
		map[string]any{"oauthOnly": isOAuthOnly},
	)

	c.JSON(http.StatusOK, gin.H{
		"message": "Your account has been deleted.",
	})
}

// ─── /me/notification-prefs (GET + PATCH) ───────────────────────────────

// prefsBody — request body for PATCH /me/notification-prefs.
//
// All-nullable pointers so the client can send a single toggle
// ("just turn off comments") without re-sending every other flag.
type prefsBody struct {
	PushEnabled          *bool `json:"pushEnabled"`
	EmailEnabled         *bool `json:"emailEnabled"`
	LikesEnabled         *bool `json:"likesEnabled"`
	CommentsEnabled      *bool `json:"commentsEnabled"`
	SubscriptionsEnabled *bool `json:"subscriptionsEnabled"`
	CommunitiesEnabled   *bool `json:"communitiesEnabled"`
	MarketingEnabled     *bool `json:"marketingEnabled"`
}

// GetNotificationPrefs — GET /api/me/notification-prefs
//
// Returns the user's prefs, lazily inserting a defaults row when they
// haven't touched the settings screen yet.
func (h *ProfileHandler) GetNotificationPrefs(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}
	p, err := h.prefs.GetOrDefault(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, p)
}

// UpdateNotificationPrefs — PATCH /api/me/notification-prefs
//
// Partial update. Any field omitted from the JSON body is left
// unchanged in the DB.
func (h *ProfileHandler) UpdateNotificationPrefs(c *gin.Context) {
	userID, ok := requireUserID(c)
	if !ok {
		return
	}
	var body prefsBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	p, err := h.prefs.Update(userID, repositories.PrefsMutation{
		PushEnabled:          body.PushEnabled,
		EmailEnabled:         body.EmailEnabled,
		LikesEnabled:         body.LikesEnabled,
		CommentsEnabled:      body.CommentsEnabled,
		SubscriptionsEnabled: body.SubscriptionsEnabled,
		CommunitiesEnabled:   body.CommunitiesEnabled,
		MarketingEnabled:     body.MarketingEnabled,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, p)
}

// ─── shared helpers ─────────────────────────────────────────────────────

// requireUserID pulls the auth-middleware-stored user id from the gin
// context. Returns (id, true) on success; on failure it writes a 401
// directly and returns (0, false) so the handler can early-return.
func requireUserID(c *gin.Context) (int64, bool) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return 0, false
	}
	return userID, true
}

// looksLikeURL — minimal sanity check. We don't try to be exhaustive
// (RFC 3986 would balloon the handler); the storage layer is what
// actually has to consume these and the S3 presigner / image loader
// will surface a clearer error if the URL is malformed.
func looksLikeURL(s string) bool {
	return strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://")
}

// errRowMissing — kept for completeness, currently unused. If a future
// handler needs to map sql.ErrNoRows differently it can reference this.
var _ = sql.ErrNoRows
