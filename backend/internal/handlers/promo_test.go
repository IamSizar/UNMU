package handlers

import (
	"halalstocks/internal/models"
	"testing"
	"time"
)

// discountedCents is the money math behind a promo code: given a base price
// (in cents) and a validated code, it returns the amount the member actually
// pays — i.e. the discounted price that gets stored on the subscription and
// shown to the admin. This test pins that math down because it's
// revenue-critical: a wrong number here means a member is over- or
// under-charged for the exact discount the admin configured on the code.
func TestDiscountedCents(t *testing.T) {
	pct := func(v float64) *models.PromoCode {
		return &models.PromoCode{DiscountType: "PERCENTAGE", DiscountValue: v}
	}
	fixed := func(v float64) *models.PromoCode {
		return &models.PromoCode{DiscountType: "FIXED", DiscountValue: v}
	}

	cases := []struct {
		name  string
		price int
		promo *models.PromoCode
		want  int
	}{
		// PERCENTAGE: value is a % off the base.
		{"25% off $10.00", 1000, pct(25), 750},
		{"50% off $96.00", 9600, pct(50), 4800},
		{"100% off → free", 1000, pct(100), 0},
		{"0% off → unchanged", 1000, pct(0), 1000},
		{"10% off rounds toward member (floor of off)", 999, pct(10), 900}, // off=int(99.9)=99 → 900

		// FIXED: value is a whole-currency amount off (dollars → cents).
		{"$3 off $10.00", 1000, fixed(3), 700},
		{"$10 off $10.00 → free", 1000, fixed(10), 0},
		{"$15 off $10.00 clamps at 0 (never negative)", 1000, fixed(15), 0},
		{"$2.50 off $10.00", 1000, fixed(2.50), 750},

		// Guards.
		{"nil promo → unchanged", 1000, nil, 1000},
		{"zero price → unchanged", 0, pct(25), 0},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := discountedCents(c.price, c.promo)
			if got != c.want {
				t.Errorf("discountedCents(%d, %+v) = %d, want %d", c.price, c.promo, got, c.want)
			}
		})
	}
}

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
