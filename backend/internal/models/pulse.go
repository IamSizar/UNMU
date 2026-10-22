package models

import "time"

// =============================================================================
// pulse.go — types for UNMU Pulse (نبض أنمو), the daily curated briefing.
//
// Tables: migration 0056_pulse.sql. Plan: docs/pulse/PLAN.md.
//
// These structs are the JSON the mobile app and the admin dashboard see. Both
// languages are always sent (…Ar / …En) and the client picks one from the
// user's locale, so one cached response serves either language.
// =============================================================================

// Pulse slots — the four items shown every day (spec §2).
const (
	PulseSlotGlobal      = "global"
	PulseSlotGulf        = "gulf"
	PulseSlotSharia      = "sharia"
	PulseSlotOpportunity = "opportunity"
)

// PulseSlotOrder is the display order on the home screen.
var PulseSlotOrder = []string{
	PulseSlotGlobal, PulseSlotGulf, PulseSlotSharia, PulseSlotOpportunity,
}

// Pulse classifications (spec §4). Shown to users as two distinct badges.
const (
	PulseConfirmed = "confirmed" // verified fact with a source / evidence
	PulseAnalysis  = "analysis"  // explanation or interpretation
)

// Pulse item lifecycle (spec §6, §16).
const (
	PulseStatusDraft     = "draft"
	PulseStatusInReview  = "in_review"
	PulseStatusApproved  = "approved"
	PulseStatusScheduled = "scheduled"
	PulseStatusPublished = "published"
	PulseStatusArchived  = "archived"
)

// Change kinds recorded when a published item is edited (spec §14).
const (
	PulseChangeUpdated   = "updated"
	PulseChangeCorrected = "corrected"
)

// Pulse analytics events (spec §18); must match pulse_events_event_check.
const (
	PulseEventViewDay      = "view_day"
	PulseEventOpenItem     = "open_item"
	PulseEventReadComplete = "read_complete"
	PulseEventSave         = "save"
	PulseEventUnsave       = "unsave"
	PulseEventShare        = "share"
	PulseEventOpenSource   = "open_source"
	PulseEventOpenStock    = "open_stock"
)

// PulseNewWindow is how long after publishing an untouched item keeps the
// "New" marker.
const PulseNewWindow = 12 * time.Hour

// PulseStockRef is the stock / company a Pulse item is linked to. The app
// opens StockDetailScreen with Ticker + Exchange.
type PulseStockRef struct {
	ID       int    `json:"id"`
	Ticker   string `json:"ticker"`
	Exchange string `json:"exchange"`
	Name     string `json:"name"`
}

// PulseItem is a published Pulse item as the app sees it.
//
// Details and evidence are only filled for the detail endpoint
// (omitempty keeps list payloads small).
type PulseItem struct {
	ID             int64  `json:"id"`
	Date           string `json:"date"` // YYYY-MM-DD, in the Pulse time zone
	Slot           string `json:"slot"`
	Classification string `json:"classification"`

	TitleAr   string `json:"titleAr"`
	TitleEn   string `json:"titleEn"`
	SummaryAr string `json:"summaryAr"`
	SummaryEn string `json:"summaryEn"`

	DetailsAr  string `json:"detailsAr,omitempty"`
	DetailsEn  string `json:"detailsEn,omitempty"`
	EvidenceAr string `json:"evidenceAr,omitempty"`
	EvidenceEn string `json:"evidenceEn,omitempty"`

	SourceName string     `json:"sourceName"`
	SourceURL  string     `json:"sourceUrl"`
	VerifiedAt *time.Time `json:"verifiedAt"`

	PublishedAt   *time.Time `json:"publishedAt"`
	LastChangedAt *time.Time `json:"lastChangedAt"`
	ChangeKind    *string    `json:"changeKind"`
	// Marker is what the card shows: "new", "updated", "corrected" or "".
	Marker string `json:"marker"`

	Stock *PulseStockRef `json:"stock"`
	// Relation says how the linked stock relates to this user:
	// "portfolio" (owned shares), "watchlist" (followed, no shares) or null.
	Relation *string `json:"relation"`
	IsSaved  bool    `json:"isSaved"`
}

// PulseMarker decides which status marker a published item shows.
// A change always wins over "new": a corrected item must say so even if it
// was published an hour ago.
func PulseMarker(publishedAt *time.Time, changeKind *string, now time.Time) string {
	if changeKind != nil && *changeKind != "" {
		return *changeKind
	}
	if publishedAt != nil && now.Sub(*publishedAt) < PulseNewWindow {
		return "new"
	}
	return ""
}

// PulseDay is the response of "today's Pulse": up to four items in slot order.
type PulseDay struct {
	Date      string      `json:"date"`
	Items     []PulseItem `json:"items"`
	UpdatedAt *time.Time  `json:"updatedAt"` // latest publish / change among the items
}
