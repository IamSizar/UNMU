package pulse

import (
	"errors"
	"strings"
	"testing"
	"time"

	"halalstocks/internal/models"
)

var pulseNow = time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)

func ptr[T any](v T) *T { return &v }

func validInput() models.PulseItemInput {
	return models.PulseItemInput{
		PulseDate: "2026-10-22", Slot: models.PulseSlotGlobal, Classification: models.PulseConfirmed,
		TitleAr: "عنوان", TitleEn: "Title", SummaryAr: "ملخص", SummaryEn: "Summary",
		SourceName: "Source", SourceURL: "https://example.com/a", VerifiedAt: ptr(pulseNow.Add(-time.Hour)),
	}
}

func completeItem(status string, createdBy int64) models.PulseAdminItem {
	return models.PulseAdminItem{
		Status: status, Slot: models.PulseSlotGlobal, CreatedBy: ptr(createdBy),
		TitleAr: "ع", TitleEn: "t", SummaryAr: "م", SummaryEn: "s",
		SourceName: "src", VerifiedAt: ptr(pulseNow),
	}
}

func TestValidateInput(t *testing.T) {
	if errs := ValidateInput(validInput(), pulseNow); len(errs) != 0 {
		t.Fatalf("valid input rejected: %v", errs)
	}
	cases := []struct {
		name   string
		mutate func(*models.PulseItemInput)
		field  string
	}{
		{"bad date", func(i *models.PulseItemInput) { i.PulseDate = "22/10/2026" }, "pulseDate"},
		{"bad slot", func(i *models.PulseItemInput) { i.Slot = "weather" }, "slot"},
		{"bad classification", func(i *models.PulseItemInput) { i.Classification = "rumour" }, "classification"},
		{"title too long", func(i *models.PulseItemInput) { i.TitleEn = strings.Repeat("a", 201) }, "titleEn"},
		{"arabic title counts characters not bytes", func(i *models.PulseItemInput) { i.TitleAr = strings.Repeat("ع", 201) }, "titleAr"},
		{"javascript link", func(i *models.PulseItemInput) { i.SourceURL = "javascript:alert(1)" }, "sourceUrl"},
		{"file link", func(i *models.PulseItemInput) { i.SourceURL = "file:///etc/passwd" }, "sourceUrl"},
		{"link without host", func(i *models.PulseItemInput) { i.SourceURL = "https://" }, "sourceUrl"},
		{"verified in the future", func(i *models.PulseItemInput) { i.VerifiedAt = ptr(pulseNow.Add(time.Hour)) }, "verifiedAt"},
		{"stock id zero", func(i *models.PulseItemInput) { i.StockID = ptr(0) }, "stockId"},
	}
	for _, c := range cases {
		in := validInput()
		c.mutate(&in)
		if errs := ValidateInput(in, pulseNow); errs[c.field] == "" {
			t.Errorf("%s: expected an error on %s, got %v", c.name, c.field, errs)
		}
	}
	// 200 Arabic characters is exactly at the limit and must pass (counted in
	// characters, not bytes).
	in := validInput()
	in.TitleAr = strings.Repeat("ع", 200)
	if errs := ValidateInput(in, pulseNow); errs["titleAr"] != "" {
		t.Errorf("200 Arabic characters should be accepted: %v", errs)
	}
	// A verification time a minute ahead is clock skew, not an error.
	in = validInput()
	in.VerifiedAt = ptr(pulseNow.Add(time.Minute))
	if errs := ValidateInput(in, pulseNow); errs["verifiedAt"] != "" {
		t.Errorf("small clock skew should be tolerated: %v", errs)
	}
}

func TestNormalizeInput(t *testing.T) {
	in := validInput()
	in.TitleEn = "  padded  "
	in.Slot = models.PulseSlotSharia
	in.IsSensitive = false
	out := NormalizeInput(in)
	if out.TitleEn != "padded" {
		t.Errorf("not trimmed: %q", out.TitleEn)
	}
	if !out.IsSensitive {
		t.Error("the Sharia slot must always be sensitive")
	}
}

func TestCompletenessErrors(t *testing.T) {
	if errs := CompletenessErrors(completeItem("draft", 1)); len(errs) != 0 {
		t.Fatalf("complete item flagged: %v", errs)
	}
	it := completeItem("draft", 1)
	it.TitleAr, it.SummaryEn, it.SourceName, it.VerifiedAt = "", "", "", nil
	errs := CompletenessErrors(it)
	for _, f := range []string{"titleAr", "summaryEn", "sourceName", "verifiedAt"} {
		if errs[f] == "" {
			t.Errorf("missing %s was not reported", f)
		}
	}
}

func staff(id int64, roles ...string) Actor {
	a := Actor{UserID: id, Roles: map[string]bool{}}
	for _, r := range roles {
		a.Roles[r] = true
	}
	return a
}

func kindOf(err error) string {
	var re *RuleError
	if errors.As(err, &re) {
		return re.Kind
	}
	return ""
}

func TestCheckAction(t *testing.T) {
	const author, other = int64(10), int64(20)
	admin := Actor{UserID: other, IsAdmin: true}
	cases := []struct {
		name   string
		action string
		item   models.PulseAdminItem
		actor  Actor
		want   string // "" = allowed, else error kind
	}{
		{"editor edits a draft", DoEdit, completeItem("draft", author), staff(author, models.PulseRoleEditor), ""},
		{"viewer cannot edit", DoEdit, completeItem("draft", author), staff(other), "forbidden"},
		{"cannot edit once in review", DoEdit, completeItem("in_review", author), staff(author, models.PulseRoleEditor), "state"},
		{"cannot delete a published item", DoDelete, completeItem("published", author), admin, "state"},
		{"editor submits", DoSubmit, completeItem("draft", author), staff(author, models.PulseRoleEditor), ""},
		{"reviewer reviews someone else's item", DoReview, completeItem("in_review", author), staff(other, models.PulseRoleReviewer), ""},
		{"author cannot review own item", DoReview, completeItem("in_review", author), staff(author, models.PulseRoleReviewer), "forbidden"},
		{"admin author cannot review own item either", DoReview, completeItem("in_review", other), admin, "forbidden"},
		{"editor cannot approve", DoApprove, completeItem("in_review", author), staff(other, models.PulseRoleEditor), "forbidden"},
		{"approver approves", DoApprove, completeItem("in_review", author), staff(other, models.PulseRoleApprover), ""},
		{"author cannot approve own item", DoApprove, completeItem("in_review", author), staff(author, models.PulseRoleApprover), "forbidden"},
		{"cannot approve a draft", DoApprove, completeItem("draft", author), staff(other, models.PulseRoleApprover), "state"},
		{"reviewer can reject", DoReject, completeItem("in_review", author), staff(other, models.PulseRoleReviewer), ""},
		{"approver publishes approved", DoPublish, completeItem("approved", author), staff(other, models.PulseRoleApprover), ""},
		{"cannot publish a draft", DoPublish, completeItem("draft", author), admin, "state"},
		{"cannot publish in review", DoPublish, completeItem("in_review", author), admin, "state"},
		{"reviewer cannot publish", DoPublish, completeItem("approved", author), staff(other, models.PulseRoleReviewer), "forbidden"},
		{"admin corrects a published item", DoCorrect, completeItem("published", author), admin, ""},
		{"editor cannot correct a published item", DoCorrect, completeItem("published", author), staff(other, models.PulseRoleEditor), "forbidden"},
		{"unknown action", "explode", completeItem("draft", author), admin, "invalid"},
	}
	for _, c := range cases {
		got := kindOf(CheckAction(c.action, c.item, c.actor))
		if got != c.want {
			t.Errorf("%s: kind=%q, want %q", c.name, got, c.want)
		}
	}
}

func TestCheckApproval(t *testing.T) {
	sensitive := completeItem("in_review", 1)
	sensitive.IsSensitive = true
	if kindOf(CheckApproval(sensitive)) != "state" {
		t.Error("a sensitive item without a reviewer must not be approvable")
	}
	sensitive.ReviewedBy = ptr(int64(2))
	if err := CheckApproval(sensitive); err != nil {
		t.Errorf("reviewed sensitive item should pass: %v", err)
	}
	incomplete := completeItem("in_review", 1)
	incomplete.TitleEn = ""
	if kindOf(CheckApproval(incomplete)) != "invalid" {
		t.Error("an incomplete item must not be approvable")
	}
	if err := CheckApproval(completeItem("in_review", 1)); err != nil {
		t.Errorf("complete non-sensitive item should pass without a reviewer: %v", err)
	}
}

func TestCheckSchedule(t *testing.T) {
	cases := []struct {
		name string
		at   time.Time
		ok   bool
	}{
		{"one hour ahead", pulseNow.Add(time.Hour), true},
		{"in the past", pulseNow.Add(-time.Minute), false},
		{"exactly now", pulseNow, false},
		{"29 days ahead", pulseNow.AddDate(0, 0, 29), true},
		{"31 days ahead", pulseNow.AddDate(0, 0, 31), false},
	}
	for _, c := range cases {
		if got := CheckSchedule(c.at, pulseNow) == nil; got != c.ok {
			t.Errorf("%s: ok=%v, want %v", c.name, got, c.ok)
		}
	}
}

func TestValidateNote(t *testing.T) {
	if ValidateNote("  ", true) == nil {
		t.Error("a required note must not be blank")
	}
	if ValidateNote("", false) != nil {
		t.Error("an optional note may be empty")
	}
	if ValidateNote(strings.Repeat("x", 1001), false) == nil {
		t.Error("an over-long note must be rejected")
	}
}
