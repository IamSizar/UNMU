// Pulse items list. The same page serves three routes:
//   /pulse            all items, with a status filter
//   /pulse/review     only items waiting for review/approval (status in_review)
//   /pulse/schedule   only scheduled items
// Every list has the four states the design rules ask for: loading skeleton,
// content, friendly error with Retry, and a designed empty state.

import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { AlertTriangle, Inbox, Plus } from 'lucide-react'
import { ApiError } from '../../api/client'
import {
  PULSE_SLOTS,
  PULSE_STATUSES,
  pulseApi,
  type PulseItem,
  type PulseSlot,
  type PulseStatus,
} from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import {
  MarkerBadge,
  PULSE_CARD,
  PULSE_GHOST_BTN,
  PULSE_INPUT,
  PULSE_PRIMARY_BTN,
  SkeletonRows,
  StatusBadge,
  fmtDateTime,
  hasRole,
  itemTitle,
  usePulseMe,
} from './pulseUi'

type Variant = 'all' | 'review' | 'schedule'

const PAGE_SIZE = 30

const HEADINGS: Record<Variant, { title: TranslationKey; subtitle: TranslationKey }> = {
  all: { title: 'pulse.title', subtitle: 'pulse.subtitle' },
  review: { title: 'pulse.reviewTitle', subtitle: 'pulse.reviewSubtitle' },
  schedule: { title: 'pulse.scheduleTitle', subtitle: 'pulse.scheduleSubtitle' },
}

const FIXED_STATUS: Partial<Record<Variant, PulseStatus>> = {
  review: 'in_review',
  schedule: 'scheduled',
}

export default function PulseItems({ variant = 'all' }: { variant?: Variant }) {
  const { t, locale } = useI18n()
  const navigate = useNavigate()
  const { me } = usePulseMe()

  const fixedStatus = FIXED_STATUS[variant]
  const [status, setStatus] = useState<PulseStatus | ''>('')
  const [slot, setSlot] = useState<PulseSlot | ''>('')
  const [date, setDate] = useState('')

  const [items, setItems] = useState<PulseItem[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const effectiveStatus = fixedStatus ?? status

  // reset=true replaces the list (filters changed / retry); false appends a page.
  const load = useCallback(
    async (reset: boolean, offset: number) => {
      if (reset) setLoading(true)
      else setLoadingMore(true)
      setError(null)
      try {
        const res = await pulseApi.list({
          status: effectiveStatus,
          slot,
          date: date || undefined,
          limit: PAGE_SIZE,
          offset,
        })
        setItems((prev) => (reset ? res.items : [...prev, ...res.items]))
        setHasMore(res.hasMore)
      } catch (e) {
        setError(e instanceof ApiError && e.status === 403 ? t('pulse.noAccess') : t('pulse.error.load'))
      } finally {
        setLoading(false)
        setLoadingMore(false)
      }
    },
    [effectiveStatus, slot, date, t],
  )

  useEffect(() => {
    load(true, 0)
  }, [load])

  const heading = HEADINGS[variant]
  const canCreate = me ? hasRole(me, 'editor') : false
  const filtered = Boolean(effectiveStatus || slot || date)

  return (
    <div className="max-w-6xl mx-auto space-y-5">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold text-fg">{t(heading.title)}</h1>
          <p className="text-sm text-fg-muted mt-1">{t(heading.subtitle)}</p>
        </div>
        {canCreate && (
          <Link to="/pulse/items/new" className={PULSE_PRIMARY_BTN}>
            <Plus className="w-4 h-4" />
            {t('pulse.new')}
          </Link>
        )}
      </div>

      {/* ── Filters ─────────────────────────────────────────────── */}
      <div className="flex items-center gap-3 flex-wrap">
        {!fixedStatus && (
          <div
            role="group"
            className="flex items-center gap-1 p-1 rounded-full bg-white/5 ring-1 ring-line flex-wrap"
          >
            {(['', ...PULSE_STATUSES] as (PulseStatus | '')[]).map((s) => (
              <button
                key={s || 'all'}
                onClick={() => setStatus(s)}
                aria-pressed={status === s}
                className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
                  status === s ? 'bg-white text-slate-900 shadow-sm' : 'text-fg-muted hover:text-fg'
                }`}
              >
                {s ? t(`pulse.status.${s}` as TranslationKey) : t('pulse.filter.all')}
              </button>
            ))}
          </div>
        )}
        <select
          aria-label={t('pulse.col.slot')}
          value={slot}
          onChange={(e) => setSlot(e.target.value as PulseSlot | '')}
          className={`${PULSE_INPUT} !w-auto`}
        >
          <option value="">{t('pulse.filter.allSlots')}</option>
          {PULSE_SLOTS.map((s) => (
            <option key={s} value={s}>
              {t(`pulse.slot.${s}` as TranslationKey)}
            </option>
          ))}
        </select>
        <input
          type="date"
          aria-label={t('pulse.filter.date')}
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className={`${PULSE_INPUT} !w-auto`}
        />
        {date && (
          <button onClick={() => setDate('')} className="text-xs text-fg-muted hover:text-fg underline">
            {t('pulse.filter.all')}
          </button>
        )}
      </div>

      {/* ── List ────────────────────────────────────────────────── */}
      <div className={`${PULSE_CARD} overflow-hidden`}>
        {loading ? (
          <SkeletonRows />
        ) : error ? (
          <div className="flex flex-col items-center gap-3 py-14 px-6 text-center">
            <AlertTriangle className="w-8 h-8 text-rose-400" />
            <p className="text-sm text-fg-muted max-w-sm">{error}</p>
            <button onClick={() => load(true, 0)} className={PULSE_GHOST_BTN}>
              {t('pulse.retry')}
            </button>
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-14 px-6 text-center">
            <Inbox className="w-8 h-8 text-fg-subtle" />
            <p className="text-sm font-medium text-fg">{t('pulse.empty.title')}</p>
            <p className="text-sm text-fg-muted max-w-sm">
              {filtered ? t('pulse.empty.filtered') : t('pulse.empty.body')}
            </p>
            {canCreate && !filtered && (
              <Link to="/pulse/items/new" className={PULSE_PRIMARY_BTN}>
                <Plus className="w-4 h-4" />
                {t('pulse.new')}
              </Link>
            )}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="text-xs text-fg-subtle bg-white/[0.02]">
              <tr>
                <th scope="col" className="text-start px-4 py-3 font-medium">{t('pulse.col.date')}</th>
                <th scope="col" className="text-start px-4 py-3 font-medium">{t('pulse.col.slot')}</th>
                <th scope="col" className="text-start px-4 py-3 font-medium">{t('pulse.col.title')}</th>
                <th scope="col" className="text-start px-4 py-3 font-medium hidden md:table-cell">{t('pulse.col.type')}</th>
                <th scope="col" className="text-start px-4 py-3 font-medium">{t('pulse.col.status')}</th>
                <th scope="col" className="text-start px-4 py-3 font-medium hidden lg:table-cell">{t('pulse.col.updated')}</th>
              </tr>
            </thead>
            <tbody>
              {items.map((it) => (
                <tr
                  key={it.id}
                  onClick={() => navigate(`/pulse/items/${it.id}`)}
                  className="border-t border-line hover:bg-white/[0.04] cursor-pointer"
                >
                  <td className="px-4 py-3 whitespace-nowrap text-fg-muted">{it.pulseDate}</td>
                  <td className="px-4 py-3 whitespace-nowrap">{t(`pulse.slot.${it.slot}` as TranslationKey)}</td>
                  <td className="px-4 py-3 max-w-md">
                    <Link
                      to={`/pulse/items/${it.id}`}
                      onClick={(e) => e.stopPropagation()}
                      className="font-medium text-fg hover:underline line-clamp-2"
                    >
                      {itemTitle(it, locale)}
                    </Link>
                  </td>
                  <td className="px-4 py-3 hidden md:table-cell text-fg-muted">
                    {t(`pulse.class.${it.classification}` as TranslationKey)}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <StatusBadge status={it.status} />
                      <MarkerBadge kind={it.changeKind} />
                    </div>
                  </td>
                  <td className="px-4 py-3 hidden lg:table-cell text-fg-subtle whitespace-nowrap">
                    {fmtDateTime(it.updatedAt, locale)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {hasMore && !loading && !error && (
        <div className="text-center">
          <button
            onClick={() => load(false, items.length)}
            disabled={loadingMore}
            className={PULSE_GHOST_BTN}
          >
            {loadingMore ? t('pulse.loading') : t('pulse.loadMore')}
          </button>
        </div>
      )}
    </div>
  )
}
