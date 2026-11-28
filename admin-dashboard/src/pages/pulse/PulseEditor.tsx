// Create / view / edit one Pulse item.
//
//   /pulse/items/new   a blank draft
//   /pulse/items/:id   an existing item: editable while it is a draft, read-only
//                      afterwards, with "update or correct" for live items.
//
// The page owns the data (load, save, workflow actions). The form, the workflow
// panel and the history are separate components. Server messages for single
// fields are shown next to the field; everything else goes to the banner.

import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { AlertTriangle, ArrowLeft, Loader2, Trash2 } from 'lucide-react'
import { ApiError } from '../../api/client'
import {
  pulseApi,
  type PulseAction,
  type PulseItem,
  type PulseItemInput,
  type PulseStock,
} from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import PendingCorrectionCard from './PendingCorrectionCard'
import PulseHistory from './PulseHistory'
import { notifyPulseChanged } from './pulseEvents'
import PulseItemForm from './PulseItemForm'
import PulseWorkflow from './PulseWorkflow'
import { emptyInput, isDirty, toInput, validateClient, type FormErrors } from './pulseForm'
import {
  MarkerBadge,
  NoticeBanner,
  PULSE_CARD,
  PULSE_GHOST_BTN,
  PULSE_INPUT,
  PULSE_PRIMARY_BTN,
  Section,
  StatusBadge,
  canEditDraft,
  hasRole,
  itemTitle,
  pulseToday,
  useNotice,
  usePulseMe,
} from './pulseUi'

export default function PulseEditor() {
  const { t, locale } = useI18n()
  const navigate = useNavigate()
  const params = useParams()
  const isNew = params.id === 'new'
  const itemId = isNew ? null : Number(params.id)

  const { me, loading: meLoading } = usePulseMe()
  const { notice, show, clear } = useNotice()

  const [item, setItem] = useState<PulseItem | null>(null)
  const [draft, setDraft] = useState<PulseItemInput>(() => emptyInput(pulseToday()))
  const [saved, setSaved] = useState<PulseItemInput>(() => emptyInput(pulseToday()))
  const [stock, setStock] = useState<PulseStock | null>(null)
  const [loading, setLoading] = useState(!isNew)
  const [loadError, setLoadError] = useState<'missing' | 'failed' | null>(null)
  const [serverErrors, setServerErrors] = useState<FormErrors>({})
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [historyKey, setHistoryKey] = useState(0)
  const [correctionKey, setCorrectionKey] = useState(0)

  // "Update or correct" mode for live items.
  const [correcting, setCorrecting] = useState(false)
  const [kind, setKind] = useState<'updated' | 'corrected'>('corrected')
  const [note, setNote] = useState('')
  const [noteTouched, setNoteTouched] = useState(false)

  // ── Load ───────────────────────────────────────────────────────────
  const load = useCallback(async () => {
    if (itemId === null) return
    setLoading(true)
    setLoadError(null)
    try {
      const it = await pulseApi.get(itemId)
      setItem(it)
      setDraft(toInput(it))
      setSaved(toInput(it))
      setStock(it.stock)
    } catch (e) {
      setLoadError(e instanceof ApiError && e.status === 404 ? 'missing' : 'failed')
    } finally {
      setLoading(false)
    }
  }, [itemId])

  useEffect(() => {
    if (isNew) {
      const blank = emptyInput(pulseToday())
      setItem(null)
      setDraft(blank)
      setSaved(blank)
      setStock(null)
      setLoading(false)
      setLoadError(null)
      return
    }
    load()
  }, [isNew, load])

  const dirty = isDirty(draft, saved)

  // Warn before closing the tab with unsaved edits.
  useEffect(() => {
    if (!dirty) return
    const h = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', h)
    return () => window.removeEventListener('beforeunload', h)
  }, [dirty])

  // ── Permissions ────────────────────────────────────────────────────
  const canCreate = me ? hasRole(me, 'editor') : false
  const editableDraft = isNew ? canCreate : Boolean(item && me && canEditDraft(item, me))
  const formDisabled = correcting ? false : !editableDraft

  function reportError(e: unknown, fallback: string) {
    if (e instanceof ApiError) {
      if (e.fields) setServerErrors(e.fields)
      show('error', e.fields ? t('pulse.fixFields') : e.message || fallback)
    } else {
      show('error', fallback)
    }
  }

  // ── Save / delete ──────────────────────────────────────────────────
  async function save() {
    const errs = validateClient(draft)
    if (Object.keys(errs).length > 0) {
      show('error', t('pulse.fixFields'))
      return
    }
    setSaving(true)
    setServerErrors({})
    try {
      if (isNew) {
        const created = await pulseApi.create(draft)
        show('ok', t('pulse.saved'))
        navigate(`/pulse/items/${created.id}`, { replace: true })
      } else if (itemId !== null) {
        const updated = await pulseApi.update(itemId, draft)
        setItem(updated)
        setSaved(toInput(updated))
        setStock(updated.stock)
        setHistoryKey((k) => k + 1)
        show('ok', t('pulse.saved'))
      }
      notifyPulseChanged()
    } catch (e) {
      reportError(e, t('pulse.saveFailed'))
    } finally {
      setSaving(false)
    }
  }

  async function remove() {
    if (itemId === null || !window.confirm(t('pulse.deleteConfirm'))) return
    setSaving(true)
    try {
      await pulseApi.remove(itemId)
      notifyPulseChanged()
      navigate('/pulse', { replace: true })
    } catch (e) {
      reportError(e, t('pulse.action.failed'))
      setSaving(false)
    }
  }

  // ── Workflow ───────────────────────────────────────────────────────
  async function runAction(action: PulseAction, body: { note?: string; publishAt?: string }) {
    if (itemId === null) return
    // Unsaved edits would be lost by the status change; save them first.
    if (dirty && editableDraft) {
      show('error', t('pulse.unsaved'))
      return
    }
    setBusy(true)
    setServerErrors({})
    try {
      const updated = await pulseApi.action(itemId, action, body)
      setItem(updated)
      setDraft(toInput(updated))
      setSaved(toInput(updated))
      setStock(updated.stock)
      setHistoryKey((k) => k + 1)
      show('ok', t('pulse.action.done'))
      notifyPulseChanged()
    } catch (e) {
      reportError(e, t('pulse.action.failed'))
    } finally {
      setBusy(false)
    }
  }

  async function confirmCorrection() {
    setNoteTouched(true)
    if (itemId === null || note.trim() === '') return
    const errs = validateClient(draft)
    if (Object.keys(errs).length > 0) {
      show('error', t('pulse.fixFields'))
      return
    }
    setBusy(true)
    setServerErrors({})
    try {
      // Only PROPOSES: the live item is unchanged until a different approver applies it.
      await pulseApi.correct(itemId, { kind, note: note.trim(), item: draft })
      if (item) setDraft(toInput(item))
      setCorrecting(false)
      setNote('')
      setNoteTouched(false)
      setCorrectionKey((k) => k + 1)
      setHistoryKey((k) => k + 1)
      show('ok', t('pulse.correction.proposed'))
      notifyPulseChanged()
    } catch (e) {
      reportError(e, t('pulse.action.failed'))
    } finally {
      setBusy(false)
    }
  }

  /** A pending correction was applied (item changed) or rejected (unchanged). */
  function correctionResolved(live: PulseItem, applied: boolean) {
    setItem(live)
    setDraft(toInput(live))
    setSaved(toInput(live))
    setStock(live.stock)
    setHistoryKey((k) => k + 1)
    show('ok', t(applied ? 'pulse.correction.applied' : 'pulse.correction.rejected'))
    notifyPulseChanged()
  }

  function cancelCorrection() {
    setCorrecting(false)
    setNote('')
    setNoteTouched(false)
    setServerErrors({})
    if (item) setDraft(toInput(item))
  }

  // ── Render ─────────────────────────────────────────────────────────
  if (meLoading || loading) {
    return (
      <div className="max-w-6xl mx-auto flex items-center justify-center py-24 text-fg-subtle">
        <Loader2 className="w-6 h-6 animate-spin" aria-label={t('pulse.loading')} />
      </div>
    )
  }
  if (loadError) {
    return (
      <div className="max-w-xl mx-auto py-20 text-center space-y-3">
        <AlertTriangle className="w-8 h-8 text-rose-400 mx-auto" />
        <p className="text-sm text-fg-muted">
          {loadError === 'missing' ? t('pulse.editor.notFound') : t('pulse.error.load')}
        </p>
        <div className="flex justify-center gap-2">
          {loadError === 'failed' && (
            <button onClick={load} className={PULSE_GHOST_BTN}>
              {t('pulse.retry')}
            </button>
          )}
          <Link to="/pulse" className={PULSE_GHOST_BTN}>
            {t('pulse.editor.back')}
          </Link>
        </div>
      </div>
    )
  }
  if (isNew && !canCreate) {
    return <p className="max-w-xl mx-auto py-20 text-center text-sm text-fg-muted">{t('pulse.noAccess')}</p>
  }

  const heading = isNew ? t('pulse.editor.newTitle') : item ? itemTitle(item, locale) : t('pulse.editor.editTitle')

  return (
    <div className="max-w-6xl mx-auto space-y-5">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <Link to="/pulse" className="inline-flex items-center gap-1.5 text-sm text-fg-muted hover:text-fg">
          <ArrowLeft className="w-4 h-4 rtl:rotate-180" />
          {t('pulse.editor.back')}
        </Link>
      </div>

      <div className="flex items-center gap-3 flex-wrap">
        <h1 className="text-2xl font-semibold text-fg min-w-0 break-words">{heading}</h1>
        {item && <StatusBadge status={item.status} />}
        {item && <MarkerBadge kind={item.changeKind} />}
      </div>

      <NoticeBanner notice={notice} onClose={clear} />

      {item && me && (
        <div className={`${PULSE_CARD} p-5`}>
          <PulseWorkflow
            item={item}
            me={me}
            busy={busy}
            onAction={runAction}
            onCorrect={() => {
              setCorrecting(true)
              setServerErrors({})
            }}
          />
        </div>
      )}

      {item && me && item.status === 'published' && (
        <PendingCorrectionCard
          item={item}
          me={me}
          refreshKey={correctionKey}
          onResolved={correctionResolved}
          onError={(m) => show('error', m)}
        />
      )}

      {item && !editableDraft && !correcting && (
        <p className="text-sm text-fg-muted bg-white/5 ring-1 ring-line rounded-lg px-4 py-3">
          {t('pulse.editor.readOnly', { status: t(`pulse.status.${item.status}` as TranslationKey) })}
        </p>
      )}

      {correcting && (
        <div className="rounded-xl bg-amber-500/10 ring-1 ring-amber-500/30 p-5 space-y-4">
          <div>
            <h2 className="text-base font-semibold text-fg">{t('pulse.dialog.correctTitle')}</h2>
            <p className="text-sm text-fg-muted">{t('pulse.dialog.correctHint')}</p>
          </div>
          <fieldset className="space-y-2">
            <legend className="text-sm font-medium text-fg mb-1">{t('pulse.dialog.kind')}</legend>
            {(['corrected', 'updated'] as const).map((k) => (
              <label key={k} className="flex items-center gap-2 text-sm text-fg">
                <input
                  type="radio"
                  name="kind"
                  checked={kind === k}
                  onChange={() => setKind(k)}
                  className="accent-[#00B7B7]"
                />
                {k === 'corrected' ? t('pulse.dialog.kindCorrected') : t('pulse.dialog.kindUpdated')}
              </label>
            ))}
          </fieldset>
          <label className="block">
            <span className="block text-[11px] font-semibold uppercase tracking-wider text-fg-subtle mb-1.5">
              {t('pulse.dialog.noteRequired')}
            </span>
            <textarea
              rows={2}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder={t('pulse.dialog.notePlaceholder')}
              className={PULSE_INPUT}
            />
            {noteTouched && note.trim() === '' && (
              <span role="alert" className="block mt-1 text-xs text-rose-400">
                {t('pulse.dialog.noteRequired')}
              </span>
            )}
          </label>
          <div className="flex gap-2">
            <button onClick={confirmCorrection} disabled={busy} className={PULSE_PRIMARY_BTN}>
              {busy ? t('pulse.saving') : t('pulse.dialog.confirmPropose')}
            </button>
            <button onClick={cancelCorrection} disabled={busy} className={PULSE_GHOST_BTN}>
              {t('pulse.dialog.cancel')}
            </button>
          </div>
        </div>
      )}

      <Section title={t('pulse.editor.editTitle')}>
        {editableDraft && <p className="text-xs text-fg-subtle mb-4">{t('pulse.hint.requiredForReview')}</p>}
        <PulseItemForm
          value={draft}
          onChange={setDraft}
          stock={stock}
          onStockChange={setStock}
          disabled={formDisabled}
          lockDateSlot={correcting}
          serverErrors={serverErrors}
        />

        {editableDraft && (
          <div className="flex items-center gap-3 mt-6 pt-5 border-t border-line flex-wrap">
            <button onClick={save} disabled={saving || (!isNew && !dirty)} className={PULSE_PRIMARY_BTN}>
              {saving ? t('pulse.saving') : isNew ? t('pulse.create') : t('pulse.save')}
            </button>
            {dirty && !isNew && <span className="text-xs text-amber-300">{t('pulse.unsaved')}</span>}
            {!isNew && (
              <button onClick={remove} disabled={saving} className={`${PULSE_GHOST_BTN} ms-auto !text-rose-300`}>
                <Trash2 className="w-4 h-4" />
                {t('pulse.delete')}
              </button>
            )}
          </div>
        )}
      </Section>

      {item && (
        <Section title={t('pulse.history.title')}>
          <PulseHistory itemId={item.id} refreshKey={historyKey} />
        </Section>
      )}
    </div>
  )
}
