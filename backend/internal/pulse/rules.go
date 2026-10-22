// Package pulse holds the UNMU Pulse editorial rules as pure functions.
package pulse

import (
	"fmt"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"halalstocks/internal/models"
)

// =============================================================================
// rules.go — the Pulse editorial rules as pure functions (no database,
// no HTTP), so every rule can be unit-tested and the same rules are applied by
// every caller.
//
// Two groups of rules:
//   1. INPUT rules      shape and length of what an editor typed.
//   2. WORKFLOW rules   who may move an item to which status, and when.
//
// The database repeats the hard ones as CHECK constraints (migration 0056);
// these functions run first so the dashboard gets a friendly message instead
// of a constraint error.
//
// Decision (2026-10-22): the author of an item can never review or approve it,
// not even a system admin. Two people always look at every published item.
// =============================================================================

// Field length limits. Generous, but bounded so one bad request cannot store a
// novel in a title column.
const (
	pulseMaxTitle    = 200
	pulseMaxSummary  = 600
	pulseMaxDetails  = 20000
	pulseMaxEvidence = 5000
	pulseMaxSource   = 200
	pulseMaxURL      = 2000
	pulseMaxNote     = 1000
	// pulseClockSkew lets "verified just now" survive a slightly fast client clock.
	pulseClockSkew = 5 * time.Minute
)

// FieldErrors maps a JSON field name to a human message.
type FieldErrors map[string]string

// RuleError is returned when a workflow rule refuses an action.
type RuleError struct {
	// Kind is "forbidden" (wrong role / four-eyes), "state" (wrong status) or
	// "invalid" (missing or malformed data). Handlers map it to 403 / 409 / 422.
	Kind    string
	Message string
	Fields  FieldErrors
}

func (e *RuleError) Error() string { return e.Message }

func ruleErr(kind, format string, a ...any) *RuleError {
	return &RuleError{Kind: kind, Message: fmt.Sprintf(format, a...)}
}

// Actor is the signed-in staff member performing an action.
type Actor struct {
	UserID  int64
	IsAdmin bool            // users.role = 'ADMIN': holds every Pulse role
	Roles   map[string]bool // pulse_staff roles
}

// Has reports whether the actor holds the role (admins hold all of them).
func (a Actor) Has(role string) bool { return a.IsAdmin || a.Roles[role] }

// IsStaff reports whether the actor may enter the Pulse CMS at all.
func (a Actor) IsStaff() bool { return a.IsAdmin || len(a.Roles) > 0 }

// ─── Input rules ──────────────────────────────────────────────────────────

func tooLong(s string, max int) bool { return utf8.RuneCountInString(s) > max }

// NormalizeInput trims whitespace and forces the Sharia slot to be
// sensitive (a Sharia item is never allowed to skip the reviewer).
func NormalizeInput(in models.PulseItemInput) models.PulseItemInput {
	for _, f := range []*string{
		&in.TitleAr, &in.TitleEn, &in.SummaryAr, &in.SummaryEn,
		&in.DetailsAr, &in.DetailsEn, &in.EvidenceAr, &in.EvidenceEn,
		&in.SourceName, &in.SourceURL,
	} {
		*f = strings.TrimSpace(*f)
	}
	if in.Slot == models.PulseSlotSharia {
		in.IsSensitive = true
	}
	return in
}

// ValidateInput checks the SHAPE of an item (what must hold even for a
// draft). It does not demand completeness; see CompletenessErrors.
func ValidateInput(in models.PulseItemInput, now time.Time) FieldErrors {
	errs := FieldErrors{}
	if _, err := time.Parse("2006-01-02", in.PulseDate); err != nil {
		errs["pulseDate"] = "Pick a valid date"
	}
	switch in.Slot {
	case models.PulseSlotGlobal, models.PulseSlotGulf, models.PulseSlotSharia, models.PulseSlotOpportunity:
	default:
		errs["slot"] = "Pick one of the four slots"
	}
	if in.Classification != models.PulseConfirmed && in.Classification != models.PulseAnalysis {
		errs["classification"] = "Choose confirmed information or analysis"
	}
	limits := []struct {
		field, value string
		max          int
	}{
		{"titleAr", in.TitleAr, pulseMaxTitle}, {"titleEn", in.TitleEn, pulseMaxTitle},
		{"summaryAr", in.SummaryAr, pulseMaxSummary}, {"summaryEn", in.SummaryEn, pulseMaxSummary},
		{"detailsAr", in.DetailsAr, pulseMaxDetails}, {"detailsEn", in.DetailsEn, pulseMaxDetails},
		{"evidenceAr", in.EvidenceAr, pulseMaxEvidence}, {"evidenceEn", in.EvidenceEn, pulseMaxEvidence},
		{"sourceName", in.SourceName, pulseMaxSource}, {"sourceUrl", in.SourceURL, pulseMaxURL},
	}
	for _, l := range limits {
		if tooLong(l.value, l.max) {
			errs[l.field] = fmt.Sprintf("Keep this under %d characters", l.max)
		}
	}
	// Only http(s) links: a "javascript:" or "file:" source link would run or
	// leak when a reader taps it.
	if in.SourceURL != "" && errs["sourceUrl"] == "" {
		u, err := url.Parse(in.SourceURL)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			errs["sourceUrl"] = "Use a full web link starting with http:// or https://"
		}
	}
	if in.VerifiedAt != nil && in.VerifiedAt.After(now.Add(pulseClockSkew)) {
		errs["verifiedAt"] = "The verification time cannot be in the future"
	}
	if in.StockID != nil && *in.StockID < 1 {
		errs["stockId"] = "Pick a valid stock"
	}
	return errs
}

// CompletenessErrors lists what is still missing before an item may leave
// draft (spec §5, §19): both languages, a source, and a verification time.
func CompletenessErrors(it models.PulseAdminItem) FieldErrors {
	errs := FieldErrors{}
	required := []struct{ field, value string }{
		{"titleAr", it.TitleAr}, {"titleEn", it.TitleEn},
		{"summaryAr", it.SummaryAr}, {"summaryEn", it.SummaryEn},
		{"sourceName", it.SourceName},
	}
	for _, r := range required {
		if r.value == "" {
			errs[r.field] = "Required before review"
		}
	}
	if it.VerifiedAt == nil {
		errs["verifiedAt"] = "Required before review"
	}
	return errs
}

// ─── Workflow rules ───────────────────────────────────────────────────────

// Workflow actions accepted by CheckAction.
const (
	DoEdit       = "edit"
	DoDelete     = "delete"
	DoSubmit     = "submit"
	DoReview     = "review"
	DoReject     = "reject"
	DoApprove    = "approve"
	DoSchedule   = "schedule"
	DoUnschedule = "unschedule"
	DoPublish    = "publish"
	DoArchive    = "archive"
	DoCorrect    = "correct" // APPLY a proposed correction (a different approver than the proposer)
	// DoProposeCorrection files a correction/update for a published item. It does
	// not change the item: a second person must apply it via DoCorrect.
	DoProposeCorrection = "propose_correction"
)

// pulseRule describes one workflow action: which statuses it may start from,
// which Pulse role it needs, and whether the author is barred (four-eyes).
type pulseRule struct {
	from        []string
	anyOfRoles  []string
	authorBlock bool
}

var actionRules = map[string]pulseRule{
	DoEdit:       {[]string{models.PulseStatusDraft}, []string{models.PulseRoleEditor}, false},
	DoDelete:     {[]string{models.PulseStatusDraft}, []string{models.PulseRoleEditor}, false},
	DoSubmit:     {[]string{models.PulseStatusDraft}, []string{models.PulseRoleEditor}, false},
	DoReview:     {[]string{models.PulseStatusInReview}, []string{models.PulseRoleReviewer}, true},
	DoReject:     {[]string{models.PulseStatusInReview}, []string{models.PulseRoleReviewer, models.PulseRoleApprover}, true},
	DoApprove:    {[]string{models.PulseStatusInReview}, []string{models.PulseRoleApprover}, true},
	DoSchedule:   {[]string{models.PulseStatusApproved}, []string{models.PulseRoleApprover}, false},
	DoUnschedule: {[]string{models.PulseStatusScheduled}, []string{models.PulseRoleApprover}, false},
	DoPublish:    {[]string{models.PulseStatusApproved, models.PulseStatusScheduled}, []string{models.PulseRoleApprover}, false},
	DoArchive:    {[]string{models.PulseStatusPublished}, []string{models.PulseRoleApprover}, false},
	DoCorrect:    {[]string{models.PulseStatusPublished}, []string{models.PulseRoleApprover}, false},
	DoProposeCorrection: {[]string{models.PulseStatusPublished},
		[]string{models.PulseRoleEditor, models.PulseRoleApprover}, false},
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// CheckAction decides whether the actor may perform the action on the
// item right now. It returns nil when allowed, otherwise a *RuleError.
func CheckAction(action string, it models.PulseAdminItem, actor Actor) error {
	rule, ok := actionRules[action]
	if !ok {
		return ruleErr("invalid", "Unknown action %q", action)
	}
	if !contains(rule.from, it.Status) {
		return ruleErr("state", "This item is %s, so \"%s\" is not possible right now", it.Status, action)
	}
	allowed := false
	for _, role := range rule.anyOfRoles {
		allowed = allowed || actor.Has(role)
	}
	if !allowed {
		return ruleErr("forbidden", "Your Pulse role does not allow this action")
	}
	if rule.authorBlock && it.CreatedBy != nil && *it.CreatedBy == actor.UserID {
		return ruleErr("forbidden", "You wrote this item, so someone else must %s it", action)
	}
	return nil
}

// CheckApproval adds the rules that need the whole item:
//   - a sensitive item must have been reviewed first;
//   - a sensitive item's approver must be someone other than its reviewer
//     (decision 2026-10-22: three people touch a sensitive item);
//   - nothing is approved while required fields are missing.
func CheckApproval(it models.PulseAdminItem, actor Actor) error {
	if it.IsSensitive && it.ReviewedBy == nil {
		return ruleErr("state", "This item is sensitive: a reviewer must review it before approval")
	}
	if it.IsSensitive && it.ReviewedBy != nil && *it.ReviewedBy == actor.UserID {
		return ruleErr("forbidden", "You reviewed this sensitive item, so someone else must approve it")
	}
	if errs := CompletenessErrors(it); len(errs) > 0 {
		return &RuleError{Kind: "invalid", Message: "The item is incomplete", Fields: errs}
	}
	return nil
}

// CheckCorrectionReview decides whether the actor may apply or reject a
// proposed correction: they need the approver role and must not be the person
// who proposed it (decision 2026-10-22: a correction is never applied by its
// own author).
func CheckCorrectionReview(it models.PulseAdminItem, proposedBy *int64, actor Actor) error {
	if err := CheckAction(DoCorrect, it, actor); err != nil {
		return err
	}
	if proposedBy != nil && *proposedBy == actor.UserID {
		return ruleErr("forbidden", "You proposed this correction, so someone else must apply it")
	}
	return nil
}

// CheckSchedule validates a requested publish time.
func CheckSchedule(publishAt time.Time, now time.Time) error {
	if !publishAt.After(now) {
		return ruleErr("invalid", "Pick a publish time in the future")
	}
	if publishAt.After(now.AddDate(0, 0, 30)) {
		return ruleErr("invalid", "Items can be scheduled at most 30 days ahead")
	}
	return nil
}

// ValidateNote checks the free-text note sent with a workflow action.
func ValidateNote(note string, required bool) error {
	note = strings.TrimSpace(note)
	if required && note == "" {
		return ruleErr("invalid", "Please add a short note explaining the change")
	}
	if tooLong(note, pulseMaxNote) {
		return ruleErr("invalid", "The note is too long")
	}
	return nil
}
