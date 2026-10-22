package models

import (
	"encoding/json"
	"time"
)

// =============================================================================
// pulse_admin.go — types for the Pulse admin CMS (editors, reviewers,
// approvers and system admins). The public shapes live in pulse.go.
// =============================================================================

// Pulse staff roles. users.role = 'ADMIN' is the system admin and holds every
// permission without needing a pulse_staff row.
const (
	PulseRoleEditor   = "editor"
	PulseRoleReviewer = "reviewer"
	PulseRoleApprover = "approver"
)

// Workflow actions, as written to the change log (pulse_item_events.action).
const (
	PulseActionCreated     = "created"
	PulseActionEdited      = "edited"
	PulseActionSubmitted   = "submitted"
	PulseActionReviewed    = "reviewed"
	PulseActionRejected    = "rejected"
	PulseActionApproved    = "approved"
	PulseActionScheduled   = "scheduled"
	PulseActionPublished   = "published"
	PulseActionUpdated     = "updated"
	PulseActionCorrected   = "corrected"
	PulseActionArchived    = "archived"
	PulseActionUnscheduled = "unscheduled"
	// Two-person correction flow (migration 0057).
	PulseActionCorrectionProposed = "correction_proposed"
	PulseActionCorrectionRejected = "correction_rejected"
)

// PulseItemInput is what an editor sends to create or change an item.
// StockID is a pointer so "no linked stock" differs from stock 0.
type PulseItemInput struct {
	PulseDate      string     `json:"pulseDate"` // YYYY-MM-DD
	Slot           string     `json:"slot"`
	Classification string     `json:"classification"`
	IsSensitive    bool       `json:"isSensitive"`
	TitleAr        string     `json:"titleAr"`
	TitleEn        string     `json:"titleEn"`
	SummaryAr      string     `json:"summaryAr"`
	SummaryEn      string     `json:"summaryEn"`
	DetailsAr      string     `json:"detailsAr"`
	DetailsEn      string     `json:"detailsEn"`
	EvidenceAr     string     `json:"evidenceAr"`
	EvidenceEn     string     `json:"evidenceEn"`
	SourceName     string     `json:"sourceName"`
	SourceURL      string     `json:"sourceUrl"`
	VerifiedAt     *time.Time `json:"verifiedAt"`
	StockID        *int       `json:"stockId"`
}

// PulseAdminItem is the full row, in any status, for the dashboard.
type PulseAdminItem struct {
	ID             int64          `json:"id"`
	PulseDate      string         `json:"pulseDate"`
	Slot           string         `json:"slot"`
	Classification string         `json:"classification"`
	Status         string         `json:"status"`
	IsSensitive    bool           `json:"isSensitive"`
	TitleAr        string         `json:"titleAr"`
	TitleEn        string         `json:"titleEn"`
	SummaryAr      string         `json:"summaryAr"`
	SummaryEn      string         `json:"summaryEn"`
	DetailsAr      string         `json:"detailsAr"`
	DetailsEn      string         `json:"detailsEn"`
	EvidenceAr     string         `json:"evidenceAr"`
	EvidenceEn     string         `json:"evidenceEn"`
	SourceName     string         `json:"sourceName"`
	SourceURL      string         `json:"sourceUrl"`
	VerifiedAt     *time.Time     `json:"verifiedAt"`
	Stock          *PulseStockRef `json:"stock"`
	Version        int            `json:"version"`
	ChangeKind     *string        `json:"changeKind"`
	LastChangedAt  *time.Time     `json:"lastChangedAt"`
	PublishAt      *time.Time     `json:"publishAt"`
	PublishedAt    *time.Time     `json:"publishedAt"`
	CreatedBy      *int64         `json:"createdBy"`
	ReviewedBy     *int64         `json:"reviewedBy"`
	ReviewedAt     *time.Time     `json:"reviewedAt"`
	ApprovedBy     *int64         `json:"approvedBy"`
	ApprovedAt     *time.Time     `json:"approvedAt"`
	CreatedAt      time.Time      `json:"createdAt"`
	UpdatedAt      time.Time      `json:"updatedAt"`
}

// PulseVersion is one stored snapshot of an item (spec §14).
type PulseVersion struct {
	Version   int             `json:"version"`
	Reason    string          `json:"reason"`
	Snapshot  json.RawMessage `json:"snapshot"`
	CreatedBy *int64          `json:"createdBy"`
	CreatedAt time.Time       `json:"createdAt"`
}

// PulseChangeLogEntry is one row of the append-only change log (spec §15).
type PulseChangeLogEntry struct {
	ID         int64     `json:"id"`
	Action     string    `json:"action"`
	ActorID    *int64    `json:"actorId"`
	ActorEmail string    `json:"actorEmail"`
	FromStatus string    `json:"fromStatus"`
	ToStatus   string    `json:"toStatus"`
	Note       string    `json:"note"`
	CreatedAt  time.Time `json:"createdAt"`
}

// PulseStaffMember is a user holding one Pulse role.
type PulseStaffMember struct {
	ID        int64     `json:"id"`
	UserID    int64     `json:"userId"`
	Email     string    `json:"email"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"createdAt"`
}

// PulseItemStats is the per-item engagement row of the analytics page.
type PulseItemStats struct {
	ItemID int64  `json:"itemId"`
	Date   string `json:"date"`
	Slot   string `json:"slot"`
	Title  string `json:"title"`
	Opens  int    `json:"opens"`
	Reads  int    `json:"reads"` // read_complete events
	Saves  int    `json:"saves"`
	Shares int    `json:"shares"`
}

// PulseAnalytics is the basic analytics summary (spec §18).
type PulseAnalytics struct {
	From           string           `json:"from"`
	To             string           `json:"to"`
	DayViews       int              `json:"dayViews"`       // today's-Pulse screen opens
	ItemOpens      int              `json:"itemOpens"`      // item detail opens
	UniqueReaders  int              `json:"uniqueReaders"`  // distinct users who opened an item
	ReadCompletion float64          `json:"readCompletion"` // read_complete / item opens, 0..1
	Saves          int              `json:"saves"`
	Shares         int              `json:"shares"`
	ReturnRate     float64          `json:"returnRate"` // users seen on 2+ days / users seen, 0..1
	Items          []PulseItemStats `json:"items"`      // sorted and compared client-side
}

// PulsePendingCorrection is a correction proposed for a published item that a
// different approver has not yet applied or rejected (migration 0057).
type PulsePendingCorrection struct {
	ID         int64          `json:"id"`
	ItemID     int64          `json:"itemId"`
	ProposedBy *int64         `json:"proposedBy"`
	Kind       string         `json:"kind"` // "updated" or "corrected"
	Note       string         `json:"note"`
	Input      PulseItemInput `json:"input"`
	CreatedAt  time.Time      `json:"createdAt"`
}
