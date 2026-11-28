/**
 * Fixed price tiers shared by expert and community pricing.
 *
 * Subscriptions are sold only through the App Store / Google Play, so
 * prices map to fixed store products instead of free-form amounts. The
 * backend owns the cents for each tier (models/price_tier.go); this
 * list only drives the admin pickers and must stay in sync with it.
 */

export type PriceTier = 't1' | 't2' | 't3' | 't4'

export type PriceTierOption = {
  id: PriceTier
  monthlyCents: number
  yearlyCents: number
}

export const PRICE_TIERS: readonly PriceTierOption[] = [
  { id: 't1', monthlyCents: 499, yearlyCents: 4999 },
  { id: 't2', monthlyCents: 999, yearlyCents: 9999 },
  { id: 't3', monthlyCents: 1999, yearlyCents: 19999 },
  { id: 't4', monthlyCents: 4999, yearlyCents: 49999 },
]

/** True when the value is one of the known tier ids. */
export function isPriceTier(value: unknown): value is PriceTier {
  return PRICE_TIERS.some((tier) => tier.id === value)
}

/** "$4.99/mo · $49.99/yr" for one tier option. */
export function formatTierLabel(tier: PriceTierOption): string {
  const dollars = (cents: number) => `$${(cents / 100).toFixed(2)}`
  return `${dollars(tier.monthlyCents)}/mo · ${dollars(tier.yearlyCents)}/yr`
}
