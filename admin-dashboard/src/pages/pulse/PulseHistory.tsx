// Change log + stored versions of one Pulse item (spec §14-15): who did what
// and when, and every earlier version of the text.

import { useEffect, useState } from 'react'
import { pulseApi, type PulseChangeLogEntry, type PulseVersion } from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import { fmtDateTime } from './pulseUi'

export default function PulseHistory({ itemId, refreshKey }: { itemId: number; refreshKey: number }) {
  const { t, locale } = useI18n()
  const [events, setEvents] = useState<PulseChangeLogEntry[] | null>(null)
  const [versions, setVersions] = useState<PulseVersion[] | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let cancelled = false
    setFailed(false)
    Promise.all([pulseApi.events(itemId), pulseApi.versions(itemId)])
      .then(([e, v]) => {
        if (cancelled) return
        setEvents(e.events)
        setVersions(v.versions)
      })
      .catch(() => !cancelled && setFailed(true))
    return () => {
      cancelled = true
    }
  }, [itemId, refreshKey])

  if (failed) return <p className="text-sm text-rose-400">{t('pulse.error.load')}</p>
  if (events === null || versions === null) {
    return <p className="text-sm text-fg-subtle">{t('pulse.loading')}</p>
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-sm font-semibold text-fg mb-3">{t('pulse.history.log')}</h3>
        {events.length === 0 ? (
          <p className="text-sm text-fg-subtle">{t('pulse.history.empty')}</p>
        ) : (
          <ol className="space-y-3">
            {events.map((e) => (
              <li key={e.id} className="flex gap-3 text-sm">
                <span className="mt-1.5 h-2 w-2 rounded-full bg-[#00B7B7] shrink-0" aria-hidden="true" />
                <div className="min-w-0">
                  <p className="text-fg">
                    <span className="font-medium">{e.actorEmail || t('pulse.history.system')}</span>{' '}
                    <span className="text-fg-muted">{t(`pulse.event.${e.action}` as TranslationKey)}</span>
                  </p>
                  {e.note && <p className="text-fg-muted italic break-words">“{e.note}”</p>}
                  <p className="text-xs text-fg-subtle">{fmtDateTime(e.createdAt, locale)}</p>
                </div>
              </li>
            ))}
          </ol>
        )}
      </div>

      <div>
        <h3 className="text-sm font-semibold text-fg mb-3">{t('pulse.history.versions')}</h3>
        <ul className="space-y-2">
          {versions.map((v) => (
            <li key={v.version} className="rounded-lg ring-1 ring-line bg-canvas">
              <details>
                <summary className="cursor-pointer px-3 py-2 text-sm text-fg flex items-center justify-between gap-3">
                  <span className="font-medium">{t('pulse.history.version', { n: v.version })}</span>
                  <span className="text-xs text-fg-subtle">
                    {v.reason} · {fmtDateTime(v.createdAt, locale)}
                  </span>
                </summary>
                <div className="px-3 pb-3 space-y-2 text-sm">
                  <p className="text-fg" dir="ltr" lang="en">{v.snapshot.titleEn || '—'}</p>
                  <p className="text-fg" dir="rtl" lang="ar">{v.snapshot.titleAr || '—'}</p>
                  <p className="text-fg-muted" dir="ltr" lang="en">{v.snapshot.summaryEn}</p>
                  <p className="text-fg-muted" dir="rtl" lang="ar">{v.snapshot.summaryAr}</p>
                </div>
              </details>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
