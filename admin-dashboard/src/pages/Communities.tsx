import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  RefreshCw,
  Plus,
  Users as UsersIcon,
  FileText,
  Crown,
  Trash2,
  X,
  Lock,
  Globe,
  Tag,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'

// Backend shape — see repositories.AdminCommunityRow.
//
// Step-19 (mig 0019, items 2.13–2.18) extended this with description /
// rules / cover / isPublic / category / tags. The dashboard surfaces
// them so admins can review + edit without dropping into psql.
type AdminCommunity = {
  id: string
  name: string
  tagline?: string
  description?: string
  rules?: string
  coverUrl?: string
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

type ListResponse = { communities: AdminCommunity[] }

/**
 * Communities — admin CRUD over the platform's regional/topic groups.
 *
 * Distinct from the Community Proposals page (which is for reviewing
 * expert-submitted requests). This page is for direct admin
 * management — list every community, create new, edit name/owner,
 * delete. Click a row → detail page with members + posts.
 */
export default function Communities() {
  const { t } = useI18n()
  const [rows, setRows] = useState<AdminCommunity[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showCreate, setShowCreate] = useState(false)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<ListResponse>('/admin/communities')
      setRows(res.communities ?? [])
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  async function deleteCommunity(c: AdminCommunity) {
    if (!confirm(t('communities.deleteConfirm', { name: c.name }))) return
    try {
      await api.delete(`/admin/communities/${c.id}`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    }
  }

  useEffect(() => {
    load()
  }, [])

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-white">{t('communities.title')}</h1>
          <p className="text-sm text-slate-400 mt-1">
            {t('communities.subtitle')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={load}
            disabled={loading}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 ring-1 ring-white/10 disabled:opacity-50"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            {t('common.refresh')}
          </button>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 ring-1 ring-cyan-500/30 font-medium"
          >
            <Plus className="w-4 h-4" />
            {t('communities.newCommunity')}
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-4 py-3 text-rose-300 text-sm">
          {error}
        </div>
      )}

      {/* ── Cards grid ──────────────────────────────────────────── */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {rows.length === 0 && !loading && (
          <p className="text-slate-500 text-sm col-span-full text-center py-10">
            {t('communities.empty')}
          </p>
        )}
        {rows.map((c) => (
          <CommunityCard
            key={c.id}
            community={c}
            onDelete={() => deleteCommunity(c)}
          />
        ))}
      </div>
      {loading && (
        <p className="text-xs text-slate-500 text-center">{t('common.loading')}</p>
      )}

      {showCreate && (
        <CreateCommunityModal
          onClose={() => setShowCreate(false)}
          onCreated={() => {
            setShowCreate(false)
            load()
          }}
        />
      )}
    </div>
  )
}

function CommunityCard({
  community: c,
  onDelete,
}: {
  community: AdminCommunity
  onDelete: () => void
}) {
  const navigate = useNavigate()
  const { t } = useI18n()
  const hasOwner = !!c.ownerId
  // Whole card → /communities/:id via onClick. We can't use a <Link>
  // wrapper here because the card already contains an inner Link to
  // /users/:id (the owner row), and nested <a> tags are invalid HTML.
  // The inner Link + delete button each call stopPropagation so a
  // click on either doesn't also navigate to the community detail.
  // Cmd/Ctrl/Shift/Alt-clicks bypass navigation so power-users can
  // open in a new tab if they want.
  function handleCardClick(e: React.MouseEvent) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    navigate(`/communities/${c.id}`)
  }
  return (
    <div
      onClick={handleCardClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') navigate(`/communities/${c.id}`)
      }}
      className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 overflow-hidden hover:bg-white/[0.04] hover:ring-cyan-500/20 transition-colors cursor-pointer"
    >
      {/* Cover banner — falls back to a flat region-tinted strip
          when no cover_url is set so the layout doesn't shift. */}
      {c.coverUrl ? (
        <div
          className="h-20 bg-cover bg-center"
          style={{ backgroundImage: `url("${absoluteUrl(c.coverUrl)}")` }}
        />
      ) : (
        <div className="h-2 bg-gradient-to-r from-cyan-500/30 via-cyan-500/10 to-transparent" />
      )}
      <div className="flex items-start gap-3 p-4">
        <div
          className={`w-12 h-12 rounded-xl flex items-center justify-center font-bold text-lg shrink-0 ring-1 ${
            c.regionCode === 'GL' || !c.regionCode
              ? 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30'
              : c.regionCode === 'US'
              ? 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30'
              : 'bg-gold-500/15 text-gold-300 ring-gold-500/30'
          }`}
        >
          {(c.regionCode || c.name).charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-bold text-white truncate">{c.name}</p>
              <p className="text-[11px] font-mono text-slate-500 truncate">
                {c.id}
                {c.regionCode ? ` · ${c.regionCode}` : ''}
              </p>
            </div>
            <button
              onClick={(e) => {
                e.stopPropagation()
                onDelete()
              }}
              className="p-1 rounded-md hover:bg-rose-500/15 text-slate-500 hover:text-rose-300"
              title={t('communities.deleteTooltip')}
            >
              <Trash2 className="w-3.5 h-3.5" />
            </button>
          </div>
          {c.tagline && (
            <p className="mt-1 text-xs text-slate-400 line-clamp-2">
              {c.tagline}
            </p>
          )}
          {/* Step-19 — privacy + category badges. Both are static
              quick-glance info; full edit lives on the detail page. */}
          <div className="mt-2 flex items-center gap-1.5 flex-wrap">
            {c.isPublic ? (
              <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold bg-emerald-500/15 text-emerald-300 ring-1 ring-emerald-500/30">
                <Globe className="w-3 h-3" />
                {t('communities.public')}
              </span>
            ) : (
              <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold bg-gold-500/15 text-gold-300 ring-1 ring-gold-500/30">
                <Lock className="w-3 h-3" />
                {t('communities.private')}
              </span>
            )}
            {c.category && (
              <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/30">
                {c.category}
              </span>
            )}
            {c.tags && c.tags.length > 0 && (
              <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold bg-white/5 text-slate-400 ring-1 ring-white/10">
                <Tag className="w-3 h-3" />
                {c.tags.length}
              </span>
            )}
          </div>
          <div className="mt-3 flex items-center gap-3 text-xs">
            <span className="flex items-center gap-1 text-slate-400">
              <UsersIcon className="w-3 h-3" />
              {c.memberCount}
            </span>
            <span className="flex items-center gap-1 text-slate-400">
              <FileText className="w-3 h-3" />
              {c.postCount}
            </span>
            {hasOwner ? (
              <Link
                to={`/users/${c.ownerId}`}
                // stopPropagation so clicking the owner pill goes to
                // the user profile, NOT the community detail (which the
                // outer card click handler would otherwise hijack).
                onClick={(e) => e.stopPropagation()}
                className="flex items-center gap-1 text-cyan-300 hover:text-cyan-200 ms-auto truncate"
                title={c.ownerEmail}
              >
                <Crown className="w-3 h-3 text-gold-400" />
                <span className="truncate max-w-[8rem]">{c.ownerName}</span>
              </Link>
            ) : (
              <span className="ms-auto text-rose-300 text-[10px] font-bold">
                {t('communities.noOwner')}
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

function CreateCommunityModal({
  onClose,
  onCreated,
}: {
  onClose: () => void
  onCreated: () => void
}) {
  const { t } = useI18n()
  const [id, setId] = useState('')
  const [name, setName] = useState('')
  const [tagline, setTagline] = useState('')
  const [regionCode, setRegionCode] = useState('')
  const [ownerId, setOwnerId] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit() {
    setError(null)
    setSubmitting(true)
    try {
      await api.post('/admin/communities', {
        id: id.trim(),
        name: name.trim(),
        tagline: tagline.trim(),
        regionCode: regionCode.trim().toUpperCase(),
        ownerId: ownerId.trim() ? Number(ownerId) : 0,
      })
      onCreated()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-md rounded-xl bg-midnight-700 ring-1 ring-white/10 p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-bold text-white">{t('communities.createTitle')}</h2>
          <button
            onClick={onClose}
            className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="space-y-3">
          <Field label={t('communities.fieldIdSlug')}>
            <input
              value={id}
              onChange={(e) => setId(e.target.value.toLowerCase())}
              placeholder="c_halal_etf"
              className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 font-mono"
            />
          </Field>
          <Field label={t('communities.fieldName')}>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t('communities.phName')}
              className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
            />
          </Field>
          <Field label={t('communities.fieldTaglineOptional')}>
            <input
              value={tagline}
              onChange={(e) => setTagline(e.target.value)}
              placeholder={t('communities.phTagline')}
              className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
            />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t('communities.fieldRegionCode')}>
              <input
                value={regionCode}
                onChange={(e) => setRegionCode(e.target.value)}
                placeholder="GL / US / SA / AE"
                className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 uppercase"
              />
            </Field>
            <Field label={t('communities.fieldOwnerIdOptional')}>
              <input
                value={ownerId}
                onChange={(e) => setOwnerId(e.target.value)}
                placeholder={t('communities.phOwnerId')}
                className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200"
              />
            </Field>
          </div>
          {error && (
            <p className="text-xs text-rose-300">{error}</p>
          )}
          <div className="flex items-center justify-end gap-2 pt-2">
            <button
              onClick={onClose}
              className="px-3 py-2 rounded-md text-sm text-slate-300 hover:bg-white/5"
            >
              {t('common.cancel')}
            </button>
            <button
              onClick={submit}
              disabled={submitting || !id || !name}
              className="px-4 py-2 rounded-md text-sm font-medium bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 ring-1 ring-cyan-500/30 disabled:opacity-50"
            >
              {submitting ? t('communities.creating') : t('communities.create')}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({
  label,
  children,
}: {
  label: string
  children: React.ReactNode
}) {
  return (
    <label className="block">
      <p className="text-[11px] text-slate-400 mb-1 font-medium">{label}</p>
      {children}
    </label>
  )
}

// absoluteUrl — turn a server-relative `/uploads/images/x.jpg` into
// an absolute URL pointing at the API host so the dashboard's
// dev-time browser can fetch it cross-origin. The `api.client`
// already knows the base; we strip its trailing `/api` and prepend
// it to relative paths.
export function absoluteUrl(maybeRelative: string): string {
  if (!maybeRelative) return ''
  if (
    maybeRelative.startsWith('http://') ||
    maybeRelative.startsWith('https://')
  ) {
    return maybeRelative
  }
  // Same env var the api client reads (see api/client.ts).
  const base =
    (import.meta.env.VITE_API_BASE_URL as string | undefined) ??
    'http://localhost:8080/api'
  return base.replace(/\/api$/, '') + maybeRelative
}
