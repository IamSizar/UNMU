// The Pulse item form: classification, slot, bilingual title/summary/details/
// evidence, source, verification time, and the linked-stock picker.
//
// It is a controlled component. Validation messages come from two places:
//   * instant client checks (pulseForm.validateClient), translated here;
//   * the server's per-field messages (serverErrors) after a failed save.

import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Search, X } from 'lucide-react'
import {
  PULSE_SLOTS,
  pulseApi,
  type PulseClassification,
  type PulseItemInput,
  type PulseStock,
} from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import { LIMITS, validateClient, type FormErrors } from './pulseForm'
import { PULSE_GHOST_BTN, PULSE_INPUT, fromLocalInput, toLocalInput } from './pulseUi'

interface Props {
  value: PulseItemInput
  onChange: (next: PulseItemInput) => void
  stock: PulseStock | null
  onStockChange: (stock: PulseStock | null) => void
  disabled: boolean
  /** Corrections cannot move an item to another day or slot. */
  lockDateSlot?: boolean
  serverErrors: FormErrors
}

const CLIENT_ERROR_KEY: Record<string, TranslationKey> = {
  date: 'pulse.hint.date',
  url: 'pulse.hint.url',
  future: 'pulse.hint.verifiedFuture',
}

function Field({
  label,
  error,
  count,
  children,
}: {
  label: string
  error?: string
  count?: { n: number; max: number }
  children: ReactNode
}) {
  return (
    <label className="block">
      <span className="flex items-center justify-between text-[11px] font-semibold uppercase tracking-wider text-fg-subtle mb-1.5">
        <span>{label}</span>
        {count && count.n > count.max * 0.8 && (
          <span className={count.n > count.max ? 'text-rose-400' : ''}>
            {count.n}/{count.max}
          </span>
        )}
      </span>
      {children}
      {error && (
        <span role="alert" className="block mt-1 text-xs text-rose-400">
          {error}
        </span>
      )}
    </label>
  )
}

export default function PulseItemForm({
  value,
  onChange,
  stock,
  onStockChange,
  disabled,
  lockDateSlot,
  serverErrors,
}: Props) {
  const { t } = useI18n()
  const clientErrors = validateClient(value)

  function set<K extends keyof PulseItemInput>(key: K, v: PulseItemInput[K]) {
    const next = { ...value, [key]: v }
    if (key === 'slot' && v === 'sharia') next.isSensitive = true
    onChange(next)
  }
  // Server message wins; otherwise show the translated instant check.
  function err(field: string): string | undefined {
    if (serverErrors[field]) return serverErrors[field]
    const key = clientErrors[field]
    return key ? t(CLIENT_ERROR_KEY[key]) : undefined
  }

  const isSharia = value.slot === 'sharia'
  const locked = disabled
  const dateSlotLocked = locked || lockDateSlot

  return (
    <div className="space-y-6">
      {/* ── What and when ───────────────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Field label={t('pulse.field.date')} error={err('pulseDate')}>
          <input
            type="date"
            value={value.pulseDate}
            disabled={dateSlotLocked}
            onChange={(e) => set('pulseDate', e.target.value)}
            className={PULSE_INPUT}
          />
        </Field>
        <Field label={t('pulse.field.slot')} error={err('slot')}>
          <select
            value={value.slot}
            disabled={dateSlotLocked}
            onChange={(e) => set('slot', e.target.value as PulseItemInput['slot'])}
            className={PULSE_INPUT}
          >
            {PULSE_SLOTS.map((s) => (
              <option key={s} value={s}>
                {t(`pulse.slot.${s}` as TranslationKey)}
              </option>
            ))}
          </select>
        </Field>
        <Field label={t('pulse.field.classification')} error={err('classification')}>
          <select
            value={value.classification}
            disabled={locked}
            onChange={(e) => set('classification', e.target.value as PulseClassification)}
            className={PULSE_INPUT}
          >
            <option value="confirmed">{t('pulse.class.confirmed')}</option>
            <option value="analysis">{t('pulse.class.analysis')}</option>
          </select>
        </Field>
      </div>

      <label className="flex items-start gap-3 text-sm text-fg">
        <input
          type="checkbox"
          checked={value.isSensitive || isSharia}
          disabled={locked || isSharia || lockDateSlot}
          onChange={(e) => set('isSensitive', e.target.checked)}
          className="mt-0.5 h-4 w-4 rounded accent-[#00B7B7]"
        />
        <span>
          <span className="font-medium">{t('pulse.field.sensitive')}</span>
          <span className="block text-xs text-fg-subtle">
            {isSharia ? t('pulse.field.sensitiveAuto') : t('pulse.editor.sensitiveNote')}
          </span>
        </span>
      </label>

      {/* ── Bilingual content ───────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Field label={t('pulse.field.titleEn')} error={err('titleEn')} count={{ n: value.titleEn.length, max: LIMITS.title }}>
          <input
            value={value.titleEn}
            disabled={locked}
            maxLength={LIMITS.title + 50}
            onChange={(e) => set('titleEn', e.target.value)}
            className={PULSE_INPUT}
            dir="ltr"
            lang="en"
          />
        </Field>
        <Field label={t('pulse.field.titleAr')} error={err('titleAr')} count={{ n: value.titleAr.length, max: LIMITS.title }}>
          <input
            value={value.titleAr}
            disabled={locked}
            maxLength={LIMITS.title + 50}
            onChange={(e) => set('titleAr', e.target.value)}
            className={PULSE_INPUT}
            dir="rtl"
            lang="ar"
          />
        </Field>
        <Field label={t('pulse.field.summaryEn')} error={err('summaryEn')} count={{ n: value.summaryEn.length, max: LIMITS.summary }}>
          <textarea
            value={value.summaryEn}
            disabled={locked}
            rows={3}
            onChange={(e) => set('summaryEn', e.target.value)}
            className={PULSE_INPUT}
            dir="ltr"
            lang="en"
          />
        </Field>
        <Field label={t('pulse.field.summaryAr')} error={err('summaryAr')} count={{ n: value.summaryAr.length, max: LIMITS.summary }}>
          <textarea
            value={value.summaryAr}
            disabled={locked}
            rows={3}
            onChange={(e) => set('summaryAr', e.target.value)}
            className={PULSE_INPUT}
            dir="rtl"
            lang="ar"
          />
        </Field>
        <Field label={t('pulse.field.detailsEn')} error={err('detailsEn')}>
          <textarea
            value={value.detailsEn}
            disabled={locked}
            rows={6}
            onChange={(e) => set('detailsEn', e.target.value)}
            className={PULSE_INPUT}
            dir="ltr"
            lang="en"
          />
        </Field>
        <Field label={t('pulse.field.detailsAr')} error={err('detailsAr')}>
          <textarea
            value={value.detailsAr}
            disabled={locked}
            rows={6}
            onChange={(e) => set('detailsAr', e.target.value)}
            className={PULSE_INPUT}
            dir="rtl"
            lang="ar"
          />
        </Field>
        <Field label={t('pulse.field.evidenceEn')} error={err('evidenceEn')}>
          <textarea
            value={value.evidenceEn}
            disabled={locked}
            rows={3}
            onChange={(e) => set('evidenceEn', e.target.value)}
            className={PULSE_INPUT}
            dir="ltr"
            lang="en"
          />
        </Field>
        <Field label={t('pulse.field.evidenceAr')} error={err('evidenceAr')}>
          <textarea
            value={value.evidenceAr}
            disabled={locked}
            rows={3}
            onChange={(e) => set('evidenceAr', e.target.value)}
            className={PULSE_INPUT}
            dir="rtl"
            lang="ar"
          />
        </Field>
      </div>

      {/* ── Source and verification ─────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Field label={t('pulse.field.sourceName')} error={err('sourceName')}>
          <input
            value={value.sourceName}
            disabled={locked}
            maxLength={LIMITS.source + 50}
            onChange={(e) => set('sourceName', e.target.value)}
            className={PULSE_INPUT}
          />
        </Field>
        <Field label={t('pulse.field.sourceUrl')} error={err('sourceUrl')}>
          <input
            type="url"
            inputMode="url"
            autoComplete="off"
            placeholder="https://"
            value={value.sourceUrl}
            disabled={locked}
            onChange={(e) => set('sourceUrl', e.target.value)}
            className={PULSE_INPUT}
            dir="ltr"
          />
        </Field>
        <Field label={t('pulse.field.verifiedAt')} error={err('verifiedAt')}>
          <input
            type="datetime-local"
            value={toLocalInput(value.verifiedAt)}
            disabled={locked}
            onChange={(e) => set('verifiedAt', fromLocalInput(e.target.value))}
            className={PULSE_INPUT}
          />
        </Field>
      </div>

      <StockPicker
        stock={stock}
        disabled={locked}
        error={err('stockId')}
        onChange={(s) => {
          onStockChange(s)
          onChange({ ...value, stockId: s ? s.id : null })
        }}
      />
    </div>
  )
}

/** Search-as-you-type picker for the stock an item is linked to. */
function StockPicker({
  stock,
  onChange,
  disabled,
  error,
}: {
  stock: PulseStock | null
  onChange: (s: PulseStock | null) => void
  disabled: boolean
  error?: string
}) {
  const { t } = useI18n()
  const [q, setQ] = useState('')
  const [results, setResults] = useState<PulseStock[] | null>(null)
  const [searching, setSearching] = useState(false)
  const seq = useRef(0) // ignore out-of-order responses

  useEffect(() => {
    const text = q.trim()
    if (text.length < 2) {
      setResults(null)
      return
    }
    const mine = ++seq.current
    setSearching(true)
    const timer = window.setTimeout(() => {
      pulseApi
        .stocks(text)
        .then((r) => mine === seq.current && setResults(r.stocks))
        .catch(() => mine === seq.current && setResults([]))
        .finally(() => mine === seq.current && setSearching(false))
    }, 300)
    return () => window.clearTimeout(timer)
  }, [q])

  return (
    <div>
      <span className="block text-[11px] font-semibold uppercase tracking-wider text-fg-subtle mb-1.5">
        {t('pulse.field.stock')}
      </span>
      {stock ? (
        <div className="flex items-center gap-3 rounded-lg ring-1 ring-line bg-canvas px-3 py-2">
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-fg truncate" dir="ltr">
              {stock.ticker} · {stock.exchange}
            </p>
            <p className="text-xs text-fg-subtle truncate">{stock.name}</p>
          </div>
          {!disabled && (
            <button
              type="button"
              onClick={() => onChange(null)}
              className={`${PULSE_GHOST_BTN} !h-8 !px-3`}
              aria-label={t('pulse.field.stockClear')}
            >
              <X className="w-4 h-4" />
              {t('pulse.field.stockClear')}
            </button>
          )}
        </div>
      ) : disabled ? (
        <p className="text-sm text-fg-subtle">{t('pulse.field.stockNone')}</p>
      ) : (
        <div className="relative">
          <Search className="w-4 h-4 absolute start-3 top-1/2 -translate-y-1/2 text-fg-subtle pointer-events-none" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('pulse.field.stockSearch')}
            autoComplete="off"
            className={`${PULSE_INPUT} ps-9`}
          />
          {q.trim().length >= 2 && (
            <ul className="absolute z-10 mt-1 w-full max-h-56 overflow-auto rounded-lg bg-surface ring-1 ring-line shadow-lg">
              {searching && results === null && (
                <li className="px-3 py-2 text-sm text-fg-subtle">{t('pulse.loading')}</li>
              )}
              {results && results.length === 0 && (
                <li className="px-3 py-2 text-sm text-fg-subtle">{t('pulse.field.stockNoResults')}</li>
              )}
              {results?.map((s) => (
                <li key={s.id}>
                  <button
                    type="button"
                    onClick={() => {
                      onChange(s)
                      setQ('')
                      setResults(null)
                    }}
                    className="w-full text-start px-3 py-2 hover:bg-white/10"
                  >
                    <span className="text-sm font-medium text-fg" dir="ltr">
                      {s.ticker} · {s.exchange}
                    </span>
                    <span className="block text-xs text-fg-subtle">{s.name}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
      {error && (
        <span role="alert" className="block mt-1 text-xs text-rose-400">
          {error}
        </span>
      )}
    </div>
  )
}
