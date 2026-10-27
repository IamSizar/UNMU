// Shared pieces for the Pulse (نبض أنمو) admin pages: status badges, the
// "who am I" hook, small formatting helpers, a notice banner, and
// availableActions() which decides which workflow buttons to show.
//
// availableActions() only HIDES buttons the person cannot use anyway. The
// server (backend/internal/pulse/rules.go) is the real authority and checks
// every action again, so a drift here can never let a forbidden action through.

import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { AlertTriangle, CheckCircle2, X } from 'lucide-react'
import { ApiError } from '../../api/client'
import {
  pulseApi,
  type PulseAction,
  type PulseItem,
  type PulseMe,
  type PulseRole,
  type PulseStatus,
} from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'

// UNMU logo teal, deepened so white text on it clears 4.5:1 contrast.
export const PULSE_PRIMARY_BTN =
  'inline-flex items-center justify-center gap-2 h-9 px-4 rounded-lg text-sm font-semibold text-white ' +
  'bg-[#007F86] hover:bg-[#006A70] disabled:opacity-50 disabled:cursor-not-allowed transition-colors'
export const PULSE_GHOST_BTN =
  'inline-flex items-center justify-center gap-2 h-9 px-4 rounded-lg text-sm font-medium text-fg ' +
  'bg-white/5 ring-1 ring-line hover:bg-white/10 disabled:opacity-50 disabled:cursor-not-allowed transition-colors'
export const PULSE_CARD = 'rounded-xl bg-surface ring-1 ring-line'
export const PULSE_INPUT =
  'w-full rounded-lg bg-canvas ring-1 ring-line px-3 py-2 text-sm text-fg placeholder:text-fg-subtle ' +
  'focus:outline-none focus:ring-2 focus:ring-[#00B7B7] disabled:opacity-60'

const STATUS_STYLE: Record<PulseStatus, string> = {
  draft: 'bg-slate-500/15 text-slate-300 ring-slate-500/30',
  in_review: 'bg-amber-500/15 text-amber-300 ring-amber-500/30',
  approved: 'bg-sky-500/15 text-sky-300 ring-sky-500/30',
  scheduled: 'bg-violet-500/15 text-violet-300 ring-violet-500/30',
  published: 'bg-[#00B7B7]/15 text-[#2DD4D4] ring-[#00B7B7]/40',
  archived: 'bg-slate-500/10 text-fg-subtle ring-slate-500/20',
}

/** Coloured pill for an item's workflow status. */
export function StatusBadge({ status }: { status: PulseStatus }) {
  const { t } = useI18n()
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold ring-1 ${STATUS_STYLE[status]}`}
    >
      {t(`pulse.status.${status}` as TranslationKey)}
    </span>
  )
}

/** The "updated" / "corrected" marker shown on a live item. */
export function MarkerBadge({ kind }: { kind: 'updated' | 'corrected' | null }) {
  const { t } = useI18n()
  if (!kind) return null
  return (
    <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold ring-1 bg-amber-500/15 text-amber-300 ring-amber-500/30">
      {t(`pulse.marker.${kind}` as TranslationKey)}
    </span>
  )
}

/** Loads the caller's Pulse roles once. */
export function usePulseMe(): { me: PulseMe | null; loading: boolean; error: string | null } {
  const [me, setMe] = useState<PulseMe | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => {
    let cancelled = false
    pulseApi
      .me()
      .then((m) => !cancelled && setMe(m))
      .catch((e) => !cancelled && setError(e instanceof ApiError ? e.message : 'error'))
      .finally(() => !cancelled && setLoading(false))
    return () => {
      cancelled = true
    }
  }, [])
  return { me, loading, error }
}

export function hasRole(me: PulseMe, role: PulseRole): boolean {
  return me.isAdmin || me.roles.includes(role)
}

/** Workflow buttons this person can use on this item right now. */
export type ItemActionKey = PulseAction | 'correct'

export function availableActions(item: PulseItem, me: PulseMe): ItemActionKey[] {
  const isAuthor = item.createdBy === me.userId
  const editor = hasRole(me, 'editor')
  const reviewer = hasRole(me, 'reviewer')
  const approver = hasRole(me, 'approver')
  switch (item.status) {
    case 'draft':
      return editor ? ['submit'] : []
    case 'in_review': {
      const out: ItemActionKey[] = []
      if (reviewer && !isAuthor) out.push('review')
      if ((reviewer || approver) && !isAuthor) out.push('reject')
      if (approver && !isAuthor) out.push('approve')
      return out
    }
    case 'approved':
      return approver ? ['schedule', 'publish'] : []
    case 'scheduled':
      return approver ? ['unschedule', 'publish'] : []
    case 'published':
      return approver ? ['correct', 'archive'] : []
    default:
      return []
  }
}

export function canEditDraft(item: PulseItem, me: PulseMe): boolean {
  return item.status === 'draft' && hasRole(me, 'editor')
}

/** Formats an ISO timestamp for the viewer's language (digits stay Western). */
export function fmtDateTime(iso: string | null | undefined, locale: string): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString(locale === 'ar' ? 'ar-u-nu-latn' : 'en-GB', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/** ISO timestamp -> value for <input type="datetime-local"> (local time). */
export function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** <input type="datetime-local"> value -> ISO timestamp (or null when empty). */
export function fromLocalInput(value: string): string | null {
  if (!value) return null
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? null : d.toISOString()
}

/** Today as YYYY-MM-DD in the Pulse time zone (UTC+3, no daylight saving). */
export function pulseToday(): string {
  const d = new Date(Date.now() + 3 * 60 * 60 * 1000)
  return d.toISOString().slice(0, 10)
}

/** Title to show in lists: the viewer's language first, else the other one. */
export function itemTitle(item: Pick<PulseItem, 'titleEn' | 'titleAr'>, locale: string): string {
  const first = locale === 'ar' ? item.titleAr : item.titleEn
  const second = locale === 'ar' ? item.titleEn : item.titleAr
  return first || second || '—'
}

// ── Notice banner ─────────────────────────────────────────────────────

export type Notice = { kind: 'ok' | 'error'; text: string } | null

/** A dismissible banner that clears itself after a few seconds. */
export function useNotice(): { notice: Notice; show: (kind: 'ok' | 'error', text: string) => void; clear: () => void } {
  const [notice, setNotice] = useState<Notice>(null)
  const timer = useRef<number | undefined>(undefined)
  const clear = useCallback(() => setNotice(null), [])
  const show = useCallback((kind: 'ok' | 'error', text: string) => {
    window.clearTimeout(timer.current)
    setNotice({ kind, text })
    timer.current = window.setTimeout(() => setNotice(null), kind === 'ok' ? 4000 : 8000)
  }, [])
  useEffect(() => () => window.clearTimeout(timer.current), [])
  return { notice, show, clear }
}

export function NoticeBanner({ notice, onClose }: { notice: Notice; onClose: () => void }) {
  if (!notice) return null
  const ok = notice.kind === 'ok'
  return (
    <div
      role={ok ? 'status' : 'alert'}
      className={`flex items-start gap-3 rounded-lg px-4 py-3 text-sm ring-1 ${
        ok
          ? 'bg-emerald-500/10 ring-emerald-500/30 text-emerald-300'
          : 'bg-rose-500/10 ring-rose-500/30 text-rose-300'
      }`}
    >
      {ok ? (
        <CheckCircle2 className="w-4 h-4 mt-0.5 shrink-0" />
      ) : (
        <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
      )}
      <span className="flex-1">{notice.text}</span>
      <button onClick={onClose} aria-label="Close" className="opacity-70 hover:opacity-100">
        <X className="w-4 h-4" />
      </button>
    </div>
  )
}

/** Loading placeholder rows shaped like the final table. */
export function SkeletonRows({ rows = 5 }: { rows?: number }) {
  return (
    <div className="divide-y divide-line" aria-hidden="true">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="flex items-center gap-4 px-4 py-4 animate-pulse">
          <div className="h-3 w-20 rounded bg-white/10" />
          <div className="h-3 w-16 rounded bg-white/10" />
          <div className="h-3 flex-1 rounded bg-white/10" />
          <div className="h-5 w-20 rounded-full bg-white/10" />
        </div>
      ))}
    </div>
  )
}

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className={`${PULSE_CARD} p-5`}>
      <h2 className="text-xs font-semibold uppercase tracking-wider text-fg-subtle mb-4">{title}</h2>
      {children}
    </section>
  )
}
