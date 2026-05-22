/**
 * PendingEventsPanel — the right-side feed on the /network page.
 *
 * Renders the `pending` array from /api/admin/network/graph and lets
 * the admin approve/reject in place. Optimistic UI: the card animates
 * out the moment you click, and a rollback toast appears if the
 * backend rejects.
 *
 * Four event kinds we surface here:
 *   - expert_application      → POST /admin/expert-applications/:id/approve|reject
 *   - subscription            → POST /admin/subscriptions/:id/approve|reject
 *   - community_subscription  → POST /admin/community-subscriptions/:id/approve|reject
 *   - community_proposal      → POST /admin/community-proposals/:id/approve|reject
 *
 * Each route already exists; we just call them. On approve we set the
 * card to `state="approved"` (green flash 600ms then fade out). On
 * reject we set `state="rejected"` (red flash). Errors fall back to
 * `state="pending"` + a toast.
 */

import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Check, X, Loader2, Sparkles, CreditCard, Users2, Lightbulb } from 'lucide-react'
import { api } from '../api/client'
import { DUR, EASE } from '../ui/motion'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'
import type { Locale } from '../i18n/translations'

export type PendingEvent = {
  kind:
    | 'expert_application'
    | 'subscription'
    | 'community_subscription'
    | 'community_proposal'
  id: number
  headline: string
  subText?: string
  createdAt: string
  actorUserId?: number
  targetUserId?: number
}

type State = 'idle' | 'approving' | 'rejecting' | 'approved' | 'rejected'

export default function PendingEventsPanel({
  events,
  onAction,
  onHoverActor,
}: {
  events: PendingEvent[]
  /** Called after a successful approve/reject so the parent can
   *  remove the resolved row from the graph (and bump counters). */
  onAction?: (e: PendingEvent, result: 'approved' | 'rejected') => void
  /** Highlights the actor's graph node while their event is hovered. */
  onHoverActor?: (userId: number | null) => void
}) {
  const { t } = useI18n()
  return (
    <div className="card-v2 h-full flex flex-col">
      <div className="p-4 border-b border-hairline flex items-center justify-between">
        <div>
          <h3 className="h3-v2 flex items-center gap-2">
            {t('pendingEvents.title')}
            {events.length > 0 && (
              <span className="px-1.5 h-[18px] inline-flex items-center rounded-sm bg-brand-gold/15 text-brand-gold text-[10px] font-mono font-bold ring-1 ring-inset ring-brand-gold/30">
                {events.length}
              </span>
            )}
          </h3>
          <p className="text-xs text-fg-subtle mt-0.5">
            {t('pendingEvents.subtitle')}
          </p>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-3 space-y-2">
        {events.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center py-12">
            <div className="w-10 h-10 rounded-full bg-ok/15 ring-1 ring-ok/30 flex items-center justify-center mb-3">
              <Check className="w-5 h-5 text-ok" />
            </div>
            <p className="text-sm font-semibold text-fg">{t('pendingEvents.allCaughtUp')}</p>
            <p className="text-xs text-fg-subtle mt-1">
              {t('pendingEvents.noItems')}
            </p>
          </div>
        ) : (
          <AnimatePresence initial={false}>
            {events.map((ev) => (
              <EventCard
                key={`${ev.kind}-${ev.id}`}
                event={ev}
                onAction={onAction}
                onHoverActor={onHoverActor}
              />
            ))}
          </AnimatePresence>
        )}
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// EventCard — one row.
// ────────────────────────────────────────────────────────────────────
function EventCard({
  event,
  onAction,
  onHoverActor,
}: {
  event: PendingEvent
  onAction?: (e: PendingEvent, result: 'approved' | 'rejected') => void
  onHoverActor?: (userId: number | null) => void
}) {
  const { t, locale } = useI18n()
  const [state, setState] = useState<State>('idle')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  const meta = META[event.kind]
  const kindLabel = t(KIND_LABEL_KEY[event.kind] as Parameters<typeof t>[0])

  async function doAction(action: 'approve' | 'reject') {
    if (state !== 'idle') return
    setState(action === 'approve' ? 'approving' : 'rejecting')
    setErrorMsg(null)

    try {
      await api.post(meta.endpoint(event.id, action), {})
      setState(action === 'approve' ? 'approved' : 'rejected')
      // Give the user a 700ms green/red flash before bubbling the
      // event up — the parent will remove the row when it re-fetches.
      setTimeout(() => {
        onAction?.(event, action === 'approve' ? 'approved' : 'rejected')
      }, 700)
    } catch (e: any) {
      setState('idle')
      setErrorMsg(e?.message ?? t('pendingEvents.failed'))
    }
  }

  // Color the card edge by state.
  const borderClass =
    state === 'approved'
      ? 'border-ok/40 bg-ok/[0.08]'
      : state === 'rejected'
      ? 'border-err/40 bg-err/[0.08]'
      : 'border-hairline hover:border-line'

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 8, scale: 0.96 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, scale: 0.92, x: 40 }}
      transition={{ duration: DUR.small, ease: EASE }}
      onMouseEnter={() => event.actorUserId && onHoverActor?.(event.actorUserId)}
      onMouseLeave={() => onHoverActor?.(null)}
      className={`relative rounded-lg border ${borderClass} p-3 transition-colors duration-micro ease-out-expo`}
    >
      <div className="flex items-start gap-2.5">
        <div
          className={`w-7 h-7 rounded-md flex items-center justify-center shrink-0 ${meta.iconClass}`}
        >
          <meta.icon className="w-3.5 h-3.5" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-[10px] font-bold tracking-[0.08em] uppercase text-fg-subtle">
            {kindLabel}
          </p>
          <p className="text-sm font-semibold text-fg mt-0.5 truncate">
            {event.headline}
          </p>
          {event.subText && (
            <p className="text-xs text-fg-muted mt-0.5 line-clamp-1">
              {event.subText}
            </p>
          )}
          <p className="text-[10px] text-fg-subtle font-mono mt-1.5">
            {relativeTime(new Date(event.createdAt), locale)}
          </p>
        </div>
      </div>

      {/* Actions */}
      {state === 'idle' && (
        <div className="flex items-center gap-1.5 mt-2.5">
          <button
            onClick={() => doAction('approve')}
            className="flex-1 h-7 rounded-md bg-ok/15 hover:bg-ok/25 ring-1 ring-inset ring-ok/30 text-ok text-xs font-bold flex items-center justify-center gap-1 transition-colors duration-micro ease-out-expo"
          >
            <Check className="w-3.5 h-3.5" />
            {t('pendingEvents.approve')}
          </button>
          <button
            onClick={() => doAction('reject')}
            className="flex-1 h-7 rounded-md bg-err/12 hover:bg-err/20 ring-1 ring-inset ring-err/30 text-err text-xs font-bold flex items-center justify-center gap-1 transition-colors duration-micro ease-out-expo"
          >
            <X className="w-3.5 h-3.5" />
            {t('pendingEvents.reject')}
          </button>
        </div>
      )}

      {(state === 'approving' || state === 'rejecting') && (
        <div className="flex items-center justify-center gap-2 mt-2.5 h-7 text-xs text-fg-muted">
          <Loader2 className="w-3.5 h-3.5 animate-spin" />
          {state === 'approving' ? t('pendingEvents.approving') : t('pendingEvents.rejecting')}
        </div>
      )}

      {state === 'approved' && (
        <div className="flex items-center justify-center gap-1.5 mt-2.5 h-7 text-xs font-bold text-ok">
          <Check className="w-3.5 h-3.5" /> {t('pendingEvents.approved')}
        </div>
      )}
      {state === 'rejected' && (
        <div className="flex items-center justify-center gap-1.5 mt-2.5 h-7 text-xs font-bold text-err">
          <X className="w-3.5 h-3.5" /> {t('pendingEvents.rejected')}
        </div>
      )}

      {errorMsg && (
        <p className="text-[10px] text-err mt-1.5 font-mono">{errorMsg}</p>
      )}
    </motion.div>
  )
}

// ── Per-kind icon + endpoint mapping ────────────────────────────────
//
// NOTE on verbs — the backend uses two conventions:
//   * expert_application + community_proposal  → /approve  /reject
//   * expert_subscription + community_subscription → /accept /reject
//
// The UI says "Approve" uniformly (admin-friendly word) but the wire
// call has to pick the right verb per resource. Map both via the
// `endpoint` callback below.
const META: Record<
  PendingEvent['kind'],
  {
    label: string
    icon: React.ComponentType<{ className?: string }>
    iconClass: string
    endpoint: (id: number, action: 'approve' | 'reject') => string
  }
> = {
  expert_application: {
    label: 'Expert application',
    icon: Sparkles,
    iconClass:
      'bg-brand-gold/15 text-brand-gold ring-1 ring-inset ring-brand-gold/30',
    endpoint: (id, action) =>
      `/admin/expert-applications/${id}/${action}`,
  },
  subscription: {
    label: 'Subscription',
    icon: CreditCard,
    iconClass:
      'bg-brand-cyan/15 text-brand-cyan ring-1 ring-inset ring-brand-cyan/30',
    // Expert-subscription uses `/accept`, not `/approve`. Mapping
    // happens here so the UI button can still say "Approve".
    endpoint: (id, action) =>
      `/admin/subscriptions/${id}/${action === 'approve' ? 'accept' : 'reject'}`,
  },
  community_subscription: {
    label: 'Community subscription',
    icon: Users2,
    iconClass:
      'bg-info/15 text-info ring-1 ring-inset ring-info/30',
    // Same `/accept` convention as expert subscriptions.
    endpoint: (id, action) =>
      `/admin/community-subscriptions/${id}/${
        action === 'approve' ? 'accept' : 'reject'
      }`,
  },
  community_proposal: {
    label: 'Community proposal',
    icon: Lightbulb,
    iconClass: 'bg-warn/15 text-warn ring-1 ring-inset ring-warn/30',
    endpoint: (id, action) =>
      `/admin/community-proposals/${id}/${action}`,
  },
}

// Per-kind label translation keys (in the `pendingEvents.` namespace).
// The `label` strings on META above are retained as developer-facing
// fallbacks; the UI renders these translated labels instead.
const KIND_LABEL_KEY: Record<PendingEvent['kind'], string> = {
  expert_application: 'pendingEvents.kindExpertApplication',
  subscription: 'pendingEvents.kindSubscription',
  community_subscription: 'pendingEvents.kindCommunitySubscription',
  community_proposal: 'pendingEvents.kindCommunityProposal',
}

function relativeTime(date: Date, locale: Locale) {
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 7) return `${days}d ago`
  return fmtDate(date, locale)
}
