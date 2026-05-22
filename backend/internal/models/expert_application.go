package models

import (
	"database/sql"
	"encoding/json"
	"time"
)

// =============================================================================
// ExpertApplication — a user's request to be promoted to EXPERT.
// Backed by table `expert_applications` (migration 0002).
//
// Lifecycle: pending -> approved | rejected
// At most ONE pending application per user (partial unique index).
// =============================================================================

const (
	ApplicationStatusPending  = "pending"
	ApplicationStatusApproved = "approved"
	ApplicationStatusRejected = "rejected"
)

type ExpertApplication struct {
	ID              int64      `json:"id"`
	UserID          int64      `json:"userId"`
	FullName        string     `json:"fullName"`
	Expertise       string     `json:"expertise"`
	Bio             string     `json:"bio"`
	Credentials     []string   `json:"credentials"`
	Country         *string    `json:"country,omitempty"`
	SampleLinks     []string   `json:"sampleLinks"`
	Status          string     `json:"status"`
	RejectionReason *string    `json:"rejectionReason,omitempty"`
	SubmittedAt     time.Time  `json:"submittedAt"`
	ReviewedAt      *time.Time `json:"reviewedAt,omitempty"`
	ReviewedBy      *int64     `json:"reviewedBy,omitempty"`

	// Optional uploads from the applicant — added in mig 0023. Both
	// are nullable strings; nil means "no file submitted".
	ResumeURL *string `json:"resumeUrl,omitempty"`
	AvatarURL *string `json:"avatarUrl,omitempty"`

	// Joined fields populated when listing for the admin dashboard.
	UserEmail        string `json:"userEmail,omitempty"`
	UserAvatar       string `json:"userAvatar,omitempty"`
	ReviewerEmail    string `json:"reviewerEmail,omitempty"`
}

// applicationRowScanner mirrors the postRowScanner pattern in social.go.
type applicationRowScanner interface {
	Scan(dest ...any) error
}

// ScanExpertApplication scans columns in this exact order:
//
//	id, user_id, full_name, expertise, bio, credentials, country, sample_links,
//	status, rejection_reason, submitted_at, reviewed_at, reviewed_by,
//	resume_url, avatar_url
func ScanExpertApplication(s applicationRowScanner) (*ExpertApplication, error) {
	var a ExpertApplication
	var (
		country         sql.NullString
		credentialsRaw  []byte
		sampleLinksRaw  []byte
		rejectionReason sql.NullString
		reviewedAt      sql.NullTime
		reviewedBy      sql.NullInt64
		resumeURL       sql.NullString
		avatarURL       sql.NullString
	)
	if err := s.Scan(
		&a.ID, &a.UserID, &a.FullName, &a.Expertise, &a.Bio,
		&credentialsRaw, &country, &sampleLinksRaw,
		&a.Status, &rejectionReason, &a.SubmittedAt, &reviewedAt, &reviewedBy,
		&resumeURL, &avatarURL,
	); err != nil {
		return nil, err
	}
	if country.Valid {
		a.Country = &country.String
	}
	if rejectionReason.Valid {
		a.RejectionReason = &rejectionReason.String
	}
	if reviewedAt.Valid {
		a.ReviewedAt = &reviewedAt.Time
	}
	if reviewedBy.Valid {
		a.ReviewedBy = &reviewedBy.Int64
	}
	if resumeURL.Valid {
		a.ResumeURL = &resumeURL.String
	}
	if avatarURL.Valid {
		a.AvatarURL = &avatarURL.String
	}
	if len(credentialsRaw) > 0 {
		_ = json.Unmarshal(credentialsRaw, &a.Credentials)
	}
	if a.Credentials == nil {
		a.Credentials = []string{}
	}
	if len(sampleLinksRaw) > 0 {
		_ = json.Unmarshal(sampleLinksRaw, &a.SampleLinks)
	}
	if a.SampleLinks == nil {
		a.SampleLinks = []string{}
	}
	return &a, nil
}
