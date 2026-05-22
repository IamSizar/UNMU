import { useEffect, useState } from 'react'
import {
  CheckCircle2, XCircle, AlertTriangle, Info, X,
  LogIn, UserPlus, FileSignature, ShieldCheck, ShieldX,
  ArrowLeftRight, FileText, EyeOff, CreditCard, Activity,
  Users as UsersIcon,
  LifeBuoy,
} from 'lucide-react'
import { useRealtime } from '../api/realtime'
import { play } from '../api/sounds'
import { useI18n } from '../i18n/I18nContext'

type Severity = 'info' | 'success' | 'warning' | 'error'

type Toast = {
  id: number
  type: string
  severity: Severity
  // Title is resolved at render time from `type` via the i18n table
  // (`toaster.<TYPE>`), falling back to the raw type for unknown events.
  body?: string
  href?: string
}

// Raw event types that carry a friendly (translated) title. We piggy-back on
// the `audit_log_created` event since EVERY important state change writes one
// audit row (per migration 0005), so listening to one channel covers all
// of: applications, role flips, posts, logins, etc. The title text itself
// lives in the i18n table under `toaster.<TYPE>` and is resolved at render.
const KNOWN_TOAST_TYPES = new Set<string>([
  'AUTH_LOGIN',
  'AUTH_REGISTER',
  'AUTH_LOGOUT',
  'EXPERT_APP_SUBMITTED',
  'EXPERT_APP_APPROVED',
  'EXPERT_APP_REJECTED',
  'USER_ROLE_CHANGED',
  'POST_CREATED',
  'POST_HIDDEN',
  'SUBSCRIPTION_CHANGED',
  'COMMUNITY_PROPOSAL_SUBMITTED',
  'SUPPORT_MESSAGE_SENT',
])

const TYPE_TO_ICON: Record<string, any> = {
  AUTH_LOGIN: LogIn,
  AUTH_REGISTER: UserPlus,
  EXPERT_APP_SUBMITTED: FileSignature,
  EXPERT_APP_APPROVED: ShieldCheck,
  EXPERT_APP_REJECTED: ShieldX,
  USER_ROLE_CHANGED: ArrowLeftRight,
  POST_CREATED: FileText,
  POST_HIDDEN: EyeOff,
  SUBSCRIPTION_CHANGED: CreditCard,
  COMMUNITY_PROPOSAL_SUBMITTED: UsersIcon,
  SUPPORT_MESSAGE_SENT: LifeBuoy,
}

const SEV_FALLBACK: Record<Severity, any> = {
  info: Info,
  success: CheckCircle2,
  warning: AlertTriangle,
  error: XCircle,
}

const SEV_STYLES: Record<Severity, { bar: string; ring: string; text: string }> = {
  info:    { bar: 'bg-cyan-400',    ring: 'ring-cyan-500/30',    text: 'text-cyan-300' },
  success: { bar: 'bg-emerald-400', ring: 'ring-emerald-500/30', text: 'text-emerald-300' },
  warning: { bar: 'bg-amber-400',   ring: 'ring-amber-500/30',   text: 'text-amber-300' },
  error:   { bar: 'bg-rose-400',    ring: 'ring-rose-500/30',    text: 'text-rose-300' },
}

export default function Toaster() {
  const { t } = useI18n()
  const [toasts, setToasts] = useState<Toast[]>([])

  useRealtime(['audit_log_created'], (ev) => {
    const data = ev.data as any
    if (!data?.id) return
    const severity: Severity = data.severity ?? 'info'
    const type: string = data.type ?? 'EVENT'
    const body: string | undefined = data.summary

    setToasts((curr) => [
      { id: data.id as number, type, severity, body },
      ...curr.slice(0, 4), // keep at most 5 stacked
    ])
    play(severity)

    // Auto-dismiss after 5s
    setTimeout(() => {
      setToasts((curr) => curr.filter((t) => t.id !== data.id))
    }, 5000)
  })

  // Mig 0029 — support chat. Direct messages from users; admin needs
  // an immediate heads-up so a user isn't kept waiting. Only USER
  // messages should pop a toast — admin replies typed from another
  // dashboard tab would otherwise re-toast their own message back.
  useRealtime(['support_message_sent'], (ev) => {
    const d = (ev as { data: Record<string, unknown> }).data
    if ((d.senderRole as string) !== 'user') return
    const threadId = Number(d.threadId ?? 0)
    if (!threadId) return
    const snippet = String(d.body ?? '').slice(0, 100)
    // Stable id range distinct from audit + proposal toasts so dedupe
    // doesn't collide across event families.
    const id = 9_500_000_000 + Number(d.messageId ?? 0)
    setToasts((curr) => [
      {
        id,
        type: 'SUPPORT_MESSAGE_SENT',
        severity: 'info',
        body: snippet,
        href: `/support/${threadId}`,
      },
      ...curr.filter((t) => t.id !== id).slice(0, 4),
    ])
    play('info')
    setTimeout(() => {
      setToasts((curr) => curr.filter((t) => t.id !== id))
    }, 7000)
  })

  // Community proposals don't write an audit row on submit (only on
  // approve/reject), so they wouldn't reach the audit_log_created listener
  // above. We subscribe directly to `community_proposal_submitted` here
  // and synthesize a toast with the proposer's name + community name —
  // info the backend ships in the event payload (see
  // `handlers/community_proposals.go:Submit`).
  useRealtime(['community_proposal_submitted'], (ev) => {
    const d = ev.data as any
    if (!d?.proposalId) return
    const proposer = (d.proposerName as string) ||
      (d.proposerEmail as string) ||
      t('toaster.someone')
    const communityName = (d.name as string) || t('toaster.aNewCommunity')
    // Synthesize a stable id from proposalId so duplicate events (e.g.
    // backend re-broadcasts after a hub reconnect) don't stack the same
    // toast twice. Offset to avoid colliding with audit_log ids.
    const id = 9_000_000_000 + Number(d.proposalId)
    setToasts((curr) => [
      {
        id,
        type: 'COMMUNITY_PROPOSAL_SUBMITTED',
        severity: 'info',
        body: t('toaster.proposalBody', { proposer, community: communityName }),
        href: '/community-proposals',
      },
      ...curr.filter((t) => t.id !== id).slice(0, 4),
    ])
    play('info')
    setTimeout(() => {
      setToasts((curr) => curr.filter((t) => t.id !== id))
    }, 6000)
  })

  if (toasts.length === 0) return null

  return (
    <div className="fixed top-20 end-3 sm:end-6 start-3 sm:start-auto z-50 flex flex-col gap-2 pointer-events-none">
      {toasts.map((t) => (
        <ToastCard
          key={t.id}
          toast={t}
          onDismiss={() => setToasts((c) => c.filter((x) => x.id !== t.id))}
        />
      ))}
    </div>
  )
}

function ToastCard({ toast, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  const { t } = useI18n()
  const Icon = TYPE_TO_ICON[toast.type] ?? SEV_FALLBACK[toast.severity] ?? Activity
  const sev = SEV_STYLES[toast.severity]
  // Title text is resolved from the event type; unknown types fall back
  // to the raw server-sent type string (not translated).
  const title = KNOWN_TOAST_TYPES.has(toast.type)
    ? t(`toaster.${toast.type}` as Parameters<typeof t>[0])
    : toast.type

  // When the toast carries an `href` (e.g. community proposals), clicking
  // the body navigates there + dismisses. We use plain location to avoid
  // pulling react-router into this component just for this one link.
  const isLink = !!toast.href
  const handleBodyClick = isLink
    ? () => {
        window.location.assign(toast.href!)
        onDismiss()
      }
    : undefined

  return (
    <div
      className={`pointer-events-auto w-full sm:w-80 sm:max-w-sm bg-midnight-500/95 backdrop-blur-md rounded-xl border border-white/10 shadow-2xl ring-1 ${sev.ring} overflow-hidden animate-slide-in`}
      style={{
        animation: 'slide-in-right 0.25s ease-out',
      }}
    >
      <div className="flex">
        <div className={`w-1 ${sev.bar}`} />
        <div
          className={`flex-1 p-3 flex items-start gap-3 ${
            isLink ? 'cursor-pointer hover:bg-white/[0.03]' : ''
          }`}
          onClick={handleBodyClick}
          role={isLink ? 'button' : undefined}
          tabIndex={isLink ? 0 : undefined}
        >
          <div className={`mt-0.5 ${sev.text}`}>
            <Icon className="w-5 h-5" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-white">{title}</p>
            {toast.body && (
              <p className="text-xs text-slate-400 mt-0.5 line-clamp-2">{toast.body}</p>
            )}
            {isLink && (
              <p className={`text-[11px] mt-1 font-bold ${sev.text}`}>
                {t('toaster.review')}
              </p>
            )}
          </div>
          <button
            onClick={(e) => {
              e.stopPropagation()
              onDismiss()
            }}
            className="p-1 rounded-md hover:bg-white/10 text-slate-500 hover:text-white -me-1 -mt-1"
            aria-label={t('toaster.dismiss')}
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  )
}
