import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  History,
  LifeBuoy,
  Loader2,
  RefreshCw,
  Send,
  XCircle,
} from 'lucide-react'
import { api } from '../api/client'
import { useRealtime } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate, fmtTime as fmtTimeHelper } from '../i18n/datefmt'
import type { Locale } from '../i18n/translations'

/**
 * Support — built-in user ↔ admin chat (mig 0029).
 *
 *   /support           → inbox (this component, no :id param)
 *   /support/:id       → thread detail (same component, :id present)
 *
 * Doing both in one file keeps the realtime sub + inbox refresh
 * coordinated — when a new message arrives the inbox auto-refreshes
 * and the thread (if open) appends it live.
 */

type Thread = {
  id: number
  userId: number
  userName: string
  userEmail: string
  status: 'open' | 'closed'
  lastMessageAt: string
  lastMessageRole?: string
  lastMessageBody?: string
  unreadAdmin: number
  unreadUser: number
  createdAt: string
  // Mig 0030 — single pinned message per thread.
  pinnedMessageId?: number | null
}

type Message = {
  id: number
  threadId: number
  senderUserId: number
  senderRole: 'user' | 'admin'
  senderName?: string
  body: string
  createdAt: string
  // Mig 0030 — non-null when the message has been edited / soft-deleted.
  editedAt?: string | null
  deletedAt?: string | null
}

export default function Support() {
  const { id } = useParams<{ id: string }>()
  if (id) return <ThreadView threadId={parseInt(id, 10)} />
  return <Inbox />
}

// ────────────────────────────────────────────────────────────────────
// Inbox: list of threads, newest activity first, unread on top
// ────────────────────────────────────────────────────────────────────
function Inbox() {
  const { t, locale } = useI18n()
  const navigate = useNavigate()
  const [status, setStatus] = useState<'open' | 'closed' | 'all'>('open')
  const [rows, setRows] = useState<Thread[]>([])
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setErr(null)
    try {
      const qs = status === 'all' ? '' : `?status=${status}`
      const res = await api.get<{ threads: Thread[] }>(
        `/admin/support/threads${qs}`,
      )
      setRows(res.threads ?? [])
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  // Reload on status filter change + realtime support events.
  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status])

  useRealtime(
    ['support_message_sent', 'support_thread_closed'],
    () => load(),
  )

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <LifeBuoy className="w-6 h-6 text-cyan-300" />
            {t('support.inboxTitle')}
          </h1>
          <p className="text-sm text-slate-400 mt-1">
            {t('support.inboxSubtitle')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {(['open', 'closed', 'all'] as const).map((s) => (
            <button
              key={s}
              onClick={() => setStatus(s)}
              className={`px-3 py-1.5 rounded-md text-xs font-bold ring-1 transition-colors ${
                status === s
                  ? 'bg-cyan-500/20 text-cyan-300 ring-cyan-500/40'
                  : 'bg-white/[0.02] text-slate-300 ring-white/10 hover:ring-white/20'
              }`}
            >
              {t(`support.filter${s.charAt(0).toUpperCase() + s.slice(1)}` as Parameters<typeof t>[0])}
            </button>
          ))}
          <button
            onClick={load}
            className="p-1.5 rounded-md bg-white/[0.02] ring-1 ring-white/10 hover:ring-white/20 text-slate-300"
            title={t('common.refresh')}
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {err && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs">
          {err}
        </div>
      )}

      {loading && rows.length === 0 ? (
        <div className="flex items-center gap-2 text-slate-400 text-sm py-12 justify-center">
          <Loader2 className="w-4 h-4 animate-spin" />
          {t('support.loading')}
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-12 text-center text-sm text-slate-400">
          {status === 'open' ? t('support.emptyOpen') : status === 'closed' ? t('support.emptyClosed') : t('support.emptyAll')}
        </div>
      ) : (
        <ul className="space-y-2">
          {rows.map((row) => (
            <li key={row.id}>
              <button
                onClick={() => navigate(`/support/${row.id}`)}
                className="w-full text-start rounded-xl bg-white/[0.02] ring-1 ring-white/5 hover:ring-cyan-500/30 transition px-4 py-3 flex items-start gap-3"
              >
                <div className="w-9 h-9 rounded-full bg-cyan-500/20 ring-1 ring-cyan-500/40 flex items-center justify-center shrink-0 text-cyan-200 text-xs font-bold">
                  {initials(row.userName || row.userEmail)}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-semibold text-white truncate">
                      {row.userName || row.userEmail.split('@')[0]}
                    </p>
                    <span className="text-[10px] text-slate-500 truncate">
                      {row.userEmail}
                    </span>
                    {row.status === 'closed' && (
                      <span className="text-[9px] uppercase tracking-wider px-1.5 py-0.5 rounded bg-slate-500/15 text-slate-400 ring-1 ring-slate-500/30">
                        {t('support.closedBadge')}
                      </span>
                    )}
                    <span className="ms-auto text-[10px] text-slate-500">
                      {fmtTime(row.lastMessageAt, locale)}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400 mt-0.5 line-clamp-1">
                    {row.lastMessageRole === 'admin' && (
                      <span className="text-slate-500">{t('support.youPrefix')}</span>
                    )}
                    {row.lastMessageBody || t('support.noMessages')}
                  </p>
                </div>
                {row.unreadAdmin > 0 && (
                  <span className="shrink-0 inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-full bg-cyan-500 text-[10px] font-bold text-midnight-500">
                    {row.unreadAdmin}
                  </span>
                )}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Thread detail: chat UI for one user, with reply composer + close
// ────────────────────────────────────────────────────────────────────
function ThreadView({ threadId }: { threadId: number }) {
  const { t } = useI18n()
  const navigate = useNavigate()
  const [thread, setThread] = useState<Thread | null>(null)
  const [messages, setMessages] = useState<Message[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [composer, setComposer] = useState('')
  const [sending, setSending] = useState(false)
  const [closing, setClosing] = useState(false)
  const scrollerRef = useRef<HTMLDivElement | null>(null)

  async function load() {
    setLoading(true)
    setErr(null)
    try {
      const res = await api.get<{ thread: Thread; messages: Message[] }>(
        `/admin/support/threads/${threadId}`,
      )
      setThread(res.thread)
      setMessages(res.messages ?? [])
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [threadId])

  // Auto-scroll to bottom on first load + any new message append.
  useEffect(() => {
    const el = scrollerRef.current
    if (!el) return
    el.scrollTop = el.scrollHeight
  }, [messages.length])

  // Live updates — append incoming messages (admin replies typed from
  // another tab AND user messages typed on the phone). De-duped on id.
  useRealtime(['support_message_sent'], (ev) => {
    const d = (ev as { data: Record<string, unknown> }).data
    const incomingThreadId = Number(d.threadId ?? 0)
    if (incomingThreadId !== threadId) return
    const incomingId = Number(d.messageId ?? 0)
    if (!incomingId) return
    setMessages((cur) => {
      if (cur.some((m) => m.id === incomingId)) return cur
      const newMsg: Message = {
        id: incomingId,
        threadId: incomingThreadId,
        senderUserId: Number(d.senderUserId ?? 0),
        senderRole: (d.senderRole as 'user' | 'admin') ?? 'user',
        body: String(d.body ?? ''),
        createdAt: String(d.createdAt ?? new Date().toISOString()),
      }
      return [...cur, newMsg]
    })
  })

  useRealtime(['support_thread_closed'], (ev) => {
    const d = (ev as { data: Record<string, unknown> }).data
    if (Number(d.threadId ?? 0) !== threadId) return
    setThread((t) => (t ? { ...t, status: 'closed' } : t))
  })

  // Mig 0030 — edit / delete update the bubble in place rather than
  // appending a new one. Both events carry the same `messageId` so
  // we just map over the list and rewrite the matching row.
  useRealtime(['support_message_edited'], (ev) => {
    const d = (ev as { data: Record<string, unknown> }).data
    if (Number(d.threadId ?? 0) !== threadId) return
    const mid = Number(d.messageId ?? 0)
    if (!mid) return
    setMessages((cur) =>
      cur.map((m) =>
        m.id === mid
          ? {
              ...m,
              body: String(d.body ?? m.body),
              editedAt: String(d.editedAt ?? new Date().toISOString()),
            }
          : m,
      ),
    )
  })

  useRealtime(['support_message_deleted'], (ev) => {
    const d = (ev as { data: Record<string, unknown> }).data
    if (Number(d.threadId ?? 0) !== threadId) return
    const mid = Number(d.messageId ?? 0)
    if (!mid) return
    setMessages((cur) =>
      cur.map((m) =>
        m.id === mid
          ? {
              ...m,
              deletedAt: String(d.deletedAt ?? new Date().toISOString()),
            }
          : m,
      ),
    )
  })

  useRealtime(['support_thread_pinned', 'support_thread_unpinned'], (ev) => {
    const d = (ev as { data: Record<string, unknown> }).data
    if (Number(d.threadId ?? 0) !== threadId) return
    const pin = d.pinnedMessageId == null ? null : Number(d.pinnedMessageId)
    setThread((t) => (t ? { ...t, pinnedMessageId: pin } : t))
  })

  async function editMessage(msg: Message) {
    const next = prompt(t('support.editPrompt'), msg.body)
    if (next == null) return
    const text = next.trim()
    if (!text || text === msg.body) return
    try {
      const res = await api.patch<{ message: Message }>(
        `/admin/support/messages/${msg.id}`,
        { body: text },
      )
      setMessages((cur) =>
        cur.map((m) => (m.id === msg.id ? res.message : m)),
      )
    } catch (e) {
      setErr((e as Error).message)
    }
  }

  async function deleteMessage(msg: Message) {
    const ok = confirm(t('support.deleteConfirm'))
    if (!ok) return
    try {
      await api.delete(`/admin/support/messages/${msg.id}`)
      setMessages((cur) =>
        cur.map((m) =>
          m.id === msg.id
            ? { ...m, deletedAt: new Date().toISOString() }
            : m,
        ),
      )
    } catch (e) {
      setErr((e as Error).message)
    }
  }

  async function togglePin(msg: Message) {
    const alreadyPinned = thread?.pinnedMessageId === msg.id
    try {
      await api.post(
        `/admin/support/threads/${threadId}/pin`,
        { messageId: alreadyPinned ? 0 : msg.id },
      )
      setThread((t) =>
        t ? { ...t, pinnedMessageId: alreadyPinned ? null : msg.id } : t,
      )
    } catch (e) {
      setErr((e as Error).message)
    }
  }

  async function send() {
    const body = composer.trim()
    if (!body || sending) return
    setSending(true)
    setErr(null)
    try {
      const res = await api.post<{ message: Message }>(
        `/admin/support/threads/${threadId}/messages`,
        { body },
      )
      setComposer('')
      // Optimistic append — but the WS echo on `support_message_sent`
      // can race ahead of our HTTP response (pg_notify fires in
      // microseconds, the HTTP round-trip takes milliseconds). If the
      // echo already added this exact message id, skip — otherwise we
      // get a visible duplicate bubble that only clears on full
      // refresh.
      setMessages((cur) => {
        if (cur.some((m) => m.id === res.message.id)) return cur
        return [...cur, res.message]
      })
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setSending(false)
    }
  }

  async function close() {
    if (closing) return
    const ok = confirm(t('support.closeConfirm'))
    if (!ok) return
    setClosing(true)
    try {
      await api.post(`/admin/support/threads/${threadId}/close`, {})
      setThread((t) => (t ? { ...t, status: 'closed' } : t))
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setClosing(false)
    }
  }

  if (loading && !thread) {
    return (
      <div className="flex items-center gap-2 text-slate-400 text-sm py-12 justify-center">
        <Loader2 className="w-4 h-4 animate-spin" />
        {t('support.loadingThread')}
      </div>
    )
  }
  if (!thread) {
    return (
      <div className="text-rose-300 text-sm">
        {err || t('support.threadNotFound')}
      </div>
    )
  }

  return (
    <div className="flex flex-col h-[calc(100vh-9rem)]">
      <div className="flex items-center gap-3 pb-3 border-b border-white/5">
        <button
          onClick={() => navigate('/support')}
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('support.backToInbox')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </button>
        <div className="w-9 h-9 rounded-full bg-cyan-500/20 ring-1 ring-cyan-500/40 flex items-center justify-center text-cyan-200 text-xs font-bold">
          {initials(thread.userName || thread.userEmail)}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-bold text-white truncate">
            {thread.userName || thread.userEmail.split('@')[0]}
          </p>
          <p className="text-[10px] text-slate-500 truncate">
            {thread.userEmail} · {thread.status === 'closed' ? t('support.statusClosed') : t('support.statusOpen')}
          </p>
        </div>
        {/* Deep-link to the audit log filtered for this thread. The
            audit page reads ?targetId/?targetKind from the URL, auto-
            switches to the Support tab, and shows a clearable chip so
            it's obvious how the admin got there. */}
        <button
          onClick={() =>
            navigate(
              `/audit-log?targetId=${threadId}&targetKind=support_thread`,
            )
          }
          className="px-3 py-1.5 rounded-md bg-white/[0.04] hover:bg-white/[0.08] ring-1 ring-white/10 hover:ring-white/20 text-slate-300 text-xs font-bold flex items-center gap-1.5"
          title={t('support.viewAuditTitle')}
        >
          <History className="w-3.5 h-3.5" />
          {t('support.audit')}
        </button>
        <button
          onClick={close}
          disabled={closing || thread.status === 'closed'}
          className="px-3 py-1.5 rounded-md bg-rose-500/15 hover:bg-rose-500/25 ring-1 ring-rose-500/30 text-rose-300 text-xs font-bold disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1.5"
        >
          <XCircle className="w-3.5 h-3.5" />
          {thread.status === 'closed' ? t('support.closed') : t('support.close')}
        </button>
      </div>

      {/* Mig 0030 — sticky pinned-message strip. Only renders when a
          pin is set (admin clicks the pin icon on any bubble). */}
      {thread.pinnedMessageId != null && (
        <PinnedStrip
          messageId={thread.pinnedMessageId}
          messages={messages}
          onUnpin={() => togglePin({ id: thread.pinnedMessageId! } as Message)}
        />
      )}

      <div
        ref={scrollerRef}
        className="flex-1 overflow-y-auto py-4 space-y-2 pe-1"
      >
        {messages.length === 0 ? (
          <p className="text-center text-xs text-slate-500 mt-8">
            {t('support.noMessages')}
          </p>
        ) : (
          messages.map((m) => (
            <Bubble
              key={m.id}
              msg={m}
              isPinned={thread.pinnedMessageId === m.id}
              onEdit={() => editMessage(m)}
              onDelete={() => deleteMessage(m)}
              onTogglePin={() => togglePin(m)}
            />
          ))
        )}
      </div>

      {err && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs mb-2">
          {err}
        </div>
      )}

      <div className="flex items-end gap-2 pt-3 border-t border-white/5">
        <textarea
          value={composer}
          onChange={(e) => setComposer(e.target.value)}
          rows={2}
          maxLength={2000}
          placeholder={
            thread.status === 'closed'
              ? t('support.composerReopen')
              : t('support.composerReply')
          }
          className="flex-1 resize-none px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 focus:outline-none focus:ring-cyan-500/40"
          onKeyDown={(e) => {
            // Enter to send, Shift+Enter for newline.
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              send()
            }
          }}
        />
        <button
          onClick={send}
          disabled={!composer.trim() || sending}
          className="h-10 px-4 rounded-md bg-cyan-500 text-midnight-500 font-bold text-sm hover:bg-cyan-400 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
        >
          {sending ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            <Send className="w-4 h-4" />
          )}
          {t('support.send')}
        </button>
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Chat bubble — admin replies right (cyan), user messages left (slate)
// ────────────────────────────────────────────────────────────────────
function Bubble({
  msg,
  isPinned,
  onEdit,
  onDelete,
  onTogglePin,
}: {
  msg: Message
  isPinned: boolean
  onEdit: () => void
  onDelete: () => void
  onTogglePin: () => void
}) {
  const { t, locale } = useI18n()
  const isAdmin = msg.senderRole === 'admin'
  const isDeleted = !!msg.deletedAt
  const isEdited = !!msg.editedAt && !isDeleted
  return (
    <div
      className={`group flex ${
        isAdmin ? 'justify-end' : 'justify-start'
      } items-end gap-2`}
    >
      {/* Actions appear on hover, on the OUTSIDE of the bubble so the
          bubble corners stay clean. Admin can edit / delete / pin
          every message regardless of sender (per the spec). Deleted
          messages hide the Edit action since the body is irrelevant
          now. */}
      {isAdmin && (
        <BubbleActions
          showEdit={!isDeleted}
          showDelete={!isDeleted}
          isPinned={isPinned}
          onEdit={onEdit}
          onDelete={onDelete}
          onTogglePin={onTogglePin}
        />
      )}
      <div
        className={`max-w-[78%] rounded-2xl px-3.5 py-2 text-sm ${
          isDeleted
            ? 'bg-white/[0.03] text-slate-500 ring-1 ring-white/10 italic'
            : isAdmin
              ? 'bg-cyan-500 text-midnight-500 rounded-ee-md'
              : 'bg-white/[0.04] text-slate-100 ring-1 ring-white/10 rounded-es-md'
        } ${isPinned ? 'ring-2 ring-amber-400/40' : ''}`}
      >
        {isPinned && !isDeleted && (
          <p
            className={`text-[9px] font-bold mb-1 ${
              isAdmin ? 'text-midnight-500/70' : 'text-amber-300'
            }`}
          >
            📌 {t('support.pinned')}
          </p>
        )}
        <p className="whitespace-pre-wrap leading-relaxed">
          {isDeleted ? t('support.messageDeleted') : msg.body}
        </p>
        <p
          className={`text-[10px] mt-1 font-bold ${
            isDeleted
              ? 'text-slate-600'
              : isAdmin
                ? 'text-midnight-500/70'
                : 'text-slate-500'
          }`}
        >
          {fmtTime(msg.createdAt, locale)}
          {isEdited && <span className="ms-1 italic">{t('support.edited')}</span>}
        </p>
      </div>
      {/* Mirror the actions on the left side for user messages so the
          row layout stays balanced (user-on-left, admin-on-right). */}
      {!isAdmin && (
        <BubbleActions
          showEdit={!isDeleted}
          showDelete={!isDeleted}
          isPinned={isPinned}
          onEdit={onEdit}
          onDelete={onDelete}
          onTogglePin={onTogglePin}
          mirror
        />
      )}
    </div>
  )
}

// Hover-only action group — Edit / Delete / Pin. Only renders the
// admin's affordances; the user's mobile app surfaces its own subset
// (own-message edit only).
function BubbleActions({
  showEdit,
  showDelete,
  isPinned,
  onEdit,
  onDelete,
  onTogglePin,
  mirror,
}: {
  showEdit: boolean
  showDelete: boolean
  isPinned: boolean
  onEdit: () => void
  onDelete: () => void
  onTogglePin: () => void
  mirror?: boolean
}) {
  const { t } = useI18n()
  return (
    <div
      className={`opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1 ${
        mirror ? 'order-2' : ''
      }`}
    >
      <button
        onClick={onTogglePin}
        title={isPinned ? t('support.unpin') : t('support.pin')}
        className={`w-7 h-7 rounded-md flex items-center justify-center ring-1 ${
          isPinned
            ? 'bg-amber-500/20 ring-amber-500/40 text-amber-300'
            : 'bg-white/[0.04] ring-white/10 text-slate-400 hover:text-amber-300 hover:bg-amber-500/15 hover:ring-amber-500/30'
        }`}
      >
        📌
      </button>
      {showEdit && (
        <button
          onClick={onEdit}
          title={t('support.editMessage')}
          className="w-7 h-7 rounded-md bg-white/[0.04] ring-1 ring-white/10 text-slate-400 hover:text-cyan-300 hover:ring-cyan-500/30 flex items-center justify-center text-xs"
        >
          ✎
        </button>
      )}
      {showDelete && (
        <button
          onClick={onDelete}
          title={t('support.deleteMessage')}
          className="w-7 h-7 rounded-md bg-white/[0.04] ring-1 ring-white/10 text-slate-400 hover:text-rose-300 hover:ring-rose-500/30 flex items-center justify-center text-xs"
        >
          🗑
        </button>
      )}
    </div>
  )
}

// Sticky pinned-message strip at the top of the thread view. Click
// the pin icon (or the unpin button) to clear.
function PinnedStrip({
  messageId,
  messages,
  onUnpin,
}: {
  messageId: number
  messages: Message[]
  onUnpin: () => void
}) {
  const { t } = useI18n()
  const msg = messages.find((m) => m.id === messageId)
  const body = msg
    ? msg.deletedAt
      ? t('support.deletedMessage')
      : msg.body
    : t('support.pinnedMessage')
  return (
    <div className="px-3 py-2 bg-amber-500/10 ring-1 ring-amber-500/30 rounded-md mb-2 flex items-start gap-2">
      <div className="mt-0.5 text-amber-300">📌</div>
      <div className="flex-1 min-w-0">
        <p className="text-[9px] font-bold text-amber-300 tracking-wider">
          {t('support.pinned')}
        </p>
        <p
          className={`text-xs mt-0.5 line-clamp-2 ${
            msg?.deletedAt ? 'italic text-slate-500' : 'text-slate-200'
          }`}
        >
          {body}
        </p>
      </div>
      <button
        onClick={onUnpin}
        title={t('support.unpin')}
        className="text-amber-300/80 hover:text-amber-200 px-1 text-xs"
      >
        ✕
      </button>
    </div>
  )
}

// ── helpers ─────────────────────────────────────────────────────────
function initials(name: string) {
  const s = name.trim()
  if (!s) return '?'
  const parts = s.split(/\s+|@|\./)
  if (parts.length === 1 || !parts[1]) return parts[0]![0]!.toUpperCase()
  return (parts[0]![0]! + parts[1]![0]!).toUpperCase()
}

function fmtTime(iso: string, locale: Locale) {
  try {
    const d = new Date(iso)
    const today = new Date()
    const sameDay =
      d.getFullYear() === today.getFullYear() &&
      d.getMonth() === today.getMonth() &&
      d.getDate() === today.getDate()
    if (sameDay) {
      return fmtTimeHelper(d, locale)
    }
    return fmtDate(d, locale)
  } catch {
    return ''
  }
}

