// price_tier.go — community and expert prices are a fixed tier, because
// each tier is one store product (internal/models/price_tier.go).
package handlers

import "halalstocks/internal/models"

// tierPricing is a community update's resolved price fields.
type tierPricing struct {
	Tier            *string // nil = unchanged; "" = free
	Monthly, Yearly *int
	Currency        *string
}

// communityTierPricing resolves a community update's prices from its
// priceTier: "" = free, "t1".."t4" = that tier's USD prices. Raw prices
// without a tier are refused (old clients), as is an unknown tier. The
// second return is a user-facing message, "" when valid.
func communityTierPricing(tier *string, monthly, yearly *int) (tierPricing, string) {
	if tier == nil {
		if monthly != nil || yearly != nil {
			return tierPricing{}, "Prices are set by tier: send priceTier (t1–t4, or empty for free). Please update the app."
		}
		return tierPricing{}, ""
	}
	t := *tier
	if t != "" && !models.IsPriceTier(t) {
		return tierPricing{}, "priceTier must be t1, t2, t3, t4 or empty for free"
	}
	m := models.TierPriceCents(t, models.SubPlanMonthly)
	y := models.TierPriceCents(t, models.SubPlanYearly)
	usd := "usd"
	return tierPricing{Tier: &t, Monthly: &m, Yearly: &y, Currency: &usd}, ""
}
