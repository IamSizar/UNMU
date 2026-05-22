package handlers

import (
	"database/sql"
	"fmt"
	"halalstocks/internal/repositories"
	"halalstocks/pkg/jwt"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

// DevHandler powers the "Switch account" surface in the Flutter app.
//
// Every route on this handler is GATED behind APP_ENV != "production".
// In production they return 404 so a leak of these URLs is harmless.
// Locally they let testers list every account in the DB and impersonate
// any of them (issue a JWT without a password) so the team can flip
// between accounts in one tap.
type DevHandler struct {
	db       *sql.DB
	userRepo *repositories.UserRepository
}

func NewDevHandler(db *sql.DB, userRepo *repositories.UserRepository) *DevHandler {
	return &DevHandler{db: db, userRepo: userRepo}
}

// isDev mirrors handlers/auth.go devMode(). Anything other than "production"
// counts as dev (including unset).
func isDev() bool {
	env := strings.ToLower(strings.TrimSpace(os.Getenv("APP_ENV")))
	return env != "production"
}

// guardDev sends a 404 when running in production and returns false. Caller
// should `return` immediately if it returns false.
func (h *DevHandler) guardDev(c *gin.Context) bool {
	if !isDev() {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return false
	}
	return true
}

// DevUserRow is the shape the switcher consumes. Includes verification
// state so the UI can flag unverified accounts (so testers know why a
// real login would 403 them).
type DevUserRow struct {
	ID               int64   `json:"id"`
	Email            string  `json:"email"`
	Name             *string `json:"name,omitempty"`
	Role             string  `json:"role"`
	ExpertID         *string `json:"expertId,omitempty"`
	SubscriptionTier string  `json:"subscriptionTier"`
	EmailVerified    bool    `json:"emailVerified"`
	CreatedAt        string  `json:"createdAt"`
}

// ListUsers — `GET /api/dev/users` — returns every account in the DB,
// newest first. The switcher renders this list directly. No pagination
// because the test DB is small; if it grows past ~500 we can add it.
func (h *DevHandler) ListUsers(c *gin.Context) {
	if !h.guardDev(c) {
		return
	}

	rows, err := h.db.Query(`
		SELECT id, email, name,
		       COALESCE(role, 'USER'),
		       expert_id,
		       COALESCE(subscription_tier, 'FREE'),
		       email_verified_at IS NOT NULL,
		       created_at::text
		FROM users
		ORDER BY id DESC
	`)
	if err != nil {
		log.Printf("dev.ListUsers: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load users"})
		return
	}
	defer rows.Close()

	out := make([]DevUserRow, 0, 32)
	for rows.Next() {
		var (
			r        DevUserRow
			name     sql.NullString
			expertID sql.NullString
		)
		if err := rows.Scan(
			&r.ID, &r.Email, &name, &r.Role, &expertID,
			&r.SubscriptionTier, &r.EmailVerified, &r.CreatedAt,
		); err != nil {
			log.Printf("dev.ListUsers scan: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to scan users"})
			return
		}
		if name.Valid {
			n := name.String
			r.Name = &n
		}
		if expertID.Valid {
			e := expertID.String
			r.ExpertID = &e
		}
		out = append(out, r)
	}

	c.JSON(http.StatusOK, gin.H{"users": out, "devMode": true})
}

type impersonateRequest struct {
	Email string `json:"email" binding:"required,email"`
}

// Impersonate — `POST /api/dev/impersonate {email}` — issues a JWT for any
// existing user without a password check. Dev-only. Also auto-verifies the
// account so the resulting JWT actually works (no point handing a token to
// an unverified user only for the next call to 403). Every impersonation is
// logged with the client IP for traceability.
func (h *DevHandler) Impersonate(c *gin.Context) {
	if !h.guardDev(c) {
		return
	}

	var req impersonateRequest
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
		c.JSON(http.StatusNotFound, gin.H{"error": "No account for that email"})
		return
	}

	// Auto-verify so the issued JWT is usable across the rest of the API.
	if _, err := h.db.Exec(`
		UPDATE users
		SET email_verified_at = COALESCE(email_verified_at, NOW())
		WHERE id = $1
	`, user.ID); err != nil {
		log.Printf("dev.Impersonate auto-verify: %v", err)
	}

	token, err := jwt.GenerateToken(user.ID, user.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	log.Printf("[dev-impersonate] target=%s id=%d from=%s",
		user.Email, user.ID, c.ClientIP())

	name := ""
	if user.Name.Valid {
		name = user.Name.String
	}
	expertID := ""
	if user.ExpertID.Valid {
		expertID = user.ExpertID.String
	}

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

// adminUserID is the ID of the only account that survives a /dev/reset.
// Matches the seed migration's admin@test.com row.
const adminUserID int64 = 1000

// resetTables lists every USER-GENERATED table that gets truncated by
// /api/dev/reset, in safe-ish order (children first). RESTART IDENTITY
// resets each table's serial sequence so the next inserted row gets id=1.
// CASCADE handles any FK relationships between them.
//
// NOT included (intentionally KEPT):
//
//	stocks, shariah_status, shariah_results, shariah_result_history,
//	fundamentals, analyst_ratings, market_indexes, market_sentiment,
//	stock_snapshots, ads, promo_codes, users (handled separately).
var resetTables = []string{
	// audit + notifications (no children depend on these)
	"audit_logs",
	"email_verification_codes",
	"user_notifications",
	"notifications",
	// post tree
	"post_attachments",
	"post_comments",
	"post_likes",
	"post_saves",
	"post_events",
	"post_versions",
	"posts",
	// community children → parents
	"community_message_reactions",
	"community_message_reads",
	"community_messages",
	"community_poll_votes",
	"community_poll_options",
	"community_polls",
	"community_proposals",
	"community_subscriptions",
	"community_members",
	"community_tags",
	"communities",
	// expert tree
	"expert_subscriptions",
	"expert_applications",
	"experts",
	// per-user data
	"subscriptions",
	"user_portfolios",
	"user_promo_usage",
	"tracked_symbols",
}

// Reset — `POST /api/dev/reset` — wipes every USER-GENERATED row except
// the admin user (id=1000). Reference data (stocks, shariah, ads, …) is
// preserved. Dev-only; also requires the `X-Confirm: yes-wipe-everything`
// header so a stray curl can't accidentally nuke the dev DB.
//
// Response includes a `wiped` map (table → row count BEFORE the wipe) so
// the mobile UI can show the user exactly what disappeared.
func (h *DevHandler) Reset(c *gin.Context) {
	if !h.guardDev(c) {
		return
	}

	if c.GetHeader("X-Confirm") != "yes-wipe-everything" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Refused without confirmation header",
			"hint":  "Set request header 'X-Confirm: yes-wipe-everything' to proceed.",
		})
		return
	}

	wiped := map[string]int{}

	// 1. Snapshot row counts so we can report what disappeared. Done
	// outside the transaction (read-only) so we don't hold a long lock.
	for _, t := range resetTables {
		var n int
		// Static identifier list — not user input — safe for fmt.Sprintf.
		if err := h.db.QueryRow(fmt.Sprintf("SELECT COUNT(*) FROM %s", t)).Scan(&n); err != nil {
			// Table missing? Log but keep going — we'd rather skip a
			// missing table than abort the whole reset.
			log.Printf("dev.Reset count %s: %v", t, err)
			continue
		}
		wiped[t] = n
	}
	var nonAdminUsers int
	_ = h.db.QueryRow(`SELECT COUNT(*) FROM users WHERE id != $1`, adminUserID).
		Scan(&nonAdminUsers)
	wiped["users"] = nonAdminUsers

	// 2. Wipe in one transaction so a mid-reset crash leaves the DB
	// untouched.
	tx, err := h.db.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer tx.Rollback()

	// TRUNCATE all user-gen tables at once. RESTART IDENTITY resets the
	// auto-increment counters; CASCADE handles any cross-table FKs.
	stmt := fmt.Sprintf(
		"TRUNCATE TABLE %s RESTART IDENTITY CASCADE",
		strings.Join(resetTables, ", "),
	)
	if _, err := tx.Exec(stmt); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "TRUNCATE failed",
			"detail": err.Error(),
		})
		return
	}

	// Drop every user EXCEPT admin. Use DELETE (not TRUNCATE) so we can
	// keep one row in place; FKs have already been cleared by the
	// truncates above.
	if _, err := tx.Exec(`DELETE FROM users WHERE id != $1`, adminUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":  "Failed to delete non-admin users",
			"detail": err.Error(),
		})
		return
	}

	// Belt-and-braces: make sure the admin row is in a sane state.
	//   • email_verified_at set so admin can log in immediately
	//   • expert_id cleared (in case admin was ever promoted; the experts
	//     table is empty now and a dangling pointer would confuse the UI)
	//   • subscription pinned to PREMIUM so admin's profile looks right
	if _, err := tx.Exec(`
		UPDATE users
		SET email_verified_at = COALESCE(email_verified_at, NOW()),
		    expert_id = NULL,
		    subscription_tier = 'PREMIUM',
		    subscription_status = 'ACTIVE',
		    updated_at = NOW()
		WHERE id = $1
	`, adminUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":  "Failed to refresh admin row",
			"detail": err.Error(),
		})
		return
	}

	// Reset the users sequence so the next signup gets a clean id past
	// the admin's reserved 1000.
	if _, err := tx.Exec(`SELECT setval('users_id_seq', $1, true)`, adminUserID); err != nil {
		log.Printf("dev.Reset setval users_id_seq: %v", err)
	}

	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	log.Printf("[dev-reset] wiped %d non-admin users + cascaded data; admin (id=%d) kept",
		nonAdminUsers, adminUserID)

	c.JSON(http.StatusOK, gin.H{
		"ok":     true,
		"wiped":  wiped,
		"kept":   gin.H{"userId": adminUserID, "email": "admin@test.com"},
		"notice": "Reference data (stocks, shariah, ads) is untouched.",
	})
}
