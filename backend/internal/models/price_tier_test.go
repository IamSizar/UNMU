package models

import "testing"

func TestAccessProductIDRoundTrip(t *testing.T) {
	for _, tier := range PriceTiers {
		for _, plan := range []string{SubPlanMonthly, SubPlanYearly} {
			id := AccessProductID(tier, plan)
			gotTier, gotPlan, ok := ParseAccessProductID(id)
			if !ok || gotTier != tier || gotPlan != plan {
				t.Fatalf("%s: got %q %q %v", id, gotTier, gotPlan, ok)
			}
		}
	}
	if AccessProductID(PriceTier1, SubPlanMonthly) != "com.unmu.access.t1.month" {
		t.Fatal("unexpected product id format")
	}
}

func TestParseAccessProductIDRejects(t *testing.T) {
	for _, id := range []string{
		"", "com.unmu.access.t9.month", "com.unmu.access.t1.week",
		"com.unmu.access.t1", "com.unmu.expert.abc.monthly", "com.unmu.premium.monthly",
	} {
		if _, _, ok := ParseAccessProductID(id); ok {
			t.Fatalf("%q should not parse", id)
		}
	}
}

func TestTierPriceCents(t *testing.T) {
	if TierPriceCents(PriceTier2, SubPlanMonthly) != 999 || TierPriceCents(PriceTier4, SubPlanYearly) != 49999 {
		t.Fatal("wrong tier price")
	}
	if TierPriceCents("t9", SubPlanMonthly) != 0 || TierPriceCents(PriceTier1, "weekly") != 0 {
		t.Fatal("unknown tier or plan must be 0")
	}
}
