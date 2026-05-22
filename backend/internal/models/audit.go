package models

import (
	"database/sql"
	"encoding/json"
	"time"
)

// =============================================================================
// AuditLog — one row per meaningful event in the system. Backed by the
// `audit_logs` table from migration 0005.
//
// Event-type constants are kept in sync with the SQL migration. Severity
// drives the color in the admin UI.
// =============================================================================

// Event types.
const (
	AuditAuthLogin             = "AUTH_LOGIN"
	AuditAuthRegister          = "AUTH_REGISTER"
	AuditAuthLogout            = "AUTH_LOGOUT"
	AuditExpertAppSubmitted    = "EXPERT_APP_SUBMITTED"
	AuditExpertAppApproved     = "EXPERT_APP_APPROVED"
	AuditExpertAppRejected     = "EXPERT_APP_REJECTED"
	AuditUserRoleChanged       = "USER_ROLE_CHANGED"
	AuditPostCreated           = "POST_CREATED"
	AuditPostHidden            = "POST_HIDDEN"
	AuditSubscriptionChanged   = "SUBSCRIPTION_CHANGED"
	// Pricing change on an expert profile. Admin-only — written by
	// SocialHandler.AdminSetExpertPricing. The metadata payload
	// records both old and new prices so the audit-log detail page
	// can render a diff.
	AuditExpertPricingUpdated  = "EXPERT_PRICING_UPDATED"
)

// Severity levels.
const (
	SeverityInfo    = "info"
	SeveritySuccess = "success"
	SeverityWarning = "warning"
	SeverityError   = "error"
)

type AuditLog struct {
	ID         int64                  `json:"id"`
	Type       string                 `json:"type"`
	Severity   string                 `json:"severity"`
	ActorID    *int64                 `json:"actorId,omitempty"`
	ActorEmail *string                `json:"actorEmail,omitempty"`
	TargetID   *string                `json:"targetId,omitempty"`
	TargetKind *string                `json:"targetKind,omitempty"`
	Summary    string                 `json:"summary"`
	Metadata   map[string]any         `json:"metadata"`
	CreatedAt  time.Time              `json:"createdAt"`
}

type auditScanner interface {
	Scan(dest ...any) error
}

// ScanAuditLog reads columns in this exact order:
//
//	id, type, severity, actor_id, actor_email, target_id, target_kind,
//	summary, metadata, created_at
func ScanAuditLog(s auditScanner) (*AuditLog, error) {
	var a AuditLog
	var (
		actorID     sql.NullInt64
		actorEmail  sql.NullString
		targetID    sql.NullString
		targetKind  sql.NullString
		metadataRaw []byte
	)
	if err := s.Scan(
		&a.ID, &a.Type, &a.Severity,
		&actorID, &actorEmail, &targetID, &targetKind,
		&a.Summary, &metadataRaw, &a.CreatedAt,
	); err != nil {
		return nil, err
	}
	if actorID.Valid {
		a.ActorID = &actorID.Int64
	}
	if actorEmail.Valid {
		a.ActorEmail = &actorEmail.String
	}
	if targetID.Valid {
		a.TargetID = &targetID.String
	}
	if targetKind.Valid {
		a.TargetKind = &targetKind.String
	}
	if len(metadataRaw) > 0 {
		_ = json.Unmarshal(metadataRaw, &a.Metadata)
	}
	if a.Metadata == nil {
		a.Metadata = map[string]any{}
	}
	return &a, nil
}
