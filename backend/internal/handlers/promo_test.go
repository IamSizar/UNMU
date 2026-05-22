package handlers

import (
	"testing"
	"time"
)

// parseOptionalDate is the entry point for every date field on the
// admin promo create/update forms. It must accept three shapes:
//
//   - the empty string → (nil, nil), meaning "clear this field"
//   - "YYYY-MM-DD"     → parsed midnight UTC
//   - full RFC 3339    → parsed instant with offset
//
// Anything else must surface as an error so the admin sees a 400
// instead of silently storing a sentinel date.
func TestParseOptionalDate(t *testing.T) {
	cases := []struct {
		name    string
		in      string
		wantNil bool
		wantErr bool
		// year/month/day are only checked when wantNil is false.
		year  int
		month time.Month
		day   int
	}{
		{name: "empty string clears the field", in: "", wantNil: true},
		{name: "whitespace also clears", in: "   ", wantNil: true},
		{
			name:  "bare YYYY-MM-DD",
			in:    "2026-05-19",
			year:  2026,
			month: time.May,
			day:   19,
		},
		{
			name:  "RFC3339 zulu",
			in:    "2026-05-19T12:30:00Z",
			year:  2026,
			month: time.May,
			day:   19,
		},
		{
			name:  "RFC3339 with offset",
			in:    "2026-05-19T12:30:00+03:00",
			year:  2026,
			month: time.May,
			day:   19,
		},
		{name: "garbage string errors", in: "not-a-date", wantNil: true, wantErr: true},
		{name: "slash format unsupported", in: "2026/05/19", wantNil: true, wantErr: true},
		{name: "month-name unsupported", in: "May 19, 2026", wantNil: true, wantErr: true},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := parseOptionalDate(c.in)
			if c.wantErr && err == nil {
				t.Fatalf("input %q: expected error, got nil", c.in)
			}
			if !c.wantErr && err != nil {
				t.Fatalf("input %q: unexpected error %v", c.in, err)
			}
			if c.wantNil && got != nil {
				t.Errorf("input %q: got %v, want nil", c.in, got)
			}
			if !c.wantNil {
				if got == nil {
					t.Fatalf("input %q: got nil, want a parsed time", c.in)
				}
				if got.Year() != c.year || got.Month() != c.month || got.Day() != c.day {
					t.Errorf("input %q: got %s, want %d-%d-%d",
						c.in, got.Format("2006-01-02"), c.year, c.month, c.day)
				}
			}
		})
	}
}
