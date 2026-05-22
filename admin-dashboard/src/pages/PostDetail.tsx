import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  Eye,
  EyeOff,
  Trash2,
  RefreshCw,
  AlertTriangle,
  Heart,
  MessageSquare,
  Bookmark,
  Share2,
  Link as LinkIcon,
  AlertOctagon,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import type { TranslationKey } from '../i18n/translations'
import { fmtDate, fmtDateTime } from '../i18n/datefmt'

type AdminPost = {
  id: number
  authorId: number
  authorName: string
  postType: 'article' | 'video' | 'reel'
  title?: string | null
  body: string
  mediaUrl?: string | null
  coverUrl?: string | null
  tickers?: string[]
  likes: number
  comments: number
  isHidden: boolean
  createdAt: string
  updatedAt?: string
  visibility: 'public' | 'subscribers_only'
  status?: 'draft' | 'scheduled' | 'published'
  publishAt?: string | null
}

// Mig 0020 (item 4.16) — one snapshot row from `post_versions`.
type PostVersion = {
  id: number
  postId: number
  editorId?: number | null
  title?: string
  body: string
  tickers?: string[]
  editedAt: string
}
type HistoryResponse = { versions: PostVersion[] }

type Stats = {
  likes: number
  comments: number
  saves: number
  shares: number
  deepLinkOpens: number
  reelLoadFails: number
}

type Comment = {
  id: number
  postId: number
  authorId: number
  authorName: string
  body: string
  createdAt: string
}

// Mirrors backend `repositories.Liker` shape.
type Liker = {
  userId: number
  name: string
  email: string
  role: string
  expertId?: string
  likedAt: string
}

type DetailResponse = { post: AdminPost; stats: Stats }
type CommentsResponse = { comments: Comment[] }
type LikesResponse = { likes: Liker[] }

/**
 * PostDetail — `/posts/:id`.
 *
 * Single screen showing the full post (no subscription gate), every
 * stat from the moderation perspective, and the full thread of
 * comments. Three moderation actions live up top:
 *
 *   * Hide / Unhide (toggle is_hidden)
 *   * Delete post (hard delete + cascade)
 *   * Per-comment delete via the trash icon next to each row
 *
 * Every action audit-logs server-side and refreshes local state via a
 * `load()` call so the page is always coherent with the DB.
 */
export default function PostDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t, locale } = useI18n()

  const [post, setPost] = useState<AdminPost | null>(null)
  const [stats, setStats] = useState<Stats | null>(null)
  const [comments, setComments] = useState<Comment[]>([])
  const [likes, setLikes] = useState<Liker[]>([])
  const [versions, setVersions] = useState<PostVersion[]>([])
  const [loading, setLoading] = useState(false)
  const [actionBusy, setActionBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    if (!id) return
    setLoading(true)
    setError(null)
    try {
      // All three sub-resources fetched in parallel — keeps the detail
      // page cold-load fast on slow connections, since the largest
      // payload (comments) doesn't block the post header from rendering.
      // Mig 0020 (item 4.16) — pull edit history alongside the
      // standard detail payload. The history endpoint returns 403 for
      // non-owners + non-admins; we hit it as admin so it should
      // always return rows (or empty for never-edited posts).
      const [detail, cm, lk, hist] = await Promise.all([
        api.get<DetailResponse>(`/admin/posts/${id}`),
        api.get<CommentsResponse>(`/admin/posts/${id}/comments`),
        api.get<LikesResponse>(`/admin/posts/${id}/likes`),
        api
          .get<HistoryResponse>(`/posts/${id}/history`)
          .catch(() => ({ versions: [] })),
      ])
      setPost(detail.post)
      setStats(detail.stats)
      setComments(cm.comments ?? [])
      setLikes(lk.likes ?? [])
      setVersions(hist.versions ?? [])
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

  async function toggleHidden() {
    if (!post) return
    setActionBusy('hide')
    try {
      const path = post.isHidden ? 'unhide' : 'hide'
      await api.post(`/admin/posts/${post.id}/${path}`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  async function deletePost() {
    if (!post) return
    if (!confirm(t('post.confirm.delete', { id: post.id }))) return
    setActionBusy('delete')
    try {
      await api.delete(`/admin/posts/${post.id}`)
      navigate('/posts')
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  async function deleteComment(c: Comment) {
    if (!post) return
    if (!confirm(t('post.confirm.deleteComment', { author: c.authorName || t('postDetail.userFallback') }))) return
    setActionBusy(`comment-${c.id}`)
    try {
      await api.delete(`/admin/posts/${post.id}/comments/${c.id}`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  if (loading && !post) {
    return <p className="text-slate-500">{t('common.loading')}</p>
  }
  if (error && !post) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-4 py-3 text-rose-300 text-sm flex items-center gap-2">
        <AlertOctagon className="w-4 h-4" />
        {error}
      </div>
    )
  }
  if (!post) {
    return <p className="text-slate-500">{t('post.detail.notFound')}</p>
  }

  const title = post.title?.trim() || t('post.detail.noTitle')
  const bodyShown = post.body.trim()

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link
          to="/posts"
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </Link>
        <div className="flex-1 min-w-0">
          <p className="text-xs text-slate-500 font-mono">#{post.id} · {post.postType} · {post.visibility}</p>
          <h1 className="text-xl font-bold text-white truncate">{title}</h1>
        </div>
        <button
          onClick={load}
          disabled={loading}
          className="p-2 rounded-md bg-white/5 hover:bg-white/10 text-slate-300 disabled:opacity-50"
          title={t('common.refresh')}
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
        <button
          onClick={toggleHidden}
          disabled={actionBusy === 'hide'}
          className={`px-3 py-2 rounded-md text-sm font-medium ring-1 disabled:opacity-50 ${
            post.isHidden
              ? 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30 hover:bg-emerald-500/25'
              : 'bg-gold-500/15 text-gold-300 ring-gold-500/30 hover:bg-gold-500/25'
          }`}
        >
          {post.isHidden ? (
            <span className="flex items-center gap-1.5">
              <Eye className="w-4 h-4" /> {t('post.action.unhide')}
            </span>
          ) : (
            <span className="flex items-center gap-1.5">
              <EyeOff className="w-4 h-4" /> {t('post.action.hide')}
            </span>
          )}
        </button>
        <button
          onClick={deletePost}
          disabled={actionBusy === 'delete'}
          className="px-3 py-2 rounded-md text-sm font-medium bg-rose-500/15 text-rose-300 ring-1 ring-rose-500/30 hover:bg-rose-500/25 disabled:opacity-50"
        >
          <span className="flex items-center gap-1.5">
            <Trash2 className="w-4 h-4" /> {t('post.action.delete')}
          </span>
        </button>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      )}

      {/* ── Author + meta ───────────────────────────────────────── */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 flex items-center gap-3">
        <div className="w-10 h-10 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold">
          {post.authorName.charAt(0).toUpperCase() || '?'}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-slate-200 font-semibold">{post.authorName || '—'}</p>
          <p className="text-xs text-slate-500">
            {t('post.posted', { date: fmtDateTime(post.createdAt, locale) })}
          </p>
        </div>
        <Link
          to={`/users/${post.authorId}`}
          className="text-xs px-2.5 py-1 rounded-md bg-white/5 hover:bg-white/10 text-slate-300 ring-1 ring-white/10"
        >
          {t('common.viewAuthor')}
        </Link>
      </div>

      {/* ── Stats grid ──────────────────────────────────────────── */}
      {stats && (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <Stat icon={<Heart className="w-4 h-4" />} label={t('post.stat.likes')} value={stats.likes} tone="rose" />
          <Stat icon={<MessageSquare className="w-4 h-4" />} label={t('post.stat.comments')} value={stats.comments} tone="cyan" />
          <Stat icon={<Bookmark className="w-4 h-4" />} label={t('post.stat.saves')} value={stats.saves} tone="gold" />
          <Stat icon={<Share2 className="w-4 h-4" />} label={t('post.stat.shares')} value={stats.shares} tone="cyan" />
          <Stat icon={<LinkIcon className="w-4 h-4" />} label={t('post.stat.deepLinks')} value={stats.deepLinkOpens} tone="cyan" />
          <Stat icon={<AlertTriangle className="w-4 h-4" />} label={t('post.stat.reelFails')} value={stats.reelLoadFails} tone={stats.reelLoadFails > 0 ? 'rose' : 'emerald'} />
        </div>
      )}

      {/* ── Cover / media ───────────────────────────────────────── */}
      {post.coverUrl && (
        <div className="rounded-xl overflow-hidden ring-1 ring-white/10">
          <img src={resolveMedia(post.coverUrl)} alt={t('postDetail.coverAlt')} className="w-full max-h-[400px] object-cover" />
        </div>
      )}
      {post.mediaUrl && post.postType !== 'article' && (
        <video
          src={resolveMedia(post.mediaUrl)}
          controls
          className="w-full max-h-[480px] rounded-xl ring-1 ring-white/10 bg-black"
        />
      )}

      {/* ── Body ────────────────────────────────────────────────── */}
      {bodyShown && (
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
          <p className="text-slate-200 whitespace-pre-wrap leading-relaxed">{bodyShown}</p>
          {post.tickers && post.tickers.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-2">
              {post.tickers.map((t) => (
                <span
                  key={t}
                  className="px-2 py-0.5 rounded-md bg-cyan-500/10 text-cyan-300 ring-1 ring-cyan-500/30 text-xs font-bold"
                >
                  ${t}
                </span>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ── Likes ───────────────────────────────────────────────── */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
          <Heart className="w-4 h-4 text-rose-300" />
          {t('post.likedBy', { count: likes.length })}
        </h2>
        {likes.length === 0 ? (
          <p className="text-slate-500 text-sm">{t('post.likedBy.empty')}</p>
        ) : (
          <ul className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            {likes.map((l) => (
              <li
                key={l.userId}
                className="rounded-lg bg-white/[0.02] ring-1 ring-white/5 px-3 py-2 flex items-center gap-3"
              >
                <Link
                  to={`/users/${l.userId}`}
                  className="w-8 h-8 rounded-full bg-rose-500/15 ring-1 ring-rose-500/30 flex items-center justify-center text-rose-300 text-xs font-bold shrink-0 hover:bg-rose-500/25"
                  title={t('common.viewUser')}
                >
                  {(l.name || l.email || '?').charAt(0).toUpperCase()}
                </Link>
                <div className="flex-1 min-w-0">
                  <Link
                    to={`/users/${l.userId}`}
                    className="text-sm text-slate-200 font-medium truncate block hover:text-cyan-300"
                  >
                    {l.name || l.email.split('@')[0]}
                  </Link>
                  <p className="text-[11px] text-slate-500 truncate">
                    {l.email}
                    {/* Role suffix is keyed off the user's CURRENT role,
                        not a stale `expertId`. A user demoted from
                        EXPERT back to USER will keep their old expert_id
                        in the DB but their role will reflect reality —
                        we trust role here. */}
                    {roleSuffixKey(l.role) ? t(roleSuffixKey(l.role) as TranslationKey) : ''}
                  </p>
                </div>
                <span className="text-[10px] text-slate-500 shrink-0">
                  {fmtDate(l.likedAt, locale)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* ── Step-20 (item 4.16) — edit history ──────────────────── */}
      {versions.length > 0 && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">
            {t('postDetail.editHistory', { count: versions.length })}
          </h2>
          <ul className="space-y-2">
            {versions.map((v) => (
              <li
                key={v.id}
                className="rounded-lg bg-white/[0.02] ring-1 ring-white/5 px-3 py-2.5"
              >
                <div className="flex items-center gap-2 text-[11px] text-slate-500 mb-1">
                  <span>
                    {fmtDateTime(v.editedAt, locale)}
                  </span>
                  {v.editorId && (
                    <Link
                      to={`/users/${v.editorId}`}
                      className="text-cyan-300 hover:text-cyan-200 ms-1"
                    >
                      {t('postDetail.editor', { id: v.editorId })}
                    </Link>
                  )}
                </div>
                {v.title && (
                  <p className="text-sm font-bold text-white truncate">
                    {v.title}
                  </p>
                )}
                <p className="text-xs text-slate-300 line-clamp-3 whitespace-pre-line">
                  {v.body}
                </p>
                {v.tickers && v.tickers.length > 0 && (
                  <div className="mt-1.5 flex flex-wrap gap-1">
                    {v.tickers.map((t) => (
                      <span
                        key={t}
                        className="px-1.5 py-0.5 rounded text-[10px] bg-white/5 text-slate-400 ring-1 ring-white/10"
                      >
                        {t}
                      </span>
                    ))}
                  </div>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* ── Comments ────────────────────────────────────────────── */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3">
          {t('post.comments', { count: comments.length })}
        </h2>
        {comments.length === 0 && (
          <p className="text-slate-500 text-sm">{t('post.comments.empty')}</p>
        )}
        <ul className="space-y-2">
          {comments.map((c) => (
            <li
              key={c.id}
              className="rounded-lg bg-white/[0.02] ring-1 ring-white/5 px-3 py-2 flex items-start gap-3"
            >
              <Link
                to={`/users/${c.authorId}`}
                className="w-7 h-7 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 text-xs font-bold shrink-0 hover:bg-cyan-500/25"
                title={t('common.viewUser')}
              >
                {c.authorName?.charAt(0).toUpperCase() || '?'}
              </Link>
              <div className="flex-1 min-w-0">
                <p className="text-xs text-slate-500">
                  <Link
                    to={`/users/${c.authorId}`}
                    className="text-slate-300 font-medium hover:text-cyan-300"
                  >
                    {c.authorName || t('postDetail.userFallback')}
                  </Link>{' '}
                  · {fmtDateTime(c.createdAt, locale)}
                </p>
                <p className="text-sm text-slate-200 whitespace-pre-wrap">{c.body}</p>
              </div>
              <button
                onClick={() => deleteComment(c)}
                disabled={actionBusy === `comment-${c.id}`}
                className="p-1 rounded-md hover:bg-rose-500/15 text-slate-500 hover:text-rose-300 disabled:opacity-50"
                title={t('postDetail.deleteComment')}
              >
                <Trash2 className="w-4 h-4" />
              </button>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}

// ─── Helpers ─────────────────────────────────────────────────────────

function Stat({
  icon,
  label,
  value,
  tone,
}: {
  icon: React.ReactNode
  label: string
  value: number
  tone: 'cyan' | 'gold' | 'rose' | 'emerald'
}) {
  const TONE_CLASS: Record<typeof tone, string> = {
    cyan: 'text-cyan-300',
    gold: 'text-gold-300',
    rose: 'text-rose-300',
    emerald: 'text-emerald-300',
  }
  return (
    <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-3">
      <div className={`flex items-center gap-1.5 text-xs ${TONE_CLASS[tone]}`}>
        {icon}
        <span className="text-slate-400">{label}</span>
      </div>
      <p className="mt-1 text-xl font-bold text-white">{value}</p>
    </div>
  )
}

// roleSuffixKey — pick the translation key for the " · expert" / " · admin"
// role suffix off the user's CURRENT role string. Plain USER → '' (no
// suffix), so the row stays clean. SCHOLAR retired in migration 0013 —
// its case used to render " · scholar" but is no longer reachable.
// The key is resolved with t() at render so it localizes properly.
function roleSuffixKey(role: string): string {
  switch (role.toUpperCase()) {
    case 'EXPERT':
      return 'postDetail.roleSuffix.expert'
    case 'ADMIN':
      return 'postDetail.roleSuffix.admin'
    default:
      return ''
  }
}

// resolveMedia — backend serves relative `/uploads/...` paths; we
// rewrite them to absolute URLs against the configured API origin so
// the <img>/<video> tags can fetch them.
function resolveMedia(rel: string): string {
  if (!rel) return rel
  if (rel.startsWith('http://') || rel.startsWith('https://')) return rel
  const base =
    (import.meta.env.VITE_API_BASE_URL as string | undefined) ??
    'http://localhost:8080/api'
  // Strip the trailing /api segment to get the origin where /uploads lives.
  const origin = base.replace(/\/api\/?$/, '')
  return origin + rel
}
