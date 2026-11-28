// Who may write, review and approve Pulse content. Any staff member can see the
// list; only a system admin (users.role = ADMIN) can add or remove roles.
// System admins hold every role already and are not listed here.

import { useCallback, useEffect, useState } from 'react'
import { AlertTriangle, Trash2, Users } from 'lucide-react'
import { ApiError } from '../../api/client'
import { pulseApi, type PulseRole, type PulseStaffMember } from '../../api/pulse'
import { useI18n } from '../../i18n/I18nContext'
import type { TranslationKey } from '../../i18n/translations'
import {
  NoticeBanner,
  PULSE_CARD,
  PULSE_GHOST_BTN,
  PULSE_INPUT,
  PULSE_PRIMARY_BTN,
  SkeletonRows,
  fmtDateTime,
  useNotice,
  usePulseMe,
} from './pulseUi'

const ROLES: PulseRole[] = ['editor', 'reviewer', 'approver']

// Same rule the browser uses for type="email"; the server looks the user up by
// exact address, so a malformed one would simply not be found.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export default function PulseStaff() {
  const { t, locale } = useI18n()
  const { me } = usePulseMe()
  const { notice, show, clear } = useNotice()

  const [staff, setStaff] = useState<PulseStaffMember[] | null>(null)
  const [error, setError] = useState(false)
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<PulseRole>('editor')
  const [touched, setTouched] = useState(false)
  const [busy, setBusy] = useState(false)

  const isAdmin = me?.isAdmin === true
  const emailValid = EMAIL_RE.test(email.trim())

  const load = useCallback(async () => {
    setError(false)
    try {
      setStaff((await pulseApi.staff()).staff)
    } catch {
      setError(true)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  async function add() {
    setTouched(true)
    if (!emailValid) return
    setBusy(true)
    try {
      await pulseApi.addStaff(email.trim().toLowerCase(), role)
      setEmail('')
      setTouched(false)
      show('ok', t('pulse.staff.added'))
      await load()
    } catch (e) {
      show('error', e instanceof ApiError ? e.fields?.email || e.message : t('pulse.action.failed'))
    } finally {
      setBusy(false)
    }
  }

  async function remove(m: PulseStaffMember) {
    const label = `${t('pulse.staff.removeConfirm')}\n${m.email} · ${t(`pulse.role.${m.role}` as TranslationKey)}`
    if (!window.confirm(label)) return
    setBusy(true)
    try {
      await pulseApi.removeStaff(m.id)
      show('ok', t('pulse.staff.removed'))
      await load()
    } catch (e) {
      show('error', e instanceof ApiError ? e.message : t('pulse.action.failed'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div>
        <h1 className="text-2xl font-semibold text-fg">{t('pulse.staff.title')}</h1>
        <p className="text-sm text-fg-muted mt-1">{t('pulse.staff.subtitle')}</p>
        <p className="text-xs text-fg-subtle mt-1">{t('pulse.staff.adminNote')}</p>
      </div>

      <NoticeBanner notice={notice} onClose={clear} />

      {/* ── What each role does ─────────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {ROLES.map((r) => (
          <div key={r} className={`${PULSE_CARD} p-4`}>
            <p className="text-sm font-semibold text-fg">{t(`pulse.role.${r}` as TranslationKey)}</p>
            <p className="text-xs text-fg-muted mt-1">{t(`pulse.role.${r}Hint` as TranslationKey)}</p>
          </div>
        ))}
      </div>

      {/* ── Add ─────────────────────────────────────────────────── */}
      {isAdmin ? (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            add()
          }}
          className={`${PULSE_CARD} p-4 flex items-start gap-3 flex-wrap`}
          noValidate
        >
          <div className="flex-1 min-w-[220px]">
            <input
              type="email"
              inputMode="email"
              autoComplete="off"
              autoCapitalize="none"
              aria-label={t('pulse.staff.email')}
              placeholder={t('pulse.staff.email')}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className={PULSE_INPUT}
              dir="ltr"
            />
            {touched && !emailValid && (
              <span role="alert" className="block mt-1 text-xs text-rose-400">
                {t('pulse.staff.emailInvalid')}
              </span>
            )}
          </div>
          <select
            aria-label={t('pulse.staff.role')}
            value={role}
            onChange={(e) => setRole(e.target.value as PulseRole)}
            className={`${PULSE_INPUT} !w-auto`}
          >
            {ROLES.map((r) => (
              <option key={r} value={r}>
                {t(`pulse.role.${r}` as TranslationKey)}
              </option>
            ))}
          </select>
          <button type="submit" disabled={busy} className={PULSE_PRIMARY_BTN}>
            {t('pulse.staff.add')}
          </button>
        </form>
      ) : (
        me && <p className="text-xs text-fg-subtle">{t('pulse.staff.adminOnly')}</p>
      )}

      {/* ── List ────────────────────────────────────────────────── */}
      <div className={`${PULSE_CARD} overflow-hidden`}>
        {staff === null && !error ? (
          <SkeletonRows rows={3} />
        ) : error ? (
          <div className="flex flex-col items-center gap-3 py-12 px-6 text-center">
            <AlertTriangle className="w-8 h-8 text-rose-400" />
            <p className="text-sm text-fg-muted">{t('pulse.error.load')}</p>
            <button onClick={load} className={PULSE_GHOST_BTN}>
              {t('pulse.retry')}
            </button>
          </div>
        ) : staff && staff.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-12 px-6 text-center">
            <Users className="w-8 h-8 text-fg-subtle" />
            <p className="text-sm text-fg-muted max-w-sm">{t('pulse.staff.empty')}</p>
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="text-xs text-fg-subtle bg-white/[0.02]">
              <tr>
                <th scope="col" className="text-start px-4 py-3 font-medium">{t('pulse.staff.email')}</th>
                <th scope="col" className="text-start px-4 py-3 font-medium">{t('pulse.staff.role')}</th>
                <th scope="col" className="text-start px-4 py-3 font-medium hidden sm:table-cell">{t('pulse.col.updated')}</th>
                <th scope="col" className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {staff?.map((m) => (
                <tr key={m.id} className="border-t border-line">
                  <td className="px-4 py-3 text-fg" dir="ltr">{m.email}</td>
                  <td className="px-4 py-3 text-fg-muted">{t(`pulse.role.${m.role}` as TranslationKey)}</td>
                  <td className="px-4 py-3 text-fg-subtle hidden sm:table-cell">{fmtDateTime(m.createdAt, locale)}</td>
                  <td className="px-4 py-3 text-end">
                    {isAdmin && (
                      <button
                        onClick={() => remove(m)}
                        disabled={busy}
                        className="inline-flex items-center gap-1.5 text-xs text-rose-300 hover:text-rose-200 disabled:opacity-50"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                        {t('pulse.staff.remove')}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
