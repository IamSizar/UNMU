// The correction waiting for a second person (decision 2026-10-22: a correction
// to a live Pulse item is never applied by the person who wrote it).
//
// Shows the open proposal for one item — what it would change and why — and,
// for an approver other than the proposer, buttons to apply or reject it. The
// proposer sees a calm note that someone else must apply it. Renders nothing
// when no proposal is open.

import { useCallback, useEffect, useState } from 'react'
import { ApiError } from '../../api/client'
import {
  pulseApi,
  type PulseItem,
  type PulseMe,
  type PulsePendingCorrection,
} from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import { PULSE_CARD, PULSE_GHOST_BTN, PULSE_INPUT, PULSE_PRIMARY_BTN, fmtDateTime, hasRole } from './pulseUi'

/** The text fields shown in the "proposed changes" list (the rest are rarely edited). */
const SHOWN_FIELDS = ['titleAr', 'titleEn', 'summaryAr', 'summaryEn', 'sourceName'] as const

interface Props {
  item: PulseItem
  me: PulseMe
  /** Bump to reload the proposal (after the editor sends a new one). */
  refreshKey: number
  /** Called with the live item after a proposal was applied or rejected. */
  onResolved: (item: PulseItem, applied: boolean) => void
  onError: (message: string) => void
}

export default function PendingCorrectionCard({ item, me, refreshKey, onResolved, onError }: Props) {
  const { t, locale } = useI18n()
  const [pending, setPending] = useState<PulsePendingCorrection | null>(null)
  const [note, setNote] = useState('')
  const [rejecting, setRejecting] = useState(false)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await pulseApi.getCorrection(item.id)
      setPending(res.pending)
    } catch {
      // A failed look-up must not block editing; the editor still works.
      setPending(null)
    }
  }, [item.id])

  useEffect(() => {
    void load()
  }, [load, refreshKey])

  if (!pending || item.status !== 'published') return null

  const isProposer = pending.proposedBy === me.userId
  const canResolve = hasRole(me, 'approver') && !isProposer
  const changed = SHOWN_FIELDS.filter((f) => pending.input[f] !== item[f])

  async function resolve(approve: boolean) {
    if (!approve && note.trim() === '') return // the field shows the "required" hint
    setBusy(true)
    try {
      const live = await pulseApi.resolveCorrection(item.id, approve, note.trim())
      setPending(null)
      setNote('')
      setRejecting(false)
      onResolved(live, approve)
    } catch (e) {
      onError(e instanceof ApiError ? e.message : t('pulse.action.failed'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className={`${PULSE_CARD} p-5 space-y-3`} role="region" aria-label={t('pulse.correction.title')}>
      <div>
        <h2 className="text-base font-semibold text-fg">{t('pulse.correction.title')}</h2>
        <p className="text-xs text-fg-subtle">
          {t(pending.kind === 'corrected' ? 'pulse.dialog.kindCorrected' : 'pulse.dialog.kindUpdated')} ·{' '}
          {fmtDateTime(pending.createdAt, locale)}
        </p>
      </div>
      <p className="text-sm text-fg italic break-words">“{pending.note}”</p>

      <div>
        <h3 className="text-sm font-semibold text-fg mb-1">{t('pulse.correction.changes')}</h3>
        {changed.length === 0 ? (
          <p className="text-sm text-fg-muted">{t('pulse.correction.noVisibleChanges')}</p>
        ) : (
          <ul className="space-y-2">
            {changed.map((f) => (
              <li key={f} className="text-sm">
                <span className="text-xs text-fg-subtle block">
                  {t(`pulse.correction.field.${f}` as TranslationKey)}
                </span>
                <span className="text-fg-subtle line-through break-words block">{item[f] || '—'}</span>
                <span className="text-fg break-words block">{pending.input[f] || '—'}</span>
              </li>
            ))}
          </ul>
        )}
      </div>

      {isProposer && <p className="text-sm text-fg-muted">{t('pulse.correction.yours')}</p>}
      {!isProposer && !canResolve && (
        <p className="text-sm text-fg-muted">{t('pulse.correction.needsApprover')}</p>
      )}

      {canResolve && (
        <div className="space-y-2">
          <label className="block">
            <span className="text-xs text-fg-subtle">
              {rejecting ? t('pulse.correction.rejectNote') : t('pulse.correction.noteOptional')}
            </span>
            <textarea
              rows={2}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              className={PULSE_INPUT}
              aria-invalid={rejecting && note.trim() === ''}
            />
            {rejecting && note.trim() === '' && (
              <span role="alert" className="block mt-1 text-xs text-rose-400">
                {t('pulse.dialog.noteRequired')}
              </span>
            )}
          </label>
          <div className="flex gap-2">
            <button onClick={() => resolve(true)} disabled={busy} className={PULSE_PRIMARY_BTN}>
              {busy ? t('pulse.saving') : t('pulse.correction.approve')}
            </button>
            <button
              onClick={() => (rejecting ? resolve(false) : setRejecting(true))}
              disabled={busy}
              className={PULSE_GHOST_BTN}
            >
              {t('pulse.correction.reject')}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
