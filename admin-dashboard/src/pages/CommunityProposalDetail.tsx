import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  RefreshCw,
  Check,
  X,
  Calendar,
  AlertOctagon,
  AlertTriangle,
  Users as UsersIcon,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

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

const STATUS_TINT: Record<string, string> = {
  pending: 'bg-gold-500/15 text-gold-300 ring-gold-500/30',
  approved: 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30',
  rejected: 'bg-rose-500/15 text-rose-300 ring-rose-500/30',
}

/**
 * CommunityProposalDetail — `/community-proposals/:id`.
 *
 * Drill-in from the Community Proposals list. Shows the full proposal
 * (long description, region, proposer info), and exposes Approve /
 * Reject with a textarea for the rejection reason. On approve, the
 * page links forward to the freshly-created `/communities/:id`.
 */
export default function CommunityProposalDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t } = useI18n()
  const [p, setP] = useState<Proposal | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [actionBusy, setActionBusy] = useState<string | null>(null)
  const [showRejectForm, setShowRejectForm] = useState(false)
  const [rejectReason, setRejectReason] = useState('')

  async function load() {
    if (!id) return
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<Proposal>(`/admin/community-proposals/${id}`)
      setP(res)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id])

  async function approve() {
    if (!p) return
    setActionBusy('approve')
    try {
      await api.post(`/admin/community-proposals/${p.id}/approve`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  async function reject() {
    if (!p) return
    setActionBusy('reject')
    try {
      await api.post(`/admin/community-proposals/${p.id}/reject`, {
        reason: rejectReason.trim(),
      })
      setShowRejectForm(false)
      setRejectReason('')
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  if (loading && !p) return <p className="text-slate-500">{t('common.loading')}</p>
  if (error && !p) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
        <AlertOctagon className="w-4 h-4" /> {error}
      </div>
    )
  }
  if (!p) {
    return (
      <div>
        <Link to="/community-proposals" className="text-cyan-300 text-sm">
          {t('communityProposals.backToProposals')}
        </Link>
        <p className="text-slate-500 mt-3">{t('communityProposals.notFound')}</p>
      </div>
    )
  }

  const tint = STATUS_TINT[p.status] ?? STATUS_TINT.pending
  const isPending = p.status === 'pending'

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate('/community-proposals')}
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </button>
        <p className="text-xs text-slate-500 font-mono flex-1">
          {t('communityProposals.proposalNumber', { id: p.id })}
        </p>
        <span
          className={`px-2 py-0.5 rounded-md text-[10px] font-bold ring-1 uppercase ${tint}`}
        >
          {p.status}
        </span>
        <button
          onClick={load}
          disabled={loading}
          className="p-2 rounded-md bg-white/5 hover:bg-white/10 text-slate-300 disabled:opacity-50"
          title={t('common.refresh')}
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {/* Hero */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-5">
        <div className="flex items-start gap-4">
          <div className="w-16 h-16 rounded-2xl bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold text-2xl">
            {p.name.charAt(0).toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h1 className="text-2xl font-bold text-white truncate">{p.name}</h1>
              {p.regionCode && (
                <span className="px-1.5 py-0.5 rounded-md bg-white/5 ring-1 ring-white/10 text-[10px] font-bold text-slate-300">
                  {p.regionCode}
                </span>
              )}
            </div>
            <p className="text-xs text-slate-500 mt-1">
              {t('communityProposals.proposedBy')}{' '}
              <Link
                to={`/users/${p.userId}`}
                className="text-cyan-300 hover:text-cyan-200"
              >
                {p.userName ?? p.userEmail ?? t('communityProposals.proposedByUser', { id: p.userId })}
              </Link>
            </p>
          </div>
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      )}

      {/* Description */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3">
          {t('communityProposals.description')}
        </h2>
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
          <p className="text-sm text-slate-200 leading-relaxed whitespace-pre-line">
            {p.description}
          </p>
        </div>
      </section>

      {/* Result section — when approved/rejected */}
      {p.status === 'approved' && p.approvedCommunityId && (
        <section>
          <div className="rounded-xl bg-emerald-500/10 ring-1 ring-emerald-500/30 p-4">
            <p className="text-[10px] uppercase tracking-wider text-emerald-300 mb-1 flex items-center gap-1">
              <UsersIcon className="w-3 h-3" />
              {t('communityProposals.approvedCreated')}
            </p>
            <Link
              to={`/communities/${p.approvedCommunityId}`}
              className="text-sm font-bold text-white hover:text-cyan-300 inline-flex items-center gap-1"
            >
              <code className="font-mono">{p.approvedCommunityId}</code>
              <span>{t('communityProposals.openDetail')}</span>
            </Link>
          </div>
        </section>
      )}
      {p.status === 'rejected' && p.rejectionReason && (
        <section>
          <div className="rounded-xl bg-rose-500/10 ring-1 ring-rose-500/30 p-4">
            <p className="text-[10px] uppercase tracking-wider text-rose-300 mb-1">
              {t('communityProposals.rejectionReason')}
            </p>
            <p className="text-sm text-rose-200">{p.rejectionReason}</p>
          </div>
        </section>
      )}

      {/* Timeline */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('communityProposals.timeline')}</h2>
        <ul className="space-y-2">
          <TimelineRow
            label={t('communityProposals.submitted')}
            ts={p.submittedAt}
            icon={<Calendar className="w-3 h-3" />}
            tone="slate"
          />
          {p.reviewedAt && (
            <TimelineRow
              label={p.status === 'approved' ? t('communityProposals.statusApproved') : t('communityProposals.statusRejected')}
              ts={p.reviewedAt}
              icon={
                p.status === 'approved' ? (
                  <Check className="w-3 h-3" />
                ) : (
                  <X className="w-3 h-3" />
                )
              }
              tone={p.status === 'approved' ? 'emerald' : 'rose'}
              extra={
                p.reviewedBy ? (
                  <Link
                    to={`/users/${p.reviewedBy}`}
                    className="text-cyan-300 hover:text-cyan-200"
                  >
                    {t('communityProposals.byAdmin', { id: p.reviewedBy })}
                  </Link>
                ) : null
              }
            />
          )}
        </ul>
      </section>

      {/* Action zone */}
      {isPending && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('communityProposals.action')}</h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 space-y-3">
            {showRejectForm ? (
              <div className="space-y-2">
                <p className="text-[10px] uppercase tracking-wider text-slate-400">
                  {t('communityProposals.rejectionReasonShown')}
                </p>
                <textarea
                  value={rejectReason}
                  onChange={(e) => setRejectReason(e.target.value)}
                  rows={3}
                  placeholder={t('communityProposals.rejectPlaceholder')}
                  className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 resize-y"
                />
                <div className="flex items-center justify-end gap-2">
                  <button
                    onClick={() => {
                      setShowRejectForm(false)
                      setRejectReason('')
                    }}
                    className="px-3 py-2 rounded-md text-sm text-slate-300 hover:bg-white/5"
                  >
                    {t('common.cancel')}
                  </button>
                  <button
                    onClick={reject}
                    disabled={actionBusy === 'reject'}
                    className="inline-flex items-center gap-2 px-4 py-2 rounded-md text-sm font-bold bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                  >
                    <X className="w-4 h-4" />
                    {actionBusy === 'reject' ? t('communityProposals.rejecting') : t('communityProposals.confirmReject')}
                  </button>
                </div>
              </div>
            ) : (
              <div className="flex items-center gap-3">
                <button
                  onClick={approve}
                  disabled={actionBusy !== null}
                  className="flex-1 inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg text-sm font-bold bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 ring-1 ring-emerald-500/30 disabled:opacity-50"
                >
                  <Check className="w-5 h-5" />
                  {actionBusy === 'approve'
                    ? t('communityProposals.creatingCommunity')
                    : t('communityProposals.approveCreate')}
                </button>
                <button
                  onClick={() => setShowRejectForm(true)}
                  disabled={actionBusy !== null}
                  className="flex-1 inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg text-sm font-bold bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                >
                  <X className="w-5 h-5" />
                  {t('communityProposals.rejectEllipsis')}
                </button>
              </div>
            )}
          </div>
        </section>
      )}
    </div>
  )
}

function TimelineRow({
  label,
  ts,
  icon,
  tone,
  extra,
}: {
  label: string
  ts: string
  icon: React.ReactNode
  tone: 'slate' | 'emerald' | 'rose'
  extra?: React.ReactNode
}) {
  const { locale } = useI18n()
  const dotCls = {
    slate: 'bg-slate-500/20 ring-slate-500/30 text-slate-300',
    emerald: 'bg-emerald-500/20 ring-emerald-500/30 text-emerald-300',
    rose: 'bg-rose-500/20 ring-rose-500/30 text-rose-300',
  }[tone]
  return (
    <li className="flex items-center gap-3 text-sm">
      <span
        className={`w-6 h-6 rounded-full ring-1 flex items-center justify-center ${dotCls}`}
      >
        {icon}
      </span>
      <span className="text-slate-200 font-semibold">{label}</span>
      <span className="text-slate-500 text-xs flex-1">
        {fmtDateTime(ts, locale)}
      </span>
      {extra && <span className="text-xs">{extra}</span>}
    </li>
  )
}
