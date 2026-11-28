// price_tier.go — the fixed price tiers that expert and community
// subscriptions are sold at. Each tier and plan is one store product,
// created once in App Store Connect (non-renewing subscription) and Play
// Console (consumable one-time product) with these exact ids and prices.
// See docs/payments/IAP_ONLY_PLAN.md.
package models

import "strings"

// Price tiers. Kept in step with the CHECK constraints in migration 0063.
const (
	PriceTier1 = "t1"
	PriceTier2 = "t2"
	PriceTier3 = "t3"
	PriceTier4 = "t4"
)

// DefaultPriceTier is the tier a new expert starts on.
const DefaultPriceTier = PriceTier2

// accessProductPrefix starts every tier product id:
// com.unmu.access.<tier>.<month|year>. Valid on both stores (no hyphens).
const accessProductPrefix = "com.unmu.access."

type tierPrices struct{ monthly, yearly int }

// tierPriceCents is the USD price of each tier, in cents.
var tierPriceCents = map[string]tierPrices{
	PriceTier1: {monthly: 499, yearly: 4999},
	PriceTier2: {monthly: 999, yearly: 9999},
	PriceTier3: {monthly: 1999, yearly: 19999},
	PriceTier4: {monthly: 4999, yearly: 49999},
}

// PriceTiers lists the tiers in order, cheapest first.
var PriceTiers = []string{PriceTier1, PriceTier2, PriceTier3, PriceTier4}

// IsPriceTier reports whether t is a known tier.
func IsPriceTier(t string) bool {
	_, ok := tierPriceCents[t]
	return ok
}

// TierPriceCents returns the USD-cent price of tier for plan, or 0 when
// either is unknown.
func TierPriceCents(tier, plan string) int {
	p, ok := tierPriceCents[tier]
	if !ok {
		return 0
	}
	switch plan {
	case SubPlanMonthly:
		return p.monthly
	case SubPlanYearly:
		return p.yearly
	}
	return 0
}

// AccessProductID returns the store product id for tier and plan, or ""
// when either is unknown.
func AccessProductID(tier, plan string) string {
	if !IsPriceTier(tier) {
		return ""
	}
	switch plan {
	case SubPlanMonthly:
		return accessProductPrefix + tier + ".month"
	case SubPlanYearly:
		return accessProductPrefix + tier + ".year"
	}
	return ""
}

// ParseAccessProductID returns the tier and plan inside a tier product id.
// ok is false for any other product.
func ParseAccessProductID(productID string) (tier, plan string, ok bool) {
	rest, found := strings.CutPrefix(productID, accessProductPrefix)
	if !found {
		return "", "", false
	}
	tier, period, found := strings.Cut(rest, ".")
	if !found || !IsPriceTier(tier) {
		return "", "", false
	}
	switch period {
	case "month":
		return tier, SubPlanMonthly, true
	case "year":
		return tier, SubPlanYearly, true
	}
	return "", "", false
}
