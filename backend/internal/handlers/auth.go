package handlers

import (
	"database/sql"
	"fmt"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"halalstocks/pkg/jwt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	userRepo     *repositories.UserRepository
	audits       *repositories.AuditRepository
	emails       *repositories.EmailVerificationRepository
	resetTokens  *repositories.PasswordResetTokenRepository
	emailSender  *services.EmailSender // nullable — soft-fails when SMTP unset
}

func NewAuthHandler(
	userRepo *repositories.UserRepository,
	audits *repositories.AuditRepository,
	emails *repositories.EmailVerificationRepository,
	resetTokens *repositories.PasswordResetTokenRepository,
	emailSender *services.EmailSender,
) *AuthHandler {
	return &AuthHandler{
		userRepo:    userRepo,
		audits:      audits,
		emails:      emails,
		resetTokens: resetTokens,
		emailSender: emailSender,
	}
}

// sendVerificationEmail is a fire-and-forget wrapper around the SMTP send.
// Failures are logged but never propagated — verification codes still
// land in stdout (and in dev-mode responses), so a flaky SMTP doesn't
// brick onboarding.
func (h *AuthHandler) sendVerificationEmail(to, name, code string) {
	if h.emailSender == nil {
		return
	}
	go func() {
		if err := h.emailSender.SendVerificationCode(to, name, code); err != nil {
			log.Printf("[email] verify-code send failed for %s: %v", to, err)
		}
	}()
}

// devMode returns true when we're running the API locally and want to
// expose verification codes in API responses (so testers don't need a real
// SMTP server). Controlled by APP_ENV — anything other than "production"
// counts as dev. Default is dev.
func devMode() bool {
	env := strings.ToLower(strings.TrimSpace(os.Getenv("APP_ENV")))
	return env == "" || env != "production"
}

type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Name     string `json:"name"`
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type VerifyEmailRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code"  binding:"required"`
}

type ResendCodeRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type AuthResponse struct {
	Token string       `json:"token"`
	User  UserResponse `json:"user"`
}

type UserResponse struct {
	ID       int64  `json:"id"`
	Email    string `json:"email"`
	Name     string `json:"name,omitempty"`
	Role     string `json:"role,omitempty"`
	ExpertID string `json:"expertId,omitempty"`
	Tier     string `json:"subscriptionTier,omitempty"`
}

// RegisterResponse is what Register returns now. Note the absence of a JWT:
// you don't get a session until you verify your email. The caller is expected
// to push a "verify code" screen and call /api/auth/verify-email next.
//
// `Code` is the dev-mode escape hatch — it is only populated when APP_ENV
// is not "production". In production this field is empty and the user has
// to read the code out of an email.
type RegisterResponse struct {
	UserID               int64  `json:"userId"`
	Email                string `json:"email"`
	RequiresVerification bool   `json:"requiresVerification"`
	Code                 string `json:"verificationCode,omitempty"`
	DevMode              bool   `json:"devMode"`
}

// Register creates the user with email_verified_at=NULL, generates a
// 6-digit code, and (in dev mode) returns the code in the response so a
// tester can immediately verify. No JWT is issued until verification
// succeeds — see VerifyEmail.
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Reject if email already in use.
	existing, err := h.userRepo.GetByEmail(req.Email)
	if err != nil && err != sql.ErrNoRows {
		log.Printf("Failed to check user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check user"})
		return
	}
	if existing != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "User already exists"})
		return
	}

	// Hash password.
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		log.Printf("Failed to hash password: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	// Create user. email_verified_at stays NULL — the row exists, but
	// the user can't log in until VerifyEmail flips that column.
	user := &models.User{
		Email:        req.Email,
		PasswordHash: string(hashedPassword),
	}
	if req.Name != "" {
		user.Name = sql.NullString{String: req.Name, Valid: true}
	}

	if err := h.userRepo.Create(user); err != nil {
		log.Printf("Failed to create user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
		return
	}

	// Generate + persist the 6-digit verification code.
	code, err := repositories.GenerateCode()
	if err != nil {
		log.Printf("Failed to generate code: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate code"})
		return
	}
	if err := h.emails.Create(user.ID, code); err != nil {
		log.Printf("Failed to save code: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save code"})
		return
	}

	// Always log the code to stdout — in dev that's how testers see it
	// when they're not looking at the API response (e.g. via Flutter).
	log.Printf("[email-verify] code=%s for user_id=%d email=%s (dev_mode=%v)",
		code, user.ID, user.Email, devMode())

	// Fire-and-forget SMTP send. No-op when SMTP_HOST is unset.
	h.sendVerificationEmail(user.Email, req.Name, code)

	// Audit — best-effort.
	_, _ = h.audits.Write(
		models.AuditAuthRegister, models.SeverityInfo,
		&user.ID, ptrStr(fmt.Sprintf("%d", user.ID)), ptrStr("user"),
		fmt.Sprintf("%s registered (awaiting email verification)", req.Email),
		map[string]any{"name": req.Name},
	)

	resp := RegisterResponse{
		UserID:               user.ID,
		Email:                user.Email,
		RequiresVerification: true,
		DevMode:              devMode(),
	}
	if devMode() {
		resp.Code = code
	}

	c.JSON(http.StatusCreated, resp)
}

func ptrStr(s string) *string { return &s }

// VerifyEmail flips email_verified_at to NOW() when (email, code) matches
// an active row, and returns a JWT so the client can log in immediately.
func (h *AuthHandler) VerifyEmail(c *gin.Context) {
	var req VerifyEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.userRepo.GetByEmail(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to look up user"})
		return
	}
	if user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "No account for that email", "code": "USER_NOT_FOUND"})
		return
	}

	if err := h.emails.Consume(user.ID, strings.TrimSpace(req.Code)); err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Invalid or expired code",
				"code":  "INVALID_CODE",
			})
			return
		}
		log.Printf("VerifyEmail consume failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to verify code"})
		return
	}

	if err := h.emails.MarkUserVerified(user.ID); err != nil {
		log.Printf("MarkUserVerified failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark verified"})
		return
	}

	token, err := jwt.GenerateToken(user.ID, user.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	name := ""
	if user.Name.Valid {
		name = user.Name.String
	}
	expertID := ""
	if user.ExpertID.Valid {
		expertID = user.ExpertID.String
	}

	_, _ = h.audits.Write(
		models.AuditAuthLogin, models.SeverityInfo,
		&user.ID, ptrStr(fmt.Sprintf("%d", user.ID)), ptrStr("user"),
		fmt.Sprintf("%s verified email", user.Email),
		map[string]any{},
	)

	c.JSON(http.StatusOK, AuthResponse{
		Token: token,
		User: UserResponse{
			ID:       user.ID,
			Email:    user.Email,
			Name:     name,
			Role:     user.Role,
			ExpertID: expertID,
			Tier:     user.SubscriptionTier,
		},
	})
}

// ResendCode generates a new code for a user that hasn't verified yet.
// Rate-limited to one fresh code per 30 seconds so testers can't pile up
// codes. Existing un-consumed codes are invalidated by Create().
func (h *AuthHandler) ResendCode(c *gin.Context) {
	var req ResendCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.userRepo.GetByEmail(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to look up user"})
		return
	}
	if user == nil {
		// Don't leak existence — same as VerifyEmail though, since the user
		// did just register. Return 404 with a code so the mobile UI can
		// surface a helpful message.
		c.JSON(http.StatusNotFound, gin.H{"error": "No account for that email", "code": "USER_NOT_FOUND"})
		return
	}

	// Short-circuit if already verified.
	if ok, err := h.emails.IsVerified(user.ID); err == nil && ok {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Email is already verified — just log in.",
			"code":  "ALREADY_VERIFIED",
		})
		return
	}

	// Rate-limit: if there's an active code newer than 30 seconds, refuse.
	if age, ok, _ := h.emails.LastActiveAge(user.ID); ok && age < 30*time.Second {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":      "Please wait a moment before requesting another code.",
			"code":       "RESEND_COOLDOWN",
			"retryAfter": int((30*time.Second - age).Seconds()),
		})
		return
	}

	code, err := repositories.GenerateCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate code"})
		return
	}
	if err := h.emails.Create(user.ID, code); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save code"})
		return
	}

	log.Printf("[email-verify] (resend) code=%s for user_id=%d email=%s (dev_mode=%v)",
		code, user.ID, user.Email, devMode())

	name := ""
	if user.Name.Valid {
		name = user.Name.String
	}
	h.sendVerificationEmail(user.Email, name, code)

	resp := gin.H{
		"requiresVerification": true,
		"devMode":              devMode(),
	}
	if devMode() {
		resp["verificationCode"] = code
	}
	c.JSON(http.StatusOK, resp)
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.userRepo.GetByEmail(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get user"})
		return
	}
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// Refuse logins on soft-deleted accounts (mig 0040). Email was
	// rewritten to deleted_<id>@deleted.local, password_hash replaced
	// with a sentinel — the bcrypt check below would already fail, but
	// surfacing a specific code lets the client show a friendlier
	// "this account was deleted" message instead of a generic 401.
	if deleted, _ := h.userRepo.IsDeleted(user.ID); deleted {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error": "This account has been deleted.",
			"code":  "ACCOUNT_DELETED",
		})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// NOTE: the old "block login until email is verified" gate was removed.
	// The product no longer has an email-verification step — new accounts
	// are created already-verified (email-first signup calls
	// MarkUserVerified; OAuth users are verified at creation by Google /
	// Apple, see CreateFromFirebase). Keeping the gate caused OAuth users
	// to get a silent 403 when signing in with the password they set
	// during onboarding. A correct password is now sufficient to log in.

	token, err := jwt.GenerateToken(user.ID, user.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	name := ""
	if user.Name.Valid {
		name = user.Name.String
	}
	expertID := ""
	if user.ExpertID.Valid {
		expertID = user.ExpertID.String
	}

	_, _ = h.audits.Write(
		models.AuditAuthLogin, models.SeverityInfo,
		&user.ID, ptrStr(fmt.Sprintf("%d", user.ID)), ptrStr("user"),
		fmt.Sprintf("%s logged in", user.Email),
		map[string]any{"role": user.Role},
	)

	c.JSON(http.StatusOK, AuthResponse{
		Token: token,
		User: UserResponse{
			ID:       user.ID,
			Email:    user.Email,
			Name:     name,
			Role:     user.Role,
			ExpertID: expertID,
			Tier:     user.SubscriptionTier,
		},
	})
}

// ─────────────────────────────────────────────────────────────────────────
// Email-first onboarding (no email-verification step).
//
// The mobile client uses a two-step flow:
//   1. POST /auth/check-email { email } → { exists }
//      - exists=true  → client shows the password field, then /auth/login
//      - exists=false → client shows the create-account screen, then /auth/signup
//   2. POST /auth/signup { email, name, password } → AuthResponse (JWT)
//
// This replaces the old Register + VerifyEmail two-step. The legacy
// endpoints stay registered but the app no longer calls them.
// ─────────────────────────────────────────────────────────────────────────

type CheckEmailRequest struct {
	Email string `json:"email" binding:"required,email"`
}

// CheckEmail — POST /api/auth/check-email
//
// Reports only whether an account exists for the email — nothing else,
// so it can't be used to harvest names/roles. Never errors on unknown
// emails. A soft-deleted account's email was rewritten to
// deleted_<id>@deleted.local (mig 0040), so its original address
// correctly reports exists=false and is free to re-register.
func (h *AuthHandler) CheckEmail(c *gin.Context) {
	var req CheckEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	user, err := h.userRepo.GetByEmail(strings.TrimSpace(req.Email))
	if err != nil {
		log.Printf("CheckEmail lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check email"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"exists": user != nil})
}

type SignupRequest struct {
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Name     string `json:"name"`
}

// Signup — POST /api/auth/signup
//
// Creates an immediately-verified user (no 6-digit code, no email round
// trip) and returns a JWT so the client drops straight into the app.
// This is the replacement for the old Register + VerifyEmail two-step.
func (h *AuthHandler) Signup(c *gin.Context) {
	var req SignupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Email = strings.TrimSpace(req.Email)

	// Reject if the email is already taken.
	existing, err := h.userRepo.GetByEmail(req.Email)
	if err != nil {
		log.Printf("Signup lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check user"})
		return
	}
	if existing != nil {
		c.JSON(http.StatusConflict, gin.H{
			"error": "An account with that email already exists.",
			"code":  "EMAIL_TAKEN",
		})
		return
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		log.Printf("Signup hash failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	user := &models.User{
		Email:        req.Email,
		PasswordHash: string(hashed),
	}
	name := strings.TrimSpace(req.Name)
	if name != "" {
		user.Name = sql.NullString{String: name, Valid: true}
	}
	if err := h.userRepo.Create(user); err != nil {
		log.Printf("Signup create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create account"})
		return
	}

	// Mark verified immediately — the new flow has no verification step,
	// and Login still gates legacy accounts on IsVerified.
	if err := h.emails.MarkUserVerified(user.ID); err != nil {
		log.Printf("Signup MarkUserVerified failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to finalize account"})
		return
	}

	token, err := jwt.GenerateToken(user.ID, user.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	_, _ = h.audits.Write(
		models.AuditAuthRegister, models.SeverityInfo,
		&user.ID, ptrStr(fmt.Sprintf("%d", user.ID)), ptrStr("user"),
		fmt.Sprintf("%s signed up (email-first)", user.Email),
		map[string]any{"name": name},
	)

	c.JSON(http.StatusCreated, AuthResponse{
		Token: token,
		User: UserResponse{
			ID:    user.ID,
			Email: user.Email,
			Name:  name,
			Role:  user.Role,
			Tier:  user.SubscriptionTier,
		},
	})
}

// ─────────────────────────────────────────────────────────────────────────
// Password reset — forgot-password flow.
// ─────────────────────────────────────────────────────────────────────────

// PasswordResetTTL is how long an emailed reset link stays valid. Short
// enough that a leaked email can't be replayed indefinitely; long enough
// that a user can click it after a meeting.
const PasswordResetTTL = 1 * time.Hour

// PasswordResetResendCooldown rate-limits the request endpoint so an
// attacker can't spam someone's inbox.
const PasswordResetResendCooldown = 60 * time.Second

type PasswordResetRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type PasswordResetConfirm struct {
	Token       string `json:"token"       binding:"required"`
	NewPassword string `json:"newPassword" binding:"required,min=6"`
}

// RequestPasswordReset — POST /api/auth/password-reset/request
//
// Always returns 200 with the same generic body, regardless of whether
// the email exists. This prevents email-enumeration attacks: someone
// fishing for valid accounts gets identical responses for known and
// unknown emails.
//
// In dev mode (APP_ENV != production) the response includes the raw token
// so testers don't need an email server. In production the token only
// travels via SMTP.
func (h *AuthHandler) RequestPasswordReset(c *gin.Context) {
	var req PasswordResetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	genericOK := gin.H{
		"message": "If an account exists for that email, a reset link has been sent.",
		"devMode": devMode(),
	}

	user, err := h.userRepo.GetByEmail(req.Email)
	if err != nil {
		log.Printf("[password-reset] lookup error: %v", err)
		c.JSON(http.StatusOK, genericOK)
		return
	}
	if user == nil {
		c.JSON(http.StatusOK, genericOK)
		return
	}

	// Rate-limit: if there's an active token newer than the cooldown,
	// don't mint a new one. Returns the generic 200 anyway so attackers
	// can't time-probe accounts.
	if age, ok, _ := h.resetTokens.LastActiveAge(user.ID); ok && age < PasswordResetResendCooldown {
		log.Printf("[password-reset] cooldown hit for user_id=%d", user.ID)
		c.JSON(http.StatusOK, genericOK)
		return
	}

	rawToken, err := repositories.GeneratePasswordResetToken()
	if err != nil {
		log.Printf("[password-reset] token gen: %v", err)
		c.JSON(http.StatusOK, genericOK)
		return
	}
	if err := h.resetTokens.Create(user.ID, rawToken, PasswordResetTTL); err != nil {
		log.Printf("[password-reset] persist: %v", err)
		c.JSON(http.StatusOK, genericOK)
		return
	}

	link := services.PublicAppURL() + "/reset-password?token=" + url.QueryEscape(rawToken)
	log.Printf("[password-reset] issued token for user_id=%d link=%s (dev_mode=%v)",
		user.ID, link, devMode())

	name := ""
	if user.Name.Valid {
		name = user.Name.String
	}
	if h.emailSender != nil {
		go func() {
			if err := h.emailSender.SendPasswordReset(user.Email, name, link); err != nil {
				log.Printf("[password-reset] send failed: %v", err)
			}
		}()
	}

	_, _ = h.audits.Write(
		models.AuditAuthLogin, models.SeverityInfo,
		&user.ID, ptrStr(fmt.Sprintf("%d", user.ID)), ptrStr("user"),
		fmt.Sprintf("%s requested password reset", user.Email),
		map[string]any{},
	)

	resp := gin.H{
		"message": "If an account exists for that email, a reset link has been sent.",
		"devMode": devMode(),
	}
	if devMode() {
		resp["resetToken"] = rawToken
		resp["resetLink"] = link
	}
	c.JSON(http.StatusOK, resp)
}

// ConfirmPasswordReset — POST /api/auth/password-reset/confirm
//
// Consumes the token and replaces the password. The token is hashed
// before the lookup, so a DB leak can't be replayed against this endpoint.
func (h *AuthHandler) ConfirmPasswordReset(c *gin.Context) {
	var req PasswordResetConfirm
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Token = strings.TrimSpace(req.Token)
	if req.Token == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "token required"})
		return
	}

	userID, err := h.resetTokens.Consume(req.Token)
	if err != nil {
		// Could be unknown, expired, or already used — collapse to one
		// generic error so we don't leak which.
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "This link has expired or has already been used. Request a new one.",
			"code":  "INVALID_TOKEN",
		})
		return
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}
	if err := h.userRepo.UpdatePassword(userID, string(hashed)); err != nil {
		log.Printf("[password-reset] UpdatePassword failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update password"})
		return
	}

	user, _ := h.userRepo.GetByID(userID)
	emailForAudit := ""
	if user != nil {
		emailForAudit = user.Email
	}
	_, _ = h.audits.Write(
		models.AuditAuthLogin, models.SeverityWarning,
		&userID, ptrStr(fmt.Sprintf("%d", userID)), ptrStr("user"),
		fmt.Sprintf("%s reset password", emailForAudit),
		map[string]any{},
	)

	c.JSON(http.StatusOK, gin.H{
		"message": "Password updated. You can now log in with the new password.",
	})
}
