package models

import (
	"testing"
	"time"
)

// These helpers back the IAP charge amount and the active-period
// expiry calculation. A typo in either constant would either
// undercharge users or expire their access early — both painful and
// invisible without a regression test, since the numbers travel
// straight from constants to the StoreKit receipt verification path.

func TestPriceForPlan(t *testing.T) {
	cases := []struct {
		plan string
		want int
	}{
		{SubPlanMonthly, PriceMonthlyCents},
		{SubPlanYearly, PriceYearlyCents},
		{"", 0},
		{"weekly", 0},
		{"MONTHLY", 0}, // case-sensitive — only the constant matches
	}
	for _, c := range cases {
		t.Run("plan="+c.plan, func(t *testing.T) {
			if got := PriceForPlan(c.plan); got != c.want {
				t.Errorf("PriceForPlan(%q) = %d, want %d", c.plan, got, c.want)
			}
		})
	}
}

// Yearly should be cheaper than 12× monthly — that's the whole point
// of the bundle. If a future edit accidentally inverts the discount,
// this test trips before billing notices.
func TestPriceYearly_IsDiscountedVsMonthlyTimes12(t *testing.T) {
	monthlyTimes12 := PriceMonthlyCents * 12
	if PriceYearlyCents >= monthlyTimes12 {
		t.Errorf("PriceYearlyCents (%d) should be < monthly×12 (%d) — yearly bundle must be a discount",
			PriceYearlyCents, monthlyTimes12)
	}
}

func TestDurationForPlan(t *testing.T) {
	cases := []struct {
		plan string
		want time.Duration
	}{
		{SubPlanMonthly, 30 * 24 * time.Hour},
		{SubPlanYearly, 365 * 24 * time.Hour},
		{"", 0},
		{"weekly", 0},
	}
	for _, c := range cases {
		t.Run("plan="+c.plan, func(t *testing.T) {
			if got := DurationForPlan(c.plan); got != c.want {
				t.Errorf("DurationForPlan(%q) = %v, want %v", c.plan, got, c.want)
			}
		})
	}
}

// Yearly duration must be strictly longer than monthly — invariant the
// subscription-expirer relies on when scheduling renewal sweeps.
func TestDurationYearly_GreaterThanMonthly(t *testing.T) {
	m := DurationForPlan(SubPlanMonthly)
	y := DurationForPlan(SubPlanYearly)
	if !(y > m) {
		t.Errorf("yearly duration (%v) must exceed monthly (%v)", y, m)
	}
}
