/**
 * PricingModal — admin edits monthly + yearly price for one expert.
 *
 * Opens from the Experts page when the admin clicks "Edit pricing"
 * on a card. Two number inputs (USD), live preview of the saved
 * format, save button, cancel button.
 *
 * Calls PATCH /api/admin/experts/:expertId/pricing with cents. The
 * backend writes an EXPERT_PRICING_UPDATED audit row with before/
 * after metadata for the audit-log feed.
 *
 * Validation:
 *   - monthly $0 .. $1,000   (cents 0 .. 100,000)
 *   - yearly  $0 .. $10,000  (cents 0 .. 1,000,000)
 * Negative values rejected. Empty fields treated as 0.
 */

import { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { X, Loader2, Check } from 'lucide-react'
import { api } from '../api/client'
import { DUR, EASE } from '../ui/motion'
import { useI18n } from '../i18n/I18nContext'

export type PricingExpert = {
  id: string
  name: string
  monthlyPriceCents: number
  yearlyPriceCents: number
  priceCurrency: string
}

type Props = {
  expert: PricingExpert | null
  onClose: () => void
  /** Called with the updated record after the backend confirms. */
  onSaved?: (updated: PricingExpert) => void
}

export default function PricingModal({ expert, onClose, onSaved }: Props) {
  const { t } = useI18n()
  // Local state for the inputs — strings so empty / partial values
  // (during typing) don't snap to 0.
  const [monthly, setMonthly] = useState('')
  const [yearly, setYearly] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Hydrate inputs whenever a new expert is selected.
  useEffect(() => {
    if (!expert) return
    setMonthly((expert.monthlyPriceCents / 100).toString())
    setYearly((expert.yearlyPriceCents / 100).toString())
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
    if (!expert) return
    const monthlyDollars = parseFloat(monthly) || 0
    const yearlyDollars = parseFloat(yearly) || 0

    if (monthlyDollars < 0 || yearlyDollars < 0) {
      setError(t('pricing.errNonNegative'))
      return
    }
    if (monthlyDollars > 1000) {
      setError(t('pricing.errMonthlyCap'))
      return
    }
    if (yearlyDollars > 10000) {
      setError(t('pricing.errYearlyCap'))
      return
    }

    setSaving(true)
    setError(null)
    try {
      const res = await api.patch<{ ok: boolean; expert: PricingExpert }>(
        `/admin/experts/${expert.id}/pricing`,
        {
          monthlyCents: Math.round(monthlyDollars * 100),
          yearlyCents: Math.round(yearlyDollars * 100),
        },
      )
      onSaved?.(res.expert)
      onClose()
    } catch (e: any) {
      setError(e?.message ?? t('pricing.errFailed'))
    } finally {
      setSaving(false)
    }
  }

  // Suggest a 20% discount on yearly when the admin tweaks monthly.
  // Decoupled by default — only computed for the "Suggest yearly" link.
  function suggestedYearly(): string {
    const m = parseFloat(monthly) || 0
    if (m <= 0) return '0'
    // 12 × monthly × 0.80 → 20% discount versus paying monthly.
    return (m * 12 * 0.8).toFixed(2)
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
                <PriceField
                  label={t('pricing.monthly')}
                  value={monthly}
                  onChange={setMonthly}
                  suffix="/mo"
                  disabled={saving}
                />
                <PriceField
                  label={t('pricing.yearly')}
                  value={yearly}
                  onChange={setYearly}
                  suffix="/yr"
                  disabled={saving}
                  hint={
                    <>
                      {t('pricing.suggested')}{' '}
                      <button
                        type="button"
                        onClick={() => setYearly(suggestedYearly())}
                        className="text-brand-cyan hover:underline font-mono"
                      >
                        ${suggestedYearly()}
                      </button>{' '}
                      <span className="text-fg-subtle">{t('pricing.discountNote')}</span>
                    </>
                  }
                />

                {error && (
                  <div className="rounded-md bg-err/10 ring-1 ring-err/30 px-3 py-2 text-err text-xs">
                    {error}
                  </div>
                )}

                <p className="text-xs text-fg-subtle">
                  {t('pricing.currencyNote')}
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
                  disabled={saving}
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

// ────────────────────────────────────────────────────────────────────
// PriceField — labeled USD input with a $ prefix and an editable suffix.
// ────────────────────────────────────────────────────────────────────
function PriceField({
  label,
  value,
  onChange,
  suffix,
  disabled,
  hint,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  suffix: string
  disabled?: boolean
  hint?: React.ReactNode
}) {
  return (
    <div>
      <label className="block text-xs font-bold tracking-wide uppercase text-fg-subtle mb-1.5">
        {label}
      </label>
      <div className="relative">
        <span className="absolute start-3 top-1/2 -translate-y-1/2 text-fg-muted font-mono text-sm">
          $
        </span>
        <input
          type="text"
          inputMode="decimal"
          value={value}
          disabled={disabled}
          onChange={(e) => onChange(e.target.value)}
          placeholder="0.00"
          className="input-v2 ps-7 pe-12 font-mono tabular-nums"
        />
        <span className="absolute end-3 top-1/2 -translate-y-1/2 text-fg-subtle text-sm font-mono">
          {suffix}
        </span>
      </div>
      {hint && <p className="text-[11px] mt-1.5 text-fg-muted">{hint}</p>}
    </div>
  )
}
