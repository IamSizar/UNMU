import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  Crown,
  Users as UsersIcon,
  FileText,
  Trash2,
  RefreshCw,
  AlertTriangle,
  Calendar,
  Lock,
  Globe,
  Save,
  Tag,
  X,
  Sparkles,
  UserPlus,
  Loader2,
  Search,
  Check,
} from 'lucide-react'
import { api, getToken } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'
import type { Locale } from '../i18n/translations'
import { absoluteUrl } from './Communities'

// Mirrors backend repositories.AdminCommunityRow.
//
// Step-19 (mig 0019, items 2.13–2.18): description / rules / cover /
// isPublic / category / tags surfaced for direct editing by admin.
type AdminCommunity = {
  id: string
  name: string
  tagline?: string
  description?: string
  rules?: string
  coverUrl?: string
  // Mig 0028 — square avatar separate from the wide cover banner.
  avatarUrl?: string
  isPublic: boolean
  category?: string
  tags?: string[]
  regionCode?: string
  ownerId?: number | null
  ownerName?: string
  ownerEmail?: string
  memberCount: number
  postCount: number
}

// Mirrors backend repositories.AdminCommunityMember.
type Member = {
  userId: number
  email: string
  name: string
  role: string
  joinedAt: string
  isOwner: boolean
}

type ListResponse = { communities: AdminCommunity[] }
type MembersResponse = { members: Member[] }

/**
 * CommunityDetail — `/communities/:id`.
 *
 * Single-community drill-in for admins. Two requests fetched in
 * parallel:
 *   * `/admin/communities` (filtered client-side to find the row)
 *   * `/admin/communities/:id/members`
 *
 * v1 is read-only. Edit / Remove-member / Posts-in-community sections
 * are stubbed for follow-up — backend endpoints either already exist
 * (PATCH for edit) or will need a small addition (filter posts by
 * community_id; remove-member endpoint).
 */
export default function CommunityDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t } = useI18n()

  const [community, setCommunity] = useState<AdminCommunity | null>(null)
  const [members, setMembers] = useState<Member[]>([])
  const [loading, setLoading] = useState(false)
  const [actionBusy, setActionBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    if (!id) return
    setLoading(true)
    setError(null)
    try {
      // List + members in parallel — list scan is small (<100 rows in
      // realistic deployments) so client-side filtering is cheaper
      // than adding a `GET /admin/communities/:id` endpoint just for
      // the detail page.
      const [list, mem] = await Promise.all([
        api.get<ListResponse>('/admin/communities'),
        api.get<MembersResponse>(`/admin/communities/${id}/members`),
      ])
      const found = (list.communities ?? []).find((c) => c.id === id) ?? null
      setCommunity(found)
      // Pin the owner row to the top — the backend already sorts
      // newest-joined first, so we re-sort with owner-first as a stable
      // secondary order rather than mutating the backend ordering.
      const sorted = [...(mem.members ?? [])].sort((a, b) => {
        if (a.isOwner !== b.isOwner) return a.isOwner ? -1 : 1
        return 0
      })
      setMembers(sorted)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  async function deleteCommunity() {
    if (!community) return
    if (!confirm(t('communities.deleteConfirm', { name: community.name }))) return
    setActionBusy(true)
    try {
      await api.delete(`/admin/communities/${community.id}`)
      navigate('/communities')
    } catch (e) {
      setError((e as Error).message)
      setActionBusy(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id])

  if (loading && !community) {
    return <p className="text-slate-500">{t('common.loading')}</p>
  }
  if (error && !community) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
        <AlertTriangle className="w-4 h-4" />
        {error}
      </div>
    )
  }
  if (!community) {
    return (
      <div>
        <Link to="/communities" className="text-cyan-300 text-sm">
          {t('communityDetail.backToCommunities')}
        </Link>
        <p className="text-slate-500 mt-3">{t('communityDetail.notFound')}</p>
      </div>
    )
  }

  const region = community.regionCode || 'GL'
  const initials = (community.regionCode || community.name)
    .charAt(0)
    .toUpperCase()

  return (
    <div className="space-y-6">
      {/* ── Top row: back / refresh ───────────────────────────── */}
      <div className="flex items-center gap-3">
        <Link
          to="/communities"
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </Link>
        <p className="text-xs text-slate-500 font-mono flex-1">
          {community.id}
        </p>
        <button
          onClick={load}
          disabled={loading}
          className="p-2 rounded-md bg-white/5 hover:bg-white/10 text-slate-300 disabled:opacity-50"
          title={t('common.refresh')}
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {/* ── Hero card: avatar + name + tagline ────────────────── */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-5">
        <div className="flex items-start gap-4">
          <div
            className={`w-16 h-16 rounded-2xl flex items-center justify-center font-bold text-2xl shrink-0 ring-1 ${
              region === 'GL'
                ? 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30'
                : region === 'US'
                ? 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30'
                : 'bg-gold-500/15 text-gold-300 ring-gold-500/30'
            }`}
          >
            {initials}
          </div>
          <div className="flex-1 min-w-0">
            <h1 className="text-2xl font-bold text-white truncate">
              {community.name}
            </h1>
            <p className="text-xs text-slate-500 mt-0.5">
              {community.regionCode
                ? t('communityDetail.region', { region: community.regionCode })
                : t('communityDetail.global')}
            </p>
            {community.tagline && (
              <p className="text-sm text-slate-300 mt-3 leading-relaxed">
                {community.tagline}
              </p>
            )}
          </div>
        </div>
      </div>

      {/* ── 3-stat strip ──────────────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Stat
          icon={<UsersIcon className="w-5 h-5 text-cyan-300" />}
          label={t('communityDetail.members')}
          value={community.memberCount.toString()}
        />
        <Stat
          icon={<FileText className="w-5 h-5 text-emerald-300" />}
          label={t('communityDetail.posts')}
          value={community.postCount.toString()}
        />
        <OwnerStat community={community} />
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      )}

      {/* ── Step-19 (mig 0019, items 2.13–2.18) — metadata editor ── */}
      <MetadataEditor community={community} onSaved={load} />

      {/* ── Owners (mig 0032 — primary + co-owners + invite button) ── */}
      <OwnersSection communityId={community.id} communityName={community.name} />

      {/* ── Members list ──────────────────────────────────────── */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
          <UsersIcon className="w-4 h-4" />
          {t('communityDetail.membersCount', { count: members.length })}
        </h2>
        {members.length === 0 ? (
          <p className="text-slate-500 text-sm">{t('communityDetail.noMembers')}</p>
        ) : (
          <ul className="space-y-2">
            {members.map((m) => (
              <MemberRow
                key={m.userId}
                member={m}
                communityId={community.id}
                busy={actionBusy}
                onRemove={async () => {
                  if (
                    !confirm(
                      t('communityDetail.removeMemberConfirm', {
                        name: m.name || m.email,
                        community: community.name,
                      }),
                    )
                  )
                    return
                  setActionBusy(true)
                  try {
                    await api.delete(
                      `/admin/communities/${community.id}/members/${m.userId}`,
                    )
                    await load()
                  } catch (e) {
                    setError((e as Error).message)
                  } finally {
                    setActionBusy(false)
                  }
                }}
                onTransfer={async () => {
                  if (
                    !confirm(
                      t('communityDetail.transferConfirm', {
                        community: community.name,
                        name: m.name || m.email,
                      }),
                    )
                  )
                    return
                  setActionBusy(true)
                  try {
                    await api.post(
                      `/admin/communities/${community.id}/transfer-ownership`,
                      { newOwnerId: m.userId },
                    )
                    await load()
                  } catch (e) {
                    setError((e as Error).message)
                  } finally {
                    setActionBusy(false)
                  }
                }}
              />
            ))}
          </ul>
        )}
      </section>

      {/* ── Danger zone ───────────────────────────────────────── */}
      <section>
        <h2 className="text-sm font-semibold text-rose-300 mb-3">
          {t('communityDetail.dangerZone')}
        </h2>
        <div className="rounded-xl bg-rose-500/5 ring-1 ring-rose-500/20 p-4">
          <p className="text-sm text-slate-300 mb-3">
            {t('communityDetail.dangerDescription')}
          </p>
          <button
            onClick={deleteCommunity}
            disabled={actionBusy}
            className="flex items-center gap-2 px-3 py-2 rounded-md text-sm font-medium bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
          >
            <Trash2 className="w-4 h-4" />
            {actionBusy ? t('communityDetail.deleting') : t('communityDetail.deleteCommunity')}
          </button>
        </div>
      </section>
    </div>
  )
}

// ─── Helpers ─────────────────────────────────────────────────────────

function MemberRow({
  member: m,
  communityId: _communityId,
  busy,
  onRemove,
  onTransfer,
}: {
  member: Member
  communityId: string
  busy: boolean
  onRemove: () => void
  onTransfer: () => void
}) {
  const { t, locale } = useI18n()
  return (
    <li className="rounded-lg bg-white/[0.02] ring-1 ring-white/5 px-3 py-2.5 flex items-center gap-3">
      <Link
        to={`/users/${m.userId}`}
        // SCHOLAR retired (mig 0013) — only ADMIN / EXPERT / USER tints.
        className={`w-9 h-9 rounded-full flex items-center justify-center font-bold text-sm shrink-0 ring-1 ${
          m.role === 'ADMIN'
            ? 'bg-gold-500/15 text-gold-300 ring-gold-500/30'
            : m.role === 'EXPERT'
            ? 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30'
            : 'bg-white/5 text-slate-300 ring-white/10'
        } hover:opacity-80`}
        title={t('common.viewUser')}
      >
        {(m.name || m.email).charAt(0).toUpperCase()}
      </Link>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          {m.isOwner && (
            <Crown className="w-3.5 h-3.5 text-gold-400 shrink-0" />
          )}
          <Link
            to={`/users/${m.userId}`}
            className="text-sm font-semibold text-white truncate hover:text-cyan-300"
          >
            {m.name || m.email.split('@')[0]}
          </Link>
          <RoleBadge role={m.role} />
          {m.isOwner && (
            <span className="text-[10px] uppercase font-bold tracking-wider text-gold-300">
              {t('communityDetail.ownerBadge')}
            </span>
          )}
        </div>
        <p className="text-[11px] text-slate-500 truncate">{m.email}</p>
      </div>
      <span className="text-[10px] text-slate-500 shrink-0 flex items-center gap-1">
        <Calendar className="w-3 h-3" />
        {relativeTime(m.joinedAt, locale)}
      </span>
      {/* Owner-row gets no actions — admin must transfer first.
          For everyone else: a small icon-only Transfer + Remove
          pair so a busy admin can clean up a community without
          leaving the page. Both gated on `busy` so a quick
          double-click can't fire two API calls. */}
      {!m.isOwner && (
        <div className="flex items-center gap-1 shrink-0">
          <button
            type="button"
            disabled={busy}
            onClick={onTransfer}
            title={t('communityDetail.transferTooltip')}
            className="p-1.5 rounded-md text-slate-400 hover:text-cyan-300 hover:bg-cyan-500/10 disabled:opacity-40"
          >
            <Crown className="w-3.5 h-3.5" />
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={onRemove}
            title={t('communityDetail.removeTooltip')}
            className="p-1.5 rounded-md text-slate-400 hover:text-rose-300 hover:bg-rose-500/10 disabled:opacity-40"
          >
            <Trash2 className="w-3.5 h-3.5" />
          </button>
        </div>
      )}
    </li>
  )
}

function RoleBadge({ role }: { role: string }) {
  // SCHOLAR retired (mig 0013) — only USER / EXPERT / ADMIN remain.
  const cls: Record<string, string> = {
    ADMIN: 'bg-gold-500/15 text-gold-300 ring-gold-500/30',
    EXPERT: 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30',
    USER: 'bg-white/5 text-slate-300 ring-white/10',
  }
  return (
    <span
      className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold ring-1 ${
        cls[role.toUpperCase()] ?? cls.USER
      }`}
    >
      {role}
    </span>
  )
}

function Stat({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode
  label: string
  value: string
}) {
  return (
    <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
      <div className="flex items-center gap-2 text-xs text-slate-400">
        {icon}
        {label}
      </div>
      <div className="mt-2 text-2xl font-bold text-white">{value}</div>
    </div>
  )
}

function OwnerStat({ community: c }: { community: AdminCommunity }) {
  const { t } = useI18n()
  const hasOwner = !!c.ownerId
  return (
    <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
      <div className="flex items-center gap-2 text-xs text-slate-400">
        <Crown className="w-5 h-5 text-gold-400" />
        {t('communityDetail.owner')}
      </div>
      {hasOwner ? (
        <Link
          to={`/users/${c.ownerId}`}
          className="mt-2 block text-base font-bold text-white hover:text-cyan-300 truncate"
        >
          {c.ownerName}
          <span className="block text-[11px] font-medium text-slate-500 truncate">
            {c.ownerEmail}
          </span>
        </Link>
      ) : (
        <p className="mt-2 text-base font-bold text-rose-300">{t('communityDetail.noOwner')}</p>
      )}
    </div>
  )
}

// MetadataEditor — owner/admin editor for items 2.13 → 2.18. One
// PATCH /admin/communities/:id call covers description / rules /
// cover / isPublic / category / tags / name / tagline. Cover image
// upload lives behind the existing /api/me/uploads/image endpoint
// — admin uploads from their browser and we paste the resulting
// /uploads/images/... URL into the form.
function MetadataEditor({
  community,
  onSaved,
}: {
  community: AdminCommunity
  onSaved: () => void
}) {
  const { t } = useI18n()
  // Predefined category list — mirrors handlers/social.go #communityCategories.
  // Hard-coded here (rather than fetched) because the dashboard's
  // `api` helper auto-prefixes /api and we want to keep the editor
  // completely synchronous.
  const CATEGORIES = [
    '',
    'general',
    'tech',
    'finance',
    'halal',
    'energy',
    'crypto',
    'realestate',
    'healthcare',
    'consumer',
    'industrial',
    'emerging',
    'etf',
  ]

  const [name, setName] = useState(community.name)
  const [tagline, setTagline] = useState(community.tagline ?? '')
  const [description, setDescription] = useState(community.description ?? '')
  const [rules, setRules] = useState(community.rules ?? '')
  const [coverUrl, setCoverUrl] = useState(community.coverUrl ?? '')
  // Mig 0028 — square avatar URL (separate from the wide cover).
  const [avatarUrl, setAvatarUrl] = useState(community.avatarUrl ?? '')
  const [isPublic, setIsPublic] = useState(community.isPublic)
  const [category, setCategory] = useState(community.category ?? '')
  const [tags, setTags] = useState<string[]>(community.tags ?? [])
  const [tagInput, setTagInput] = useState('')
  // Step-23 — paid community pricing.
  const c = community as AdminCommunity & {
    joinPriceMonthlyCents?: number
    joinPriceYearlyCents?: number
    priceCurrency?: string
  }
  const [monthlyDollars, setMonthlyDollars] = useState(
    centsToDollarStr(c.joinPriceMonthlyCents),
  )
  const [yearlyDollars, setYearlyDollars] = useState(
    centsToDollarStr(c.joinPriceYearlyCents),
  )
  const [priceCurrency, setPriceCurrency] = useState(
    c.priceCurrency || 'usd',
  )
  const [paidMode, setPaidMode] = useState(
    (c.joinPriceMonthlyCents ?? 0) > 0 ||
      (c.joinPriceYearlyCents ?? 0) > 0,
  )

  const [busy, setBusy] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [savedAt, setSavedAt] = useState<number | null>(null)

  // Reset form when the community prop changes (after parent reload).
  useEffect(() => {
    setName(community.name)
    setTagline(community.tagline ?? '')
    setDescription(community.description ?? '')
    setRules(community.rules ?? '')
    setCoverUrl(community.coverUrl ?? '')
    setAvatarUrl(community.avatarUrl ?? '')
    setIsPublic(community.isPublic)
    setCategory(community.category ?? '')
    setTags(community.tags ?? [])
    setTagInput('')
    const cp = community as AdminCommunity & {
      joinPriceMonthlyCents?: number
      joinPriceYearlyCents?: number
      priceCurrency?: string
    }
    setMonthlyDollars(centsToDollarStr(cp.joinPriceMonthlyCents))
    setYearlyDollars(centsToDollarStr(cp.joinPriceYearlyCents))
    setPriceCurrency(cp.priceCurrency || 'usd')
    setPaidMode(
      (cp.joinPriceMonthlyCents ?? 0) > 0 ||
        (cp.joinPriceYearlyCents ?? 0) > 0,
    )
  }, [community])

  function addTag() {
    const tag = tagInput.trim().toLowerCase()
    if (!tag || tags.includes(tag)) return
    if (tags.length >= 10) {
      setErr(t('communityDetail.maxTags'))
      return
    }
    if (tag.length > 30) {
      setErr(t('communityDetail.tagTooLong'))
      return
    }
    setTags([...tags, tag])
    setTagInput('')
    setErr(null)
  }

  function removeTag(t: string) {
    setTags(tags.filter((x) => x !== t))
  }

  async function uploadCover(file: File) {
    setUploading(true)
    setErr(null)
    try {
      // Bypass the api wrapper — its `post()` helper auto-JSON-encodes
      // the body, which would mangle a FormData multipart payload.
      // We call fetch directly with the same auth header pattern.
      const fd = new FormData()
      fd.append('file', file)
      const base =
        (import.meta.env.VITE_API_BASE_URL as string | undefined) ??
        'http://localhost:8080/api'
      const token = getToken()
      const res = await fetch(`${base}/me/uploads/image`, {
        method: 'POST',
        body: fd,
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      })
      if (!res.ok) {
        let msg = `Upload failed (${res.status}).`
        try {
          const j = await res.json()
          if (j?.error) msg = j.error
        } catch {
          // ignore json parse errors — keep default msg
        }
        throw new Error(msg)
      }
      const j = (await res.json()) as { url: string }
      setCoverUrl(j.url)
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setUploading(false)
    }
  }

  // Mig 0028 — avatar uploader. Same plumbing as uploadCover, just
  // routes the resulting URL to setAvatarUrl. Kept as a sibling rather
  // than a generic helper so error states remain readable per-field.
  async function uploadAvatar(file: File) {
    setUploading(true)
    setErr(null)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const base =
        (import.meta.env.VITE_API_BASE_URL as string | undefined) ??
        'http://localhost:8080/api'
      const token = getToken()
      const res = await fetch(`${base}/me/uploads/image`, {
        method: 'POST',
        body: fd,
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      })
      if (!res.ok) {
        let msg = `Upload failed (${res.status}).`
        try {
          const j = await res.json()
          if (j?.error) msg = j.error
        } catch {
          // ignore json parse errors — keep default msg
        }
        throw new Error(msg)
      }
      const j = (await res.json()) as { url: string }
      setAvatarUrl(j.url)
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setUploading(false)
    }
  }

  async function save() {
    // Step-23 follow-up — confirm before flipping free → paid.
    // The backend kicks every member except the owner in the same
    // transaction so the price gate actually kicks in for the
    // existing user base. Make the consequence explicit.
    const cp = community as AdminCommunity & {
      joinPriceMonthlyCents?: number
      joinPriceYearlyCents?: number
    }
    const wasFree =
      (cp.joinPriceMonthlyCents ?? 0) <= 0 &&
      (cp.joinPriceYearlyCents ?? 0) <= 0
    const willBePaid =
      paidMode &&
      (dollarsToCents(monthlyDollars) > 0 ||
        dollarsToCents(yearlyDollars) > 0)
    if (wasFree && willBePaid) {
      const yes = confirm(
        community.memberCount === 1
          ? t('communityDetail.flipPaidConfirmOne', {
              name: community.name,
              count: community.memberCount,
            })
          : t('communityDetail.flipPaidConfirm', {
              name: community.name,
              count: community.memberCount,
            }),
      )
      if (!yes) return
    }
    setBusy(true)
    setErr(null)
    try {
      // Pricing payload. Free mode forces both prices to 0;
      // paid mode honours whatever the user typed.
      const monthlyCents = paidMode ? dollarsToCents(monthlyDollars) : 0
      const yearlyCents = paidMode ? dollarsToCents(yearlyDollars) : 0
      await api.patch(`/admin/communities/${community.id}`, {
        name: name.trim(),
        tagline: tagline.trim(),
        description: description.trim(),
        rules: rules.trim(),
        coverUrl: coverUrl.trim(),
        avatarUrl: avatarUrl.trim(),
        isPublic,
        category,
        tags,
        joinPriceMonthlyCents: monthlyCents,
        joinPriceYearlyCents: yearlyCents,
        priceCurrency: priceCurrency,
      })
      setSavedAt(Date.now())
      onSaved()
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <section>
      <h2 className="text-sm font-semibold text-slate-300 mb-3">
        {t('communityDetail.metadataTitle')}
      </h2>
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-5 space-y-4">
        {/* Cover image */}
        <div>
          <p className="text-[11px] text-slate-400 mb-2 font-medium">
            {t('communityDetail.coverImage')}
          </p>
          {coverUrl ? (
            <div className="relative">
              <img
                src={absoluteUrl(coverUrl)}
                alt="cover"
                className="w-full h-32 object-cover rounded-lg ring-1 ring-white/10"
              />
              <button
                type="button"
                onClick={() => setCoverUrl('')}
                className="absolute end-2 top-2 p-1 rounded-md bg-black/60 hover:bg-black/80 text-white"
                title={t('communityDetail.removeCover')}
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          ) : (
            <div className="h-24 rounded-lg ring-1 ring-dashed ring-white/15 bg-white/[0.02] flex items-center justify-center text-xs text-slate-500">
              {t('communityDetail.noCoverSet')}
            </div>
          )}
          <div className="mt-2 flex items-center gap-2">
            <label className="px-3 py-1.5 rounded-md bg-cyan-500/15 hover:bg-cyan-500/25 ring-1 ring-cyan-500/30 text-cyan-300 text-xs font-medium cursor-pointer">
              {uploading ? t('communityDetail.uploading') : t('communityDetail.uploadImage')}
              <input
                type="file"
                accept="image/*"
                hidden
                onChange={(e) => {
                  const f = e.target.files?.[0]
                  if (f) uploadCover(f)
                }}
              />
            </label>
            <input
              value={coverUrl}
              onChange={(e) => setCoverUrl(e.target.value)}
              placeholder={t('communityDetail.pasteUrl')}
              className="flex-1 px-3 py-1.5 rounded-md bg-white/5 ring-1 ring-white/10 text-xs text-slate-200 font-mono"
            />
          </div>
        </div>

        {/* Avatar (square) — mig 0028. Separate from the wide cover.
            Shown alongside it so the admin sees both image options
            together when editing a community. */}
        <div>
          <p className="text-[11px] text-slate-400 mb-2 font-medium">
            {t('communityDetail.avatarSquareLogo')}
          </p>
          <div className="flex items-start gap-3">
            {avatarUrl ? (
              <div className="relative">
                <img
                  src={absoluteUrl(avatarUrl)}
                  alt="avatar"
                  className="w-20 h-20 object-cover rounded-xl ring-1 ring-white/10"
                />
                <button
                  type="button"
                  onClick={() => setAvatarUrl('')}
                  className="absolute -end-1 -top-1 p-1 rounded-full bg-black/80 hover:bg-black text-white"
                  title={t('communityDetail.removeAvatar')}
                >
                  <X className="w-3 h-3" />
                </button>
              </div>
            ) : (
              <div className="w-20 h-20 rounded-xl ring-1 ring-dashed ring-white/15 bg-white/[0.02] flex items-center justify-center text-[10px] text-slate-500 text-center px-2">
                {t('communityDetail.noAvatarSet')}
              </div>
            )}
            <div className="flex-1 space-y-2">
              <label className="inline-block px-3 py-1.5 rounded-md bg-cyan-500/15 hover:bg-cyan-500/25 ring-1 ring-cyan-500/30 text-cyan-300 text-xs font-medium cursor-pointer">
                {uploading ? t('communityDetail.uploading') : t('communityDetail.uploadImage')}
                <input
                  type="file"
                  accept="image/*"
                  hidden
                  onChange={(e) => {
                    const f = e.target.files?.[0]
                    if (f) uploadAvatar(f)
                  }}
                />
              </label>
              <input
                value={avatarUrl}
                onChange={(e) => setAvatarUrl(e.target.value)}
                placeholder={t('communityDetail.pasteUrl')}
                className="w-full px-3 py-1.5 rounded-md bg-white/5 ring-1 ring-white/10 text-xs text-slate-200 font-mono"
              />
            </div>
          </div>
        </div>

        {/* Public / private */}
        <button
          type="button"
          onClick={() => setIsPublic(!isPublic)}
          className={`w-full text-start flex items-center gap-3 px-4 py-3 rounded-lg ring-1 ${
            isPublic
              ? 'bg-emerald-500/10 ring-emerald-500/30'
              : 'bg-gold-500/10 ring-gold-500/30'
          }`}
        >
          {isPublic ? (
            <Globe className="w-5 h-5 text-emerald-300" />
          ) : (
            <Lock className="w-5 h-5 text-gold-300" />
          )}
          <div className="flex-1">
            <p
              className={`text-sm font-bold ${
                isPublic ? 'text-emerald-300' : 'text-gold-300'
              }`}
            >
              {isPublic ? t('communities.public') : t('communities.private')}
            </p>
            <p className="text-[11px] text-slate-400">
              {isPublic
                ? t('communityDetail.publicDesc')
                : t('communityDetail.privateDesc')}
            </p>
          </div>
          <span className="text-[10px] uppercase font-bold tracking-wider text-slate-400">
            {t('communityDetail.toggle')}
          </span>
        </button>

        {/* Name + tagline */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <p className="text-[11px] text-slate-400 mb-1 font-medium">
              {t('communityDetail.name')}
            </p>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={60}
              className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
            />
          </div>
          <div>
            <p className="text-[11px] text-slate-400 mb-1 font-medium">
              {t('communityDetail.tagline')}
            </p>
            <input
              value={tagline}
              onChange={(e) => setTagline(e.target.value)}
              maxLength={200}
              className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
            />
          </div>
        </div>

        {/* Description */}
        <div>
          <p className="text-[11px] text-slate-400 mb-1 font-medium">
            {t('communityDetail.descriptionLong')}
          </p>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            maxLength={4000}
            rows={3}
            className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 resize-y"
          />
        </div>

        {/* Rules */}
        <div>
          <p className="text-[11px] text-slate-400 mb-1 font-medium">
            {t('communityDetail.rules')}
          </p>
          <textarea
            value={rules}
            onChange={(e) => setRules(e.target.value)}
            maxLength={4000}
            rows={4}
            className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 resize-y"
          />
        </div>

        {/* Category */}
        <div>
          <p className="text-[11px] text-slate-400 mb-1 font-medium">
            {t('communityDetail.category')}
          </p>
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
          >
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c === '' ? t('communityDetail.categoryNone') : c[0].toUpperCase() + c.slice(1)}
              </option>
            ))}
          </select>
        </div>

        {/* Tags */}
        <div>
          <p className="text-[11px] text-slate-400 mb-1 font-medium">
            {t('communityDetail.tagsCount', { count: tags.length })}
          </p>
          <div className="flex gap-2">
            <input
              value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault()
                  addTag()
                }
              }}
              placeholder={t('communityDetail.addTagPlaceholder')}
              maxLength={30}
              className="flex-1 px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
            />
            <button
              type="button"
              onClick={addTag}
              className="px-3 py-2 rounded-md bg-cyan-500/15 hover:bg-cyan-500/25 ring-1 ring-cyan-500/30 text-cyan-300 text-sm"
            >
              {t('communityDetail.add')}
            </button>
          </div>
          {tags.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1.5">
              {tags.map((tag) => (
                <span
                  key={tag}
                  className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs bg-white/5 ring-1 ring-white/10 text-slate-300"
                >
                  <Tag className="w-3 h-3 text-slate-500" />#{tag}
                  <button
                    type="button"
                    onClick={() => removeTag(tag)}
                    className="ms-0.5 text-slate-500 hover:text-rose-300"
                    title={t('communityDetail.removeTag')}
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              ))}
            </div>
          )}
        </div>

        {/* Step-23 — paid community pricing. */}
        <div>
          <p className="text-[11px] text-slate-400 mb-2 font-medium flex items-center gap-1">
            {t('communityDetail.pricing')}
          </p>
          <div className="rounded-lg ring-1 ring-white/10 bg-white/5 p-3 space-y-3">
            <button
              type="button"
              onClick={() => setPaidMode(!paidMode)}
              className={`w-full text-start flex items-center gap-3 px-3 py-2 rounded-md ring-1 ${
                paidMode
                  ? 'bg-gold-500/10 ring-gold-500/30'
                  : 'bg-emerald-500/10 ring-emerald-500/30'
              }`}
            >
              <span className="text-sm font-bold text-white">
                {paidMode ? t('communityDetail.paidCommunity') : t('communityDetail.freeCommunity')}
              </span>
              <span className="text-[10px] uppercase tracking-wider text-slate-400 ms-auto">
                {t('communityDetail.toggle')}
              </span>
            </button>
            {paidMode && (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-1">
                      {t('communityDetail.monthly')}
                    </p>
                    <input
                      value={monthlyDollars}
                      onChange={(e) => setMonthlyDollars(e.target.value)}
                      placeholder="0"
                      inputMode="decimal"
                      className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 font-mono"
                    />
                  </div>
                  <div>
                    <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-1">
                      {t('communityDetail.yearly')}
                    </p>
                    <input
                      value={yearlyDollars}
                      onChange={(e) => setYearlyDollars(e.target.value)}
                      placeholder="0"
                      inputMode="decimal"
                      className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 font-mono"
                    />
                  </div>
                </div>
                <div>
                  <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-1">
                    {t('communityDetail.currency')}
                  </p>
                  <select
                    value={priceCurrency}
                    onChange={(e) => setPriceCurrency(e.target.value)}
                    className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
                  >
                    {['usd', 'iqd', 'sar', 'aed', 'eur', 'gbp'].map((cur) => (
                      <option key={cur} value={cur}>
                        {cur.toUpperCase()}
                      </option>
                    ))}
                  </select>
                </div>
                {/* Live "save X%" preview — computed from the typed
                    values so the admin sees the discount they're
                    offering. Mirrors the same formula in the Flutter
                    edit sheet (lib/utils/price_format.dart). Hidden
                    when only one plan is set or yearly ≥ monthly×12. */}
                {(() => {
                  const m = dollarsToCents(monthlyDollars)
                  const y = dollarsToCents(yearlyDollars)
                  if (m <= 0 || y <= 0) return null
                  const annualViaMonthly = m * 12
                  if (y >= annualViaMonthly) return null
                  const pct = Math.round(
                    ((annualViaMonthly - y) / annualViaMonthly) * 100,
                  )
                  return (
                    <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-emerald-500/15 ring-1 ring-emerald-500/40 text-emerald-300 text-[11px] font-bold">
                      <span>💰</span>
                      <span>{t('communityDetail.saveYearlyHint', { pct })}</span>
                    </div>
                  )
                })()}
                <p className="text-[11px] text-slate-500">
                  {t('communityDetail.pricingNote')}
                </p>
              </>
            )}
          </div>
        </div>

        {err && (
          <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs">
            {err}
          </div>
        )}

        <div className="flex items-center justify-between pt-1">
          <div className="text-[11px] text-slate-500">
            {savedAt && Date.now() - savedAt < 4000 ? t('communityDetail.saved') : ' '}
          </div>
          <button
            onClick={save}
            disabled={busy || uploading}
            className="flex items-center gap-2 px-4 py-2 rounded-md text-sm font-bold bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 ring-1 ring-cyan-500/30 disabled:opacity-50"
          >
            <Save className="w-4 h-4" />
            {busy ? t('communityDetail.saving') : t('communityDetail.saveChanges')}
          </button>
        </div>
      </div>
    </section>
  )
}

// relativeTime — "2 days ago" / "5h ago" / etc. Intentionally local
// to this file since it's only used here; if a second page needs it
// we'll lift to a shared util.
function relativeTime(iso: string, locale: Locale): string {
  const d = new Date(iso)
  const ms = Date.now() - d.getTime()
  const s = Math.floor(ms / 1000)
  if (s < 60) return `${s}s ago`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const days = Math.floor(h / 24)
  if (days < 7) return `${days}d ago`
  if (days < 30) return `${Math.floor(days / 7)}w ago`
  return fmtDate(d, locale)
}

// Step-23 — pricing helpers (dollars ↔ cents) for the metadata
// editor's pricing section. Empty / NaN inputs become 0 cents,
// which the backend treats as "free for that plan".
function dollarsToCents(raw: string): number {
  const v = parseFloat((raw || '').trim())
  if (!isFinite(v) || v <= 0) return 0
  return Math.round(v * 100)
}

function centsToDollarStr(cents?: number): string {
  if (!cents || cents <= 0) return ''
  const v = cents / 100
  return v === Math.floor(v) ? v.toFixed(0) : v.toFixed(2)
}

// ────────────────────────────────────────────────────────────────────
// Owners (mig 0032) — primary + co-owners + Invite Expert button.
//
// The admin can invite any verified expert to ANY community thanks to
// the admin-override path in requirePrimaryOwner on the backend. The
// invitation goes through the same /me/communities/:id/invitations
// route as the mobile flow; the backend's role check accepts admins
// implicitly.
// ────────────────────────────────────────────────────────────────────
type OwnerEntry = {
  userId: number
  name: string
  email: string
  expertId?: string
  isPrimary: boolean
}
type OwnersResponse = {
  primary?: {
    userId: number
    name: string
    email: string
    expertId?: string
  } | null
  coOwners?: Array<{
    userId: number
    name: string
    email: string
    expertId?: string
    grantedBy?: number
    grantedAt?: string
  }>
}

function OwnersSection({
  communityId,
  communityName,
}: {
  communityId: string
  communityName: string
}) {
  const { t } = useI18n()
  const [owners, setOwners] = useState<OwnerEntry[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [removing, setRemoving] = useState<number | null>(null)
  const [showInvite, setShowInvite] = useState(false)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<OwnersResponse>(
        `/communities/${communityId}/owners`,
      )
      const out: OwnerEntry[] = []
      if (res.primary) {
        out.push({
          userId: res.primary.userId,
          name: res.primary.name,
          email: res.primary.email,
          expertId: res.primary.expertId,
          isPrimary: true,
        })
      }
      for (const c of res.coOwners ?? []) {
        out.push({ ...c, isPrimary: false })
      }
      setOwners(out)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [communityId])

  async function removeCoOwner(userId: number, name: string) {
    if (
      !confirm(
        t('communityDetail.removeCoOwnerConfirm', {
          name,
          community: communityName,
        }),
      )
    )
      return
    setRemoving(userId)
    try {
      await api.delete(`/me/communities/${communityId}/owners/${userId}`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setRemoving(null)
    }
  }

  return (
    <section>
      <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
        <h2 className="text-sm font-semibold text-slate-300 flex items-center gap-2">
          <Crown className="w-4 h-4 text-amber-300" />
          {t('communityDetail.ownersCount', { count: owners.length })}
        </h2>
        <button
          onClick={() => setShowInvite(true)}
          className="inline-flex items-center gap-1.5 h-8 px-3 rounded-md bg-cyan-500 hover:bg-cyan-400 text-midnight-500 text-xs font-bold"
        >
          <UserPlus className="w-3.5 h-3.5" />
          {t('communityDetail.inviteExpert')}
        </button>
      </div>

      {error && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs mb-2">
          {error}
        </div>
      )}

      {loading && owners.length === 0 ? (
        <p className="text-slate-500 text-sm">{t('communityDetail.loadingOwners')}</p>
      ) : owners.length === 0 ? (
        <p className="text-slate-500 text-sm">{t('communityDetail.noOwnersYet')}</p>
      ) : (
        <ul className="space-y-2">
          {owners.map((o) => (
            <li
              key={o.userId}
              className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-3 flex items-center gap-3"
            >
              <div
                className={`w-10 h-10 rounded-full flex items-center justify-center font-bold ring-1 ${
                  o.isPrimary
                    ? 'bg-amber-500/15 text-amber-300 ring-amber-500/30'
                    : 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30'
                }`}
              >
                {(o.name || o.email).charAt(0).toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-white truncate">
                  {o.name || o.email.split('@')[0]}
                </p>
                <p className="text-xs text-slate-500 truncate">{o.email}</p>
              </div>
              {o.isPrimary ? (
                <span className="px-2 py-0.5 rounded-md bg-amber-500/15 text-amber-300 ring-1 ring-amber-500/30 text-[10px] font-bold uppercase tracking-wider">
                  {t('communityDetail.primary')}
                </span>
              ) : (
                <>
                  <span className="px-2 py-0.5 rounded-md bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/30 text-[10px] font-bold uppercase tracking-wider">
                    {t('communityDetail.coOwner')}
                  </span>
                  <button
                    onClick={() => removeCoOwner(o.userId, o.name || o.email)}
                    disabled={removing === o.userId}
                    title={t('communityDetail.removeCoOwnerTooltip')}
                    className="p-1.5 rounded-md hover:bg-rose-500/10 text-slate-500 hover:text-rose-300 disabled:opacity-50"
                  >
                    {removing === o.userId ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <Trash2 className="w-4 h-4" />
                    )}
                  </button>
                </>
              )}
            </li>
          ))}
        </ul>
      )}

      {showInvite && (
        <InviteExpertModal
          communityId={communityId}
          communityName={communityName}
          existingOwnerExpertIds={
            new Set(owners.map((o) => o.expertId).filter(Boolean) as string[])
          }
          onClose={() => setShowInvite(false)}
          onInvited={async () => {
            setShowInvite(false)
            // No row to add yet — invitation is `pending` until the
            // invitee accepts. Owners list doesn't change. Refresh
            // anyway in case the WS event already fired the accept
            // on a fast invitee.
            await load()
          }}
        />
      )}
    </section>
  )
}

// ────────────────────────────────────────────────────────────────────
// InviteExpertModal — searchable picker of platform experts.
// Mirrors the mobile InviteExpertScreen but in admin colors.
// ────────────────────────────────────────────────────────────────────
type ExpertProfile = {
  id: string
  name: string
  expertise: string
  subscriberCount?: number
}

function InviteExpertModal({
  communityId,
  communityName,
  existingOwnerExpertIds,
  onClose,
  onInvited,
}: {
  communityId: string
  communityName: string
  existingOwnerExpertIds: Set<string>
  onClose: () => void
  onInvited: () => void
}) {
  const { t } = useI18n()
  const [experts, setExperts] = useState<ExpertProfile[]>([])
  const [q, setQ] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [sendingId, setSendingId] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    async function go() {
      setLoading(true)
      try {
        const res = await api.get<{ experts: ExpertProfile[] }>('/experts')
        if (!cancelled) setExperts(res.experts ?? [])
      } catch (e) {
        if (!cancelled) setError((e as Error).message)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    go()
    return () => {
      cancelled = true
    }
  }, [])

  // Esc to close.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const filtered = experts.filter((e) => {
    if (existingOwnerExpertIds.has(e.id)) return false
    if (!q) return true
    const hay = `${e.name.toLowerCase()} ${e.expertise.toLowerCase()}`
    return hay.includes(q.toLowerCase())
  })

  async function send(e: ExpertProfile) {
    if (sendingId) return
    setSendingId(e.id)
    setError(null)
    try {
      await api.post(
        `/me/communities/${communityId}/invitations`,
        { invitedExpertId: e.id },
      )
      onInvited()
    } catch (err: any) {
      setError(err?.message ?? t('communityDetail.inviteFailed', { name: e.name }))
    } finally {
      setSendingId(null)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        onClick={onClose}
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
      />
      {/* Dialog */}
      <div className="relative w-full max-w-lg bg-midnight-700 ring-1 ring-white/10 rounded-xl shadow-xl flex flex-col max-h-[80vh]">
        <div className="flex items-start justify-between p-5 border-b border-white/[0.06]">
          <div>
            <p className="text-[10px] font-bold tracking-[0.08em] uppercase text-slate-500">
              {t('communityDetail.inviteExpert')}
            </p>
            <h3 className="text-lg font-extrabold tracking-tight text-white mt-1 truncate">
              {communityName}
            </h3>
            <p className="text-xs text-slate-400 mt-1">
              {t('communityDetail.inviteModalSubtitle')}
            </p>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-md hover:bg-white/[0.04] text-slate-400 hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-4 border-b border-white/[0.06]">
          <div className="relative">
            <Search className="w-4 h-4 absolute start-3 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none" />
            <input
              type="text"
              autoFocus
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder={t('communityDetail.searchExperts')}
              className="w-full h-9 ps-9 pe-3 rounded-md bg-white/[0.03] ring-1 ring-inset ring-white/[0.06] text-sm text-white placeholder:text-slate-500 focus:outline-none focus:ring-cyan-500/40 focus:ring-2"
            />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-3">
          {loading ? (
            <div className="flex items-center justify-center py-12 text-slate-400 text-sm">
              <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('communityDetail.loadingExperts')}
            </div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-slate-500 text-sm">
              {existingOwnerExpertIds.size > 0 && q === ''
                ? t('communityDetail.allExpertsOwners')
                : t('communityDetail.noMatchingExperts')}
            </div>
          ) : (
            <ul className="space-y-2">
              {filtered.map((e) => (
                <li
                  key={e.id}
                  className="rounded-lg bg-white/[0.02] ring-1 ring-white/5 p-3 flex items-center gap-3"
                >
                  <div className="w-9 h-9 rounded-full bg-amber-500/15 ring-1 ring-amber-500/30 flex items-center justify-center text-amber-300 font-bold">
                    <Sparkles className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-white truncate">
                      {e.name}
                    </p>
                    {e.expertise && (
                      <p className="text-xs text-slate-500 truncate">
                        {e.expertise}
                      </p>
                    )}
                  </div>
                  <button
                    onClick={() => send(e)}
                    disabled={sendingId !== null}
                    className="inline-flex items-center gap-1 h-7 px-3 rounded-md bg-cyan-500 hover:bg-cyan-400 text-midnight-500 text-xs font-bold disabled:opacity-50"
                  >
                    {sendingId === e.id ? (
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    ) : (
                      <Check className="w-3.5 h-3.5" />
                    )}
                    {t('communityDetail.invite')}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {error && (
          <div className="p-3 border-t border-white/[0.06] text-xs text-rose-300 bg-rose-500/5">
            {error}
          </div>
        )}
      </div>
    </div>
  )
}
