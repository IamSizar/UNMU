import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  RefreshCw,
  Check,
  X,
  Clock,
  AlertTriangle,
  Users as UsersIcon,
} from 'lucide-react'
import { api } from '../api/client'
import { useRealtime } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate, fmtDateTime } from '../i18n/datefmt'

// Mirrors backend repositories.CommunityProposal — all timestamps
// arrive as ISO strings; reviewed_* fields are nullable when status
// is still pending.
type Proposal = {
  id: number
  userId: number
  userName?: string
  userEmail?: string
  name: string
  regionCode?: string
  description: string
  status: 'pending' | 'approved' | 'rejected'
  rejectionReason?: string
  submittedAt: string
  reviewedAt?: string | null
  reviewedBy?: number | null
  approvedCommunityId?: string
}

type ListResponse = { proposals: Proposal[] }

type StatusFilter = 'pending' | 'approved' | 'rejected' | 'all'

/**
 * CommunityProposals — admin reviews experts' proposals to spin up
 * new communities. On approve, the matching community is created
 * with the proposing expert set as owner; on reject, a reason is
 * required and the expert sees it in their studio.
 */
export default function CommunityProposals() {
  const { t } = useI18n()
  const [status, setStatus] = useState<StatusFilter>('pending')
  const [rows, setRows] = useState<Proposal[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [actionBusy, setActionBusy] = useState<number | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const qs = status === 'all' ? '' : `?status=${status}`
      const res = await api.get<ListResponse>(`/admin/community-proposals${qs}`)
      setRows(res.proposals ?? [])
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  async function approve(p: Proposal) {
    if (
      !confirm(
        t('communityProposals.approveConfirm', {
          name: p.name,
          user: p.userName ?? p.userEmail ?? '',
        }),
      )
    )
      return
    setActionBusy(p.id)
    try {
      await api.post(`/admin/community-proposals/${p.id}/approve`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  async function reject(p: Proposal) {
    const reason = prompt(
      t('communityProposals.rejectPrompt', {
        name: p.name,
        user: p.userName ?? t('communityProposals.theExpert'),
      }),
    )
    if (!reason || reason.trim().length < 3) return
    setActionBusy(p.id)
    try {
      await api.post(`/admin/community-proposals/${p.id}/reject`, {
        reason: reason.trim(),
      })
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status])

  // Realtime — refresh the list the moment an expert submits a new
  // proposal or another admin tab approves / rejects one. Same pattern
  // as the Applications page.
  useRealtime(
    [
      'community_proposal_submitted',
      'community_proposal_approved',
      'community_proposal_rejected',
    ],
    () => load(),
  )

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-white">{t('communityProposals.title')}</h1>
          <p className="text-sm text-slate-400 mt-1">
            {t('communityProposals.subtitle')}
          </p>
        </div>
        <button
          onClick={load}
          disabled={loading}
          className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 ring-1 ring-white/10 disabled:opacity-50"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          {t('common.refresh')}
        </button>
      </div>

      {/* ── Status filter ──────────────────────────────────────── */}
      <div className="flex items-center gap-1 bg-white/5 rounded-lg p-1 ring-1 ring-white/10 w-fit">
        {([
          { v: 'pending' as StatusFilter, label: t('communityProposals.filterPending') },
          { v: 'approved' as StatusFilter, label: t('communityProposals.filterApproved') },
          { v: 'rejected' as StatusFilter, label: t('communityProposals.filterRejected') },
          { v: 'all' as StatusFilter, label: t('communityProposals.filterAll') },
        ]).map(({ v, label }) => (
          <button
            key={v}
            onClick={() => setStatus(v)}
            className={`px-2.5 py-1 rounded-md text-xs font-medium ${
              status === v
                ? 'bg-cyan-500/20 text-cyan-300 ring-1 ring-cyan-500/30'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-4 py-3 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" />
          {error}
        </div>
      )}

      <div className="space-y-3">
        {rows.length === 0 && !loading && (
          <p className="text-slate-500 text-sm text-center py-10">
            {t('communityProposals.empty')}
          </p>
        )}
        {rows.map((p) => (
          <ProposalCard
            key={p.id}
            proposal={p}
            busy={actionBusy === p.id}
            onApprove={() => approve(p)}
            onReject={() => reject(p)}
          />
        ))}
      </div>
      {loading && (
        <p className="text-xs text-slate-500 text-center">{t('common.loading')}</p>
      )}
    </div>
  )
}

function ProposalCard({
  proposal: p,
  busy,
  onApprove,
  onReject,
}: {
  proposal: Proposal
  busy: boolean
  onApprove: () => void
  onReject: () => void
}) {
  const { t, locale } = useI18n()
  const isPending = p.status === 'pending'
  // Step-22 — whole card → /community-proposals/:id detail page.
  const navigate = useNavigate()
  function onCardClick(e: React.MouseEvent) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    navigate(`/community-proposals/${p.id}`)
  }
  return (
    <div
      onClick={onCardClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') navigate(`/community-proposals/${p.id}`)
      }}
      className={`cursor-pointer rounded-xl ring-1 p-4 hover:ring-cyan-500/30 transition-shadow ${
        p.status === 'approved'
          ? 'bg-emerald-500/5 ring-emerald-500/20'
          : p.status === 'rejected'
          ? 'bg-rose-500/5 ring-rose-500/20'
          : 'bg-white/[0.02] ring-white/5'
      }`}
    >
      <div className="flex items-start gap-3">
        <Link
          to={`/users/${p.userId}`}
          className="w-10 h-10 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold shrink-0 hover:bg-cyan-500/25"
        >
          {(p.userName || p.userEmail || '?').charAt(0).toUpperCase()}
        </Link>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <h3 className="text-white font-bold truncate">{p.name}</h3>
                <StatusPill status={p.status} />
                {p.regionCode && (
                  <span className="px-1.5 py-0.5 rounded-md bg-white/5 ring-1 ring-white/10 text-[10px] font-bold text-slate-300">
                    {p.regionCode}
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-500 mt-0.5">
                {t('communityProposals.proposedBy')}{' '}
                <Link to={`/users/${p.userId}`} className="text-cyan-300 hover:text-cyan-200">
                  {p.userName ?? p.userEmail}
                </Link>{' '}
                · {fmtDateTime(p.submittedAt, locale)}
              </p>
            </div>
            {isPending && (
              <div className="flex items-center gap-1 shrink-0" onClick={(e) => e.stopPropagation()}>
                <button
                  onClick={onApprove}
                  disabled={busy}
                  className="flex items-center gap-1 px-2.5 py-1.5 rounded-md text-xs font-bold bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-300 ring-1 ring-emerald-500/30 disabled:opacity-50"
                >
                  <Check className="w-3.5 h-3.5" />
                  {t('communityProposals.approve')}
                </button>
                <button
                  onClick={onReject}
                  disabled={busy}
                  className="flex items-center gap-1 px-2.5 py-1.5 rounded-md text-xs font-bold bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                >
                  <X className="w-3.5 h-3.5" />
                  {t('communityProposals.reject')}
                </button>
              </div>
            )}
          </div>
          <p className="mt-2 text-sm text-slate-300 leading-relaxed">
            {p.description}
          </p>
          {p.status === 'approved' && p.approvedCommunityId && (
            <p className="mt-3 text-xs text-emerald-300 flex items-center gap-1">
              <UsersIcon className="w-3 h-3" />
              {t('communityProposals.createdAs')} <code className="font-mono">{p.approvedCommunityId}</code>
              {p.reviewedAt &&
                t('communityProposals.createdOn', {
                  date: fmtDate(p.reviewedAt, locale),
                })}
            </p>
          )}
          {p.status === 'rejected' && p.rejectionReason && (
            <div className="mt-3 rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2">
              <p className="text-[10px] uppercase tracking-wider font-bold text-rose-300">
                {t('communityProposals.rejectionReason')}
              </p>
              <p className="text-xs text-rose-200 mt-1">{p.rejectionReason}</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function StatusPill({ status }: { status: Proposal['status'] }) {
  const { t } = useI18n()
  const config = {
    pending: { label: t('communityProposals.statusPending'), cls: 'bg-gold-500/15 text-gold-300 ring-gold-500/30', Icon: Clock },
    approved: { label: t('communityProposals.statusApproved'), cls: 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30', Icon: Check },
    rejected: { label: t('communityProposals.statusRejected'), cls: 'bg-rose-500/15 text-rose-300 ring-rose-500/30', Icon: X },
  }[status]
  const Icon = config.Icon
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-bold ring-1 ${config.cls}`}
    >
      <Icon className="w-3 h-3" />
      {config.label}
    </span>
  )
}
