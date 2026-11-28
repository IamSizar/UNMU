// The workflow panel of a Pulse item: the status stepper, the buttons this
// person may use right now, and the confirmation dialog for actions that need
// a note or a time (reject, schedule) or deserve a second look (publish...).

import { useEffect, useRef, useState } from 'react'
import { Check } from 'lucide-react'
import type { PulseAction, PulseItem, PulseMe, PulseStatus } from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import {
  PULSE_GHOST_BTN,
  PULSE_INPUT,
  PULSE_PRIMARY_BTN,
  availableActions,
  fromLocalInput,
  type ItemActionKey,
} from './pulseUi'

const STEPS: PulseStatus[] = ['draft', 'in_review', 'approved', 'scheduled', 'published']

/** draft → in review → approved → (scheduled) → published. */
export function StatusStepper({ status }: { status: PulseStatus }) {
  const { t } = useI18n()
  const archived = status === 'archived'
  const current = archived ? STEPS.length : STEPS.indexOf(status)
  return (
    <ol className="flex items-center gap-2 flex-wrap" aria-label={t('pulse.workflow.title')}>
      {STEPS.map((s, i) => {
        const done = i < current
        const now = i === current
        return (
          <li key={s} className="flex items-center gap-2">
            <span
              aria-current={now ? 'step' : undefined}
              className={`w-6 h-6 rounded-full grid place-items-center text-[11px] font-semibold ring-1 ${
                done
                  ? 'bg-[#007F86] text-white ring-transparent'
                  : now
                    ? 'bg-white text-[#005A60] ring-2 ring-[#00B7B7]'
                    : 'bg-white/5 text-fg-subtle ring-line'
              }`}
            >
              {done ? <Check className="w-3.5 h-3.5" /> : i + 1}
            </span>
            <span className={`text-xs font-medium ${now ? 'text-fg' : done ? 'text-fg-muted' : 'text-fg-subtle'}`}>
              {t(`pulse.status.${s}` as TranslationKey)}
            </span>
            {i < STEPS.length - 1 && <span className="w-5 h-px bg-line" aria-hidden="true" />}
          </li>
        )
      })}
      {archived && (
        <li className="text-xs font-medium text-fg-subtle ms-2">{t('pulse.status.archived')}</li>
      )}
    </ol>
  )
}

// Actions that run immediately, without a dialog.
const DIRECT: PulseAction[] = ['submit', 'unschedule']
// Actions that need the dialog to collect a note.
const NOTE_REQUIRED: PulseAction[] = ['reject']

interface Props {
  item: PulseItem
  me: PulseMe
  busy: boolean
  onAction: (action: PulseAction, body: { note?: string; publishAt?: string }) => Promise<void>
  /** Opens the editor in "update or correct" mode. */
  onCorrect: () => void
}

export default function PulseWorkflow({ item, me, busy, onAction, onCorrect }: Props) {
  const { t } = useI18n()
  const [dialog, setDialog] = useState<PulseAction | null>(null)
  const actions = availableActions(item, me)
  const isAuthor = item.createdBy === me.userId

  function click(a: ItemActionKey) {
    if (a === 'correct') return onCorrect()
    if (DIRECT.includes(a)) return void onAction(a, {})
    setDialog(a)
  }

  return (
    <div className="space-y-4">
      <StatusStepper status={item.status} />

      {item.status === 'in_review' && isAuthor && (
        <p className="text-xs text-amber-300 bg-amber-500/10 ring-1 ring-amber-500/30 rounded-lg px-3 py-2">
          {t('pulse.editor.fourEyes')}
        </p>
      )}

      {actions.length === 0 ? (
        <p className="text-sm text-fg-subtle">{t('pulse.workflow.none')}</p>
      ) : (
        <div className="flex flex-wrap gap-2">
          {actions.map((a) => (
            <button
              key={a}
              disabled={busy}
              onClick={() => click(a)}
              className={a === 'approve' || a === 'publish' || a === 'submit' ? PULSE_PRIMARY_BTN : PULSE_GHOST_BTN}
            >
              {t(`pulse.action.${a}` as TranslationKey)}
            </button>
          ))}
        </div>
      )}

      {dialog && (
        <ActionDialog
          action={dialog}
          busy={busy}
          onCancel={() => setDialog(null)}
          onConfirm={async (body) => {
            await onAction(dialog, body)
            setDialog(null)
          }}
        />
      )}
    </div>
  )
}

function ActionDialog({
  action,
  busy,
  onCancel,
  onConfirm,
}: {
  action: PulseAction
  busy: boolean
  onCancel: () => void
  onConfirm: (body: { note?: string; publishAt?: string }) => Promise<void>
}) {
  const { t } = useI18n()
  const [note, setNote] = useState('')
  const [publishAt, setPublishAt] = useState('')
  const [touched, setTouched] = useState(false)
  const firstField = useRef<HTMLTextAreaElement | HTMLInputElement | null>(null)

  const needsNote = NOTE_REQUIRED.includes(action)
  const needsTime = action === 'schedule'
  const publishIso = fromLocalInput(publishAt)
  const timeInvalid = needsTime && (!publishIso || new Date(publishIso).getTime() <= Date.now())
  const noteInvalid = needsNote && note.trim() === ''
  const invalid = timeInvalid || noteInvalid

  // Focus the first field and close on Escape, like a native dialog.
  useEffect(() => {
    firstField.current?.focus()
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && !busy && onCancel()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [busy, onCancel])

  const title =
    action === 'reject'
      ? t('pulse.dialog.rejectTitle')
      : action === 'schedule'
        ? t('pulse.dialog.scheduleTitle')
        : t(`pulse.action.${action}` as TranslationKey)

  async function submit() {
    setTouched(true)
    if (invalid) return
    await onConfirm({
      note: note.trim() || undefined,
      publishAt: needsTime && publishIso ? publishIso : undefined,
    })
  }

  return (
    <div
      className="fixed inset-0 z-50 grid place-items-center bg-black/60 p-4"
      onMouseDown={(e) => e.target === e.currentTarget && !busy && onCancel()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="w-full max-w-md rounded-2xl bg-surface ring-1 ring-line p-5 space-y-4"
      >
        <h3 className="text-lg font-semibold text-fg">{title}</h3>

        {needsTime && (
          <label className="block">
            <span className="block text-[11px] font-semibold uppercase tracking-wider text-fg-subtle mb-1.5">
              {t('pulse.dialog.publishAt')}
            </span>
            <input
              ref={(el) => {
                firstField.current = el
              }}
              type="datetime-local"
              value={publishAt}
              onChange={(e) => setPublishAt(e.target.value)}
              className={PULSE_INPUT}
            />
            <span className="block mt-1 text-xs text-fg-subtle">{t('pulse.dialog.scheduleHint')}</span>
            {touched && timeInvalid && (
              <span role="alert" className="block mt-1 text-xs text-rose-400">
                {t('pulse.dialog.publishAt')}
              </span>
            )}
          </label>
        )}

        {!needsTime && (
          <label className="block">
            <span className="block text-[11px] font-semibold uppercase tracking-wider text-fg-subtle mb-1.5">
              {needsNote ? t('pulse.dialog.noteRequired') : t('pulse.dialog.note')}
            </span>
            <textarea
              ref={(el) => {
                firstField.current = el
              }}
              rows={3}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder={t('pulse.dialog.notePlaceholder')}
              className={PULSE_INPUT}
            />
            {touched && noteInvalid && (
              <span role="alert" className="block mt-1 text-xs text-rose-400">
                {t('pulse.dialog.noteRequired')}
              </span>
            )}
          </label>
        )}

        <div className="flex justify-end gap-2">
          <button onClick={onCancel} disabled={busy} className={PULSE_GHOST_BTN}>
            {t('pulse.dialog.cancel')}
          </button>
          <button onClick={submit} disabled={busy} className={PULSE_PRIMARY_BTN}>
            {busy ? t('pulse.saving') : t('pulse.dialog.confirm')}
          </button>
        </div>
      </div>
    </div>
  )
}
