/**
 * PricingModal — admin picks the price tier for one expert.
 *
 * Opens from the Experts page when the admin clicks "Edit pricing"
 * on a card. Subscriptions are sold only through the App Store /
 * Google Play, so the admin chooses one of the fixed tiers
 * (see ../api/priceTiers) instead of typing amounts.
 *
 * Calls PATCH /api/admin/experts/:expertId/pricing with {priceTier}.
 * The backend sets the cents for the tier and writes an
 * EXPERT_PRICING_UPDATED audit row for the audit-log feed.
 */

import { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { X, Loader2, Check } from 'lucide-react'
import { api } from '../api/client'
import {
  PRICE_TIERS,
  formatTierLabel,
  isPriceTier,
  type PriceTier,
} from '../api/priceTiers'
import { DUR, EASE } from '../ui/motion'
import { useI18n } from '../i18n/I18nContext'

export type PricingExpert = {
  id: string
  name: string
  monthlyPriceCents: number
  yearlyPriceCents: number
  priceCurrency: string
  priceTier: string
}

type Props = {
  expert: PricingExpert | null
  onClose: () => void
  /** Called with the updated record after the backend confirms. */
  onSaved?: (updated: PricingExpert) => void
}

export default function PricingModal({ expert, onClose, onSaved }: Props) {
  const { t } = useI18n()
  // Selected tier; null only if the expert row carries an unknown tier.
  const [tier, setTier] = useState<PriceTier | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Preselect the expert's current tier whenever a new expert is selected.
  useEffect(() => {
    if (!expert) return
    setTier(isPriceTier(expert.priceTier) ? expert.priceTier : null)
    setError(null)
  }, [expert])

  // Close on Escape.
  useEffect(() => {
    if (!expert) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [expert, onClose])

  async function save() {
    if (!expert || !tier) return
    setSaving(true)
    setError(null)
    try {
      const res = await api.patch<{ ok: boolean; expert: PricingExpert }>(
        `/admin/experts/${expert.id}/pricing`,
        { priceTier: tier },
      )
      onSaved?.(res.expert)
      onClose()
    } catch (e: any) {
      setError(e?.message ?? t('pricing.errFailed'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <AnimatePresence>
      {expert && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: DUR.small, ease: EASE }}
            onClick={onClose}
            className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm"
          />

          {/* Dialog */}
          <motion.div
            initial={{ opacity: 0, scale: 0.96, y: 12 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96, y: 12 }}
            transition={{ duration: DUR.small, ease: EASE }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4 pointer-events-none"
          >
            <div className="pointer-events-auto w-full max-w-md bg-elevated ring-1 ring-line rounded-xl shadow-xl">
              {/* Header */}
              <div className="flex items-start justify-between p-5 border-b border-hairline">
                <div className="min-w-0">
                  <p className="eyebrow-v2">{t('pricing.eyebrow')}</p>
                  <h3 className="h2-v2 mt-1 truncate">{expert.name}</h3>
                  <p className="text-xs text-fg-muted mt-0.5 font-mono">
                    {expert.id}
                  </p>
                </div>
                <button
                  onClick={onClose}
                  className="p-1.5 rounded-md hover:bg-hairline text-fg-subtle hover:text-fg shrink-0"
                  aria-label={t('pricing.close')}
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              {/* Body */}
              <div className="p-5 space-y-4">
                <div>
                  <p className="block text-xs font-bold tracking-wide uppercase text-fg-subtle mb-1.5">
                    {t('pricing.tierLabel')}
                  </p>
                  <div role="radiogroup" className="space-y-2">
                    {PRICE_TIERS.map((option) => {
                      const selected = option.id === tier
                      return (
                        <button
                          key={option.id}
                          type="button"
                          role="radio"
                          aria-checked={selected}
                          disabled={saving}
                          onClick={() => setTier(option.id)}
                          className={`w-full flex items-center justify-between gap-3 px-3 py-2 rounded-md ring-1 text-sm font-mono tabular-nums ${
                            selected
                              ? 'ring-brand-cyan bg-brand-cyan/10 text-fg'
                              : 'ring-line text-fg-muted hover:bg-hairline'
                          }`}
                        >
                          <span>{formatTierLabel(option)}</span>
                          {selected && <Check className="w-4 h-4 text-brand-cyan shrink-0" />}
                        </button>
                      )
                    })}
                  </div>
                </div>

                {error && (
                  <div className="rounded-md bg-err/10 ring-1 ring-err/30 px-3 py-2 text-err text-xs">
                    {error}
                  </div>
                )}

                <p className="text-xs text-fg-subtle">
                  {t('pricing.tierNote')}
                </p>
              </div>

              {/* Footer */}
              <div className="flex items-center justify-end gap-2 p-4 border-t border-hairline">
                <button
                  onClick={onClose}
                  disabled={saving}
                  className="btn-v2-ghost"
                >
                  {t('common.cancel')}
                </button>
                <button
                  onClick={save}
                  disabled={saving || !tier}
                  className="btn-v2-primary"
                >
                  {saving ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      {t('pricing.saving')}
                    </>
                  ) : (
                    <>
                      <Check className="w-4 h-4" />
                      {t('pricing.save')}
                    </>
                  )}
                </button>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
