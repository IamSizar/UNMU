// Basic Pulse analytics (spec §18): how many people opened Pulse and its items,
// how many read to the end, saved or shared, how many came back on another day,
// and a per-item table so items can be compared (most opened, most saved...).
// Everything is computed on the server from the events the app reports.

import { useCallback, useEffect, useState } from 'react'
import { AlertTriangle, BarChart3 } from 'lucide-react'
import { pulseApi, type PulseAnalytics as Analytics } from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import { PULSE_CARD, PULSE_GHOST_BTN, PULSE_INPUT, SkeletonRows, pulseToday } from './pulseUi'

const MAX_DAYS = 92
const DAY_MS = 24 * 60 * 60 * 1000

function shiftDays(date: string, days: number): string {
  return new Date(new Date(`${date}T00:00:00Z`).getTime() + days * DAY_MS).toISOString().slice(0, 10)
}

/** True when from <= to and the range is at most MAX_DAYS days. */
export function isValidRange(from: string, to: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) return false
  const span = (new Date(`${to}T00:00:00Z`).getTime() - new Date(`${from}T00:00:00Z`).getTime()) / DAY_MS
  return span >= 0 && span <= MAX_DAYS
}

const pct = (x: number) => `${Math.round(x * 100)}%`

export default function PulseAnalytics() {
  const { t } = useI18n()
  const today = pulseToday()
  const [from, setFrom] = useState(shiftDays(today, -6))
  const [to, setTo] = useState(today)
  const [data, setData] = useState<Analytics | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)

  const rangeOk = isValidRange(from, to)

  const load = useCallback(async () => {
    if (!rangeOk) return
    setLoading(true)
    setError(false)
    try {
      setData(await pulseApi.analytics(from, to))
    } catch {
      setError(true)
    } finally {
      setLoading(false)
    }
  }, [from, to, rangeOk])

  useEffect(() => {
    load()
  }, [load])

  const tiles: { key: TranslationKey; value: string }[] = data
    ? [
        { key: 'pulse.analytics.dayViews', value: String(data.dayViews) },
        { key: 'pulse.analytics.itemOpens', value: String(data.itemOpens) },
        { key: 'pulse.analytics.uniqueReaders', value: String(data.uniqueReaders) },
        { key: 'pulse.analytics.readCompletion', value: pct(data.readCompletion) },
        { key: 'pulse.analytics.saves', value: String(data.saves) },
        { key: 'pulse.analytics.shares', value: String(data.shares) },
        { key: 'pulse.analytics.returnRate', value: pct(data.returnRate) },
      ]
    : []
  const maxOpens = data ? Math.max(1, ...data.items.map((i) => i.opens)) : 1

  return (
    <div className="max-w-6xl mx-auto space-y-5">
      <div>
        <h1 className="text-2xl font-semibold text-fg">{t('pulse.analytics.title')}</h1>
        <p className="text-sm text-fg-muted mt-1">{t('pulse.analytics.subtitle')}</p>
      </div>

      <div className="flex items-end gap-3 flex-wrap">
        <label className="block">
          <span className="block text-[11px] font-semibold uppercase tracking-wider text-fg-subtle mb-1.5">
            {t('pulse.analytics.from')}
          </span>
          <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} className={PULSE_INPUT} />
        </label>
        <label className="block">
          <span className="block text-[11px] font-semibold uppercase tracking-wider text-fg-subtle mb-1.5">
            {t('pulse.analytics.to')}
          </span>
          <input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} className={PULSE_INPUT} />
        </label>
        {!rangeOk && (
          <span role="alert" className="text-xs text-rose-400 pb-2.5">
            {t('pulse.analytics.badRange')}
          </span>
        )}
      </div>

      {error ? (
        <div className={`${PULSE_CARD} flex flex-col items-center gap-3 py-14 px-6 text-center`}>
          <AlertTriangle className="w-8 h-8 text-rose-400" />
          <p className="text-sm text-fg-muted">{t('pulse.error.load')}</p>
          <button onClick={load} className={PULSE_GHOST_BTN}>
            {t('pulse.retry')}
          </button>
        </div>
      ) : loading || !data ? (
        <div className={PULSE_CARD}>
          <SkeletonRows rows={4} />
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            {tiles.map((tile) => (
              <div key={tile.key} className={`${PULSE_CARD} p-4`}>
                <p className="text-xs text-fg-subtle">{t(tile.key)}</p>
                <p className="text-2xl font-semibold text-fg mt-1 tabular-nums">{tile.value}</p>
              </div>
            ))}
          </div>

          <div className={`${PULSE_CARD} overflow-hidden`}>
            <h2 className="px-4 pt-4 text-sm font-semibold text-fg">{t('pulse.analytics.perItem')}</h2>
            {data.items.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-12 px-6 text-center">
                <BarChart3 className="w-8 h-8 text-fg-subtle" />
                <p className="text-sm text-fg-muted">{t('pulse.analytics.noData')}</p>
              </div>
            ) : (
              <table className="w-full text-sm mt-2">
                <thead className="text-xs text-fg-subtle">
                  <tr>
                    <th scope="col" className="text-start px-4 py-2 font-medium">{t('pulse.col.title')}</th>
                    <th scope="col" className="text-start px-4 py-2 font-medium w-48">{t('pulse.analytics.opens')}</th>
                    <th scope="col" className="text-end px-4 py-2 font-medium">{t('pulse.analytics.reads')}</th>
                    <th scope="col" className="text-end px-4 py-2 font-medium">{t('pulse.analytics.saves')}</th>
                    <th scope="col" className="text-end px-4 py-2 font-medium">{t('pulse.analytics.shares')}</th>
                  </tr>
                </thead>
                <tbody>
                  {data.items.map((it) => (
                    <tr key={it.itemId} className="border-t border-line">
                      <td className="px-4 py-2.5 max-w-xs">
                        <p className="text-fg truncate">{it.title}</p>
                        <p className="text-xs text-fg-subtle">
                          {it.date} · {t(`pulse.slot.${it.slot}` as TranslationKey)}
                        </p>
                      </td>
                      <td className="px-4 py-2.5">
                        <div className="flex items-center gap-2">
                          <div className="h-2 flex-1 rounded-full bg-white/5 overflow-hidden" aria-hidden="true">
                            <div
                              className="h-full rounded-full bg-[#00B7B7]"
                              style={{ width: `${Math.round((it.opens / maxOpens) * 100)}%` }}
                            />
                          </div>
                          <span className="tabular-nums text-fg w-8 text-end">{it.opens}</span>
                        </div>
                      </td>
                      <td className="px-4 py-2.5 text-end tabular-nums text-fg-muted">{it.reads}</td>
                      <td className="px-4 py-2.5 text-end tabular-nums text-fg-muted">{it.saves}</td>
                      <td className="px-4 py-2.5 text-end tabular-nums text-fg-muted">{it.shares}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}
    </div>
  )
}
