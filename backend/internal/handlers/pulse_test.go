package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"halalstocks/internal/models"

	"github.com/gin-gonic/gin"
)

// Unit tests for the Pulse request helpers. Database-backed behaviour is
// covered by repositories/pulse_integration_test.go.

func TestPulseToday_RollsOverAtMidnightInBaghdad(t *testing.T) {
	cases := []struct {
		name string
		utc  time.Time
		want string
	}{
		// 20:59 UTC is 23:59 in UTC+3: still the same day.
		{"just before midnight", time.Date(2026, 10, 22, 20, 59, 0, 0, time.UTC), "2026-10-22"},
		// 21:00 UTC is 00:00 in UTC+3: next day.
		{"at midnight", time.Date(2026, 10, 22, 21, 0, 0, 0, time.UTC), "2026-10-23"},
		{"morning", time.Date(2026, 10, 22, 6, 0, 0, 0, time.UTC), "2026-10-22"},
	}
	for _, c := range cases {
		if got := pulseToday(c.utc); got != c.want {
			t.Errorf("%s: pulseToday = %s, want %s", c.name, got, c.want)
		}
	}
}

func TestParsePulseDate(t *testing.T) {
	cases := []struct {
		in     string
		wantOK bool
		want   string
	}{
		{"", true, ""},
		{"2026-10-22", true, "2026-10-22"},
		{"2026-13-01", false, ""},  // no month 13
		{"2026-02-30", false, ""},  // no 30 Feb
		{"22-10-2026", false, ""},  // wrong order
		{"2026-10-22x", false, ""}, // trailing junk
		{"' OR 1=1 --", false, ""}, // an injection attempt is just an invalid date
	}
	for _, c := range cases {
		got, ok := parsePulseDate(c.in)
		if ok != c.wantOK || got != c.want {
			t.Errorf("parsePulseDate(%q) = (%q,%v), want (%q,%v)", c.in, got, ok, c.want, c.wantOK)
		}
	}
}

func TestParsePulsePaging(t *testing.T) {
	cases := []struct {
		query              string
		wantLimit, wantOff int
		wantOK             bool
	}{
		{"", 30, 0, true},
		{"limit=10&offset=20", 10, 20, true},
		{"limit=5000", 100, 0, true}, // capped, not rejected
		{"limit=0", 0, 0, false},
		{"limit=-3", 0, 0, false},
		{"limit=abc", 0, 0, false},
		{"offset=-1", 0, 0, false},
	}
	for _, c := range cases {
		ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
		ctx.Request = httptest.NewRequest(http.MethodGet, "/x?"+c.query, nil)
		l, o, ok := parsePulsePaging(ctx)
		if ok != c.wantOK || (ok && (l != c.wantLimit || o != c.wantOff)) {
			t.Errorf("paging %q = (%d,%d,%v), want (%d,%d,%v)", c.query, l, o, ok, c.wantLimit, c.wantOff, c.wantOK)
		}
	}
}

func TestValidatePulseEvent(t *testing.T) {
	one, zero := int64(1), int64(0)
	cases := []struct {
		name    string
		req     pulseEventRequest
		wantErr bool
	}{
		{"view_day without item", pulseEventRequest{Event: models.PulseEventViewDay}, false},
		{"view_day with item is wrong", pulseEventRequest{Event: models.PulseEventViewDay, ItemID: &one}, true},
		{"open_item with item", pulseEventRequest{Event: models.PulseEventOpenItem, ItemID: &one}, false},
		{"open_item without item", pulseEventRequest{Event: models.PulseEventOpenItem}, true},
		{"open_item with id 0", pulseEventRequest{Event: models.PulseEventOpenItem, ItemID: &zero}, true},
		{"share with item", pulseEventRequest{Event: models.PulseEventShare, ItemID: &one}, false},
		{"unknown event", pulseEventRequest{Event: "like", ItemID: &one}, true},
		{"empty event", pulseEventRequest{}, true},
	}
	for _, c := range cases {
		got := validatePulseEvent(c.req) != ""
		if got != c.wantErr {
			t.Errorf("%s: error=%v, want %v", c.name, got, c.wantErr)
		}
	}
}

func TestPulseMarker(t *testing.T) {
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	hourAgo := now.Add(-time.Hour)
	dayAgo := now.Add(-24 * time.Hour)
	corrected, updated := models.PulseChangeCorrected, models.PulseChangeUpdated

	cases := []struct {
		name      string
		published *time.Time
		change    *string
		want      string
	}{
		{"fresh and untouched is new", &hourAgo, nil, "new"},
		{"old and untouched has no marker", &dayAgo, nil, ""},
		{"corrected wins over new", &hourAgo, &corrected, "corrected"},
		{"updated on an old item", &dayAgo, &updated, "updated"},
		{"never published has no marker", nil, nil, ""},
	}
	for _, c := range cases {
		if got := models.PulseMarker(c.published, c.change, now); got != c.want {
			t.Errorf("%s: marker = %q, want %q", c.name, got, c.want)
		}
	}
}
