import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  Search,
  RefreshCw,
  Eye,
  EyeOff,
  FileText,
  Video,
  Film,
  Bookmark,
  Clock,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate, fmtTime } from '../i18n/datefmt'

// Mirrors the admin posts row shape from the Go side.
//
// Step-20 (mig 0020) added `status` + `publishAt` for drafts and
// scheduling. The dashboard surfaces them as a status badge on each
// row and a column header.
type AdminPost = {
  id: number
  authorId: number
  authorName: string
  authorEmail: string
  authorRole: string
  postType: 'article' | 'video' | 'reel'
  title?: string | null
  body: string
  likes: number
  comments: number
  isHidden: boolean
  createdAt: string
  visibility: 'public' | 'subscribers_only'
  status?: 'draft' | 'scheduled' | 'published'
  publishAt?: string | null
}

type ListResponse = { posts: AdminPost[] }

type TypeFilter = '' | 'article' | 'video' | 'reel'
type TargetFilter = '' | 'expert' | 'community'
type StatusFilter = 'all' | 'active' | 'hidden'
type SortKey = 'newest' | 'oldest' | 'most_liked' | 'most_commented'

/**
 * Posts — unified moderation table for articles, videos, and reels.
 *
 * Replaces the old Articles + Videos mock pages. Drives every admin
 * post-related action on the platform: filter by type / author / status,
 * search, sort, and drill into a single post via /posts/:id.
 *
 * Optional `authorId` prop lets a parent (e.g. UserDetail) pre-filter
 * the table to a specific user without us needing a second route.
 *
 * Optional `defaultType` + `lockType` let the dedicated Articles /
 * Videos / Reels pages reuse this table without duplicating the
 * fetch/filter/state machine. `lockType` also hides the type-pill row
 * so the page is visually focused on one content type.
 *
 * Optional `title` / `subtitle` override the default page header (the
 * Articles page wants "Articles", not "Posts").
 */
export default function Posts({
  authorId,
  defaultType = '',
  lockType = false,
  title,
  subtitle,
}: {
  authorId?: number
  defaultType?: TypeFilter
  lockType?: boolean
  title?: string
  subtitle?: string
}) {
  const { t } = useI18n()
  const [type, setType] = useState<TypeFilter>(defaultType)
  const [target, setTarget] = useState<TargetFilter>('')
  const [status, setStatus] = useState<StatusFilter>('all')
  const [sort, setSort] = useState<SortKey>('newest')
  const [query, setQuery] = useState('')
  const [rows, setRows] = useState<AdminPost[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Tiny debounce on the search box so we don't fire a request per
  // keystroke. 250ms feels instant but coalesces fast typing into one
  // server round-trip.
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [debouncedQuery, setDebouncedQuery] = useState('')
  useEffect(() => {
    if (searchTimer.current) clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => setDebouncedQuery(query), 250)
    return () => {
      if (searchTimer.current) clearTimeout(searchTimer.current)
    }
  }, [query])

  // Memoised query string so we don't rebuild it on every render and so
  // the useEffect dep is a single primitive comparison.
  const qs = useMemo(() => {
    const params = new URLSearchParams()
    if (type) params.set('type', type)
    if (target) params.set('target', target)
    if (status !== 'all') params.set('status', status)
    if (sort !== 'newest') params.set('sort', sort)
    if (debouncedQuery.trim()) params.set('q', debouncedQuery.trim())
    if (authorId) params.set('authorId', String(authorId))
    params.set('limit', '100')
    return params.toString()
  }, [type, target, status, sort, debouncedQuery, authorId])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<ListResponse>(`/admin/posts?${qs}`)
      setRows(res.posts ?? [])
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [qs])

  return (
    <div className="space-y-5">
      {!authorId && (
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-white">
              {title ?? t('posts.title')}
            </h1>
            <p className="text-sm text-slate-400 mt-1">
              {subtitle ?? t('posts.subtitle')}
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
      )}

      {/* ── Filters ──────────────────────────────────────────────── */}
      <div className="flex flex-wrap items-center gap-2">
        {/* Type pills (article / video / reel). Hidden when the parent
            already locked the type — the Articles + Videos pages render
            a focused view that doesn't let the user switch to another
            content kind. */}
        {!lockType && (
          <div className="flex items-center gap-1 bg-white/5 rounded-lg p-1 ring-1 ring-white/10">
            {([
              { v: '' as TypeFilter, label: t('posts.filter.all') },
              { v: 'article' as TypeFilter, label: t('posts.filter.articles') },
              { v: 'video' as TypeFilter, label: t('posts.filter.videos') },
              { v: 'reel' as TypeFilter, label: t('posts.filter.reels') },
            ]).map(({ v, label }) => (
              <button
                key={label}
                onClick={() => setType(v)}
                className={`px-2.5 py-1 rounded-md text-xs font-medium ${
                  type === v
                    ? 'bg-cyan-500/20 text-cyan-300 ring-1 ring-cyan-500/30'
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        )}

        {/* Target pills (expert / community) — Sprint-C step 11.
            Lets admins isolate community posts (forum-style) from
            expert posts (paywalled content). Uses the `target` query
            param wired into AdminPostFilter.TargetType. */}
        <div className="flex items-center gap-1 bg-white/5 rounded-lg p-1 ring-1 ring-white/10">
          {([
            { v: '' as TargetFilter, label: t('posts.target.all') },
            { v: 'expert' as TargetFilter, label: t('posts.target.expert') },
            { v: 'community' as TargetFilter, label: t('posts.target.community') },
          ]).map(({ v, label }) => (
            <button
              key={label}
              onClick={() => setTarget(v)}
              className={`px-2.5 py-1 rounded-md text-xs font-medium ${
                target === v
                  ? 'bg-fuchsia-500/20 text-fuchsia-300 ring-1 ring-fuchsia-500/30'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        <select
          value={status}
          onChange={(e) => setStatus(e.target.value as StatusFilter)}
          className="px-2.5 py-1.5 rounded-md bg-white/5 ring-1 ring-white/10 text-slate-300 text-xs"
        >
          <option value="all">{t('posts.status.allHidden')}</option>
          <option value="active">{t('posts.status.activeOnly')}</option>
          <option value="hidden">{t('posts.status.hiddenOnly')}</option>
        </select>

        <select
          value={sort}
          onChange={(e) => setSort(e.target.value as SortKey)}
          className="px-2.5 py-1.5 rounded-md bg-white/5 ring-1 ring-white/10 text-slate-300 text-xs"
        >
          <option value="newest">{t('posts.sort.newest')}</option>
          <option value="oldest">{t('posts.sort.oldest')}</option>
          <option value="most_liked">{t('posts.sort.mostLiked')}</option>
          <option value="most_commented">{t('posts.sort.mostCommented')}</option>
        </select>

        {/* Search */}
        <div className="ms-auto relative flex-1 min-w-[200px] max-w-md">
          <Search className="w-4 h-4 absolute start-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('posts.search.placeholder')}
            className="w-full ps-8 pe-3 py-1.5 rounded-md bg-midnight-700 ring-1 ring-white/10 text-sm text-slate-200 placeholder:text-slate-500"
          />
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-4 py-3 text-rose-300 text-sm">
          {error}
        </div>
      )}

      {/* ── Table ────────────────────────────────────────────────── */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="text-xs text-slate-500 bg-white/[0.02]">
            <tr>
              <th className="text-start px-4 py-3 font-medium w-16">{t('posts.col.id')}</th>
              <th className="text-start px-4 py-3 font-medium w-24">{t('posts.col.type')}</th>
              <th className="text-start px-4 py-3 font-medium">{t('posts.col.author')}</th>
              <th className="text-start px-4 py-3 font-medium">{t('posts.col.title')}</th>
              <th className="text-end px-4 py-3 font-medium w-16">❤</th>
              <th className="text-end px-4 py-3 font-medium w-16">💬</th>
              <th className="text-start px-4 py-3 font-medium w-32">{t('posts.col.date')}</th>
              <th className="text-start px-4 py-3 font-medium w-20">{t('posts.col.status')}</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && !loading && (
              <tr>
                <td colSpan={8} className="text-center py-10 text-slate-500">
                  {t('posts.empty')}
                </td>
              </tr>
            )}
            {rows.map((p) => (
              <PostRow key={p.id} post={p} />
            ))}
          </tbody>
        </table>
      </div>
      {loading && (
        <p className="text-xs text-slate-500 text-center">{t('common.loading')}</p>
      )}
    </div>
  )
}

function PostRow({ post }: { post: AdminPost }) {
  const { t, locale } = useI18n()
  const navigate = useNavigate()
  const TypeIcon = TYPE_ICON[post.postType] ?? FileText
  const excerpt = post.title?.trim()
    ? post.title
    : post.body.slice(0, 80) + (post.body.length > 80 ? '…' : '')
  // Clicking anywhere on the row drills into the post detail page
  // where likers + comments + stats live. The inner Link on the title
  // stays as a Link (not a span) so Cmd/Ctrl-click still opens the
  // post in a new tab — onRowClick won't fire when the user uses a
  // modifier because we ignore those event paths.
  function handleRowClick(e: React.MouseEvent) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    navigate(`/posts/${post.id}`)
  }
  return (
    <tr
      onClick={handleRowClick}
      className="border-t border-white/5 hover:bg-white/[0.04] cursor-pointer"
    >
      <td className="px-4 py-3 font-mono text-xs text-slate-400">#{post.id}</td>
      <td className="px-4 py-3">
        <span className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-white/5 ring-1 ring-white/10 text-xs text-slate-300">
          <TypeIcon className="w-3.5 h-3.5" />
          {post.postType}
        </span>
      </td>
      <td className="px-4 py-3">
        <div className="flex items-center gap-2 min-w-0">
          <div className="w-7 h-7 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 text-xs font-bold shrink-0">
            {(post.authorName || post.authorEmail || '?').charAt(0).toUpperCase()}
          </div>
          <div className="min-w-0">
            <p className="truncate text-slate-200 font-medium">
              {post.authorName || '—'}
            </p>
            {post.authorEmail && (
              <p className="truncate text-[11px] text-slate-500">{post.authorEmail}</p>
            )}
          </div>
        </div>
      </td>
      <td className="px-4 py-3">
        <Link
          to={`/posts/${post.id}`}
          className="block text-slate-200 hover:text-cyan-300 truncate max-w-[460px]"
        >
          {excerpt || <span className="text-slate-500 italic">{t('post.detail.empty')}</span>}
        </Link>
      </td>
      <td className="px-4 py-3 text-end text-slate-300">{post.likes}</td>
      <td className="px-4 py-3 text-end text-slate-300">{post.comments}</td>
      <td className="px-4 py-3 text-xs text-slate-400">
        {fmtDate(post.createdAt, locale)}{' '}
        <span className="text-slate-600">
          {fmtTime(post.createdAt, locale)}
        </span>
      </td>
      <td className="px-4 py-3">
        {post.status === 'draft' ? (
          <span
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-gold-500/15 text-gold-300 text-[10px] ring-1 ring-gold-500/30"
            title={t('posts.status.draftTooltip')}
          >
            <Bookmark className="w-3 h-3" /> {t('posts.status.draft')}
          </span>
        ) : post.status === 'scheduled' ? (
          <span
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-cyan-500/15 text-cyan-300 text-[10px] ring-1 ring-cyan-500/30"
            title={
              post.publishAt
                ? t('posts.status.scheduledFor', { date: new Date(post.publishAt).toLocaleString(locale) })
                : t('posts.status.scheduled')
            }
          >
            <Clock className="w-3 h-3" /> {t('posts.status.scheduled')}
          </span>
        ) : post.isHidden ? (
          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-rose-500/15 text-rose-300 text-[10px] ring-1 ring-rose-500/30">
            <EyeOff className="w-3 h-3" /> {t('posts.status.hidden')}
          </span>
        ) : (
          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-emerald-500/15 text-emerald-300 text-[10px] ring-1 ring-emerald-500/30">
            <Eye className="w-3 h-3" /> {t('posts.status.active')}
          </span>
        )}
      </td>
    </tr>
  )
}

const TYPE_ICON: Record<string, React.ComponentType<{ className?: string }>> = {
  article: FileText,
  video: Video,
  reel: Film,
}
