import { useEffect, useState } from 'react'
import {
  Camera,
  Moon,
  Sun,
  Database,
  FileJson,
  FileCode,
  Download,
  Loader2,
  CheckCircle2,
  AlertTriangle,
  X,
} from 'lucide-react'
import { api, ApiError, getToken } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import { useI18n } from '../i18n/I18nContext'

// ────────────────────────────────────────────────────────────────────
// useAdminLang — minimal i18n hook for the admin dashboard.
//
// Storage: `localStorage.adminLang` ('en' | 'ar'). The hook returns
// `[lang, setLang]`, and every component that calls it re-renders
// whenever the value changes (via a tiny event listener so changes in
// one tab/panel propagate to every other call site immediately).
// ────────────────────────────────────────────────────────────────────
const LANG_EVT = 'admin-lang-change'
export function useAdminLang() {
  const [lang, setLangState] = useState(() => {
    try {
      return localStorage.getItem('adminLang') || 'en'
    } catch {
      return 'en'
    }
  })
  useEffect(() => {
    function onChange(e) {
      setLangState(e.detail || 'en')
    }
    window.addEventListener(LANG_EVT, onChange)
    return () => window.removeEventListener(LANG_EVT, onChange)
  }, [])
  function setLang(next) {
    try {
      localStorage.setItem('adminLang', next)
    } catch {
      // ignore — storage might be blocked (rare); the in-memory state
      // still updates so the panel responds to the toggle for this
      // session at least.
    }
    window.dispatchEvent(new CustomEvent(LANG_EVT, { detail: next }))
  }
  return [lang, setLang]
}

// Same persistent-via-localStorage + event-bus pattern as useAdminLang,
// applied to the "default region filter" preference. Other admin pages
// (Stocks, Users) can read this when they mount to set their starting
// region filter.
const REGION_KEY = 'adminDefaultRegion'
const REGION_EVT = 'admin-region-change'
function useAdminDefaultRegion() {
  const [region, setRegionState] = useState(() => {
    try {
      return localStorage.getItem(REGION_KEY) || 'GLOBAL'
    } catch {
      return 'GLOBAL'
    }
  })
  useEffect(() => {
    function onChange(e) {
      setRegionState(e.detail || 'GLOBAL')
    }
    window.addEventListener(REGION_EVT, onChange)
    return () => window.removeEventListener(REGION_EVT, onChange)
  }, [])
  function setRegion(next) {
    try {
      localStorage.setItem(REGION_KEY, next)
    } catch {
      // ignore
    }
    window.dispatchEvent(new CustomEvent(REGION_EVT, { detail: next }))
  }
  return [region, setRegion]
}

// ────────────────────────────────────────────────────────────────────
// Top-level page
// ────────────────────────────────────────────────────────────────────

export default function Settings() {
  const { t } = useI18n()
  const [tab, setTab] = useState('profile')
  const tabs = [
    { id: 'profile', label: t('settings.tabProfile') },
    { id: 'preferences', label: t('settings.tabPreferences') },
    { id: 'features', label: 'Features' },
    { id: 'notifications', label: t('settings.tabNotifications') },
    { id: 'security', label: t('settings.tabSecurity') },
    { id: 'team', label: t('settings.tabTeam') },
    { id: 'backup', label: t('settings.tabBackup') },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
          {t('settings.title')}
        </h1>
        <p className="text-slate-400 text-sm mt-1">
          {t('settings.subtitle')}
        </p>
      </div>

      <div className="card overflow-hidden">
        <div className="border-b border-white/5 px-2 flex items-center gap-1 overflow-x-auto">
          {tabs.map((tb) => (
            <button
              key={tb.id}
              onClick={() => setTab(tb.id)}
              className={`shrink-0 px-3 sm:px-4 py-3 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${
                tab === tb.id
                  ? 'border-cyan-500 text-cyan-400'
                  : 'border-transparent text-slate-400 hover:text-white'
              }`}
            >
              {tb.label}
            </button>
          ))}
        </div>

        <div className="p-4 sm:p-6">
          {tab === 'profile' && <ProfileForm />}
          {tab === 'preferences' && <PreferencesForm />}
          {tab === 'features' && <FeaturesForm />}
          {tab === 'notifications' && <NotificationsForm />}
          {tab === 'security' && <SecurityForm />}
          {tab === 'team' && <Placeholder title={t('settings.teamManagement')} />}
          {tab === 'backup' && <BackupExport />}
        </div>
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Profile — wired to PATCH /me/profile (Phase 1.8). Splits the stored
// full name into first / last for the two-column form and stitches it
// back together on save (DB stores one `name` column).
// ────────────────────────────────────────────────────────────────────

function ProfileForm() {
  const { t } = useI18n()
  const { user, updateUser } = useAuth()
  const initial = splitName(user?.name ?? '')
  const [firstName, setFirstName] = useState(initial.first)
  const [lastName, setLastName] = useState(initial.last)
  const [avatarUrl, setAvatarUrl] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [savedFlash, setSavedFlash] = useState(false)

  // Pull the full user record once so we can pre-fill avatar +
  // confirm the email shown matches the backend. AuthContext caches
  // id + email + role + name only.
  useEffect(() => {
    let cancelled = false
    api
      .get('/me')
      .then((me) => {
        if (cancelled) return
        if (me?.name) {
          const split = splitName(String(me.name))
          setFirstName(split.first)
          setLastName(split.last)
        }
        if (me?.avatarUrl) setAvatarUrl(String(me.avatarUrl))
      })
      .catch(() => {
        // Non-fatal: AuthContext still has enough to render the form.
      })
    return () => {
      cancelled = true
    }
  }, [])

  const initialName = user?.name ?? ''
  const fullName = [firstName.trim(), lastName.trim()].filter(Boolean).join(' ')
  const dirty = fullName !== initialName.trim()

  async function save() {
    if (!dirty) return
    setSaving(true)
    setError(null)
    setSavedFlash(false)
    try {
      const res = await api.patch('/me/profile', { name: fullName })
      if (res?.name !== undefined) {
        updateUser({ name: res.name })
      } else {
        updateUser({ name: fullName })
      }
      setSavedFlash(true)
      // Auto-hide the success chip after a moment so the form returns
      // to its idle look.
      setTimeout(() => setSavedFlash(false), 2400)
    } catch (e) {
      setError(e instanceof ApiError ? e.message : t('settings.saveProfileFailed'))
    } finally {
      setSaving(false)
    }
  }

  function reset() {
    const split = splitName(initialName)
    setFirstName(split.first)
    setLastName(split.last)
    setError(null)
    setSavedFlash(false)
  }

  return (
    <div className="space-y-5 sm:space-y-6 max-w-2xl">
      <div className="flex items-center gap-4 sm:gap-5">
        <div className="relative shrink-0">
          {avatarUrl ? (
            <img
              src={avatarUrl}
              className="w-16 h-16 sm:w-20 sm:h-20 rounded-full ring-2 ring-cyan-500/40 object-cover"
              alt=""
            />
          ) : (
            <div className="w-16 h-16 sm:w-20 sm:h-20 rounded-full ring-2 ring-cyan-500/40 bg-gradient-to-br from-cyan-500/30 to-cyan-700/30 flex items-center justify-center text-cyan-200 text-xl font-bold">
              {initialsOf(fullName || user?.email || '?')}
            </div>
          )}
          <span
            className="absolute -bottom-1 -end-1 w-7 h-7 sm:w-8 sm:h-8 rounded-full bg-slate-700 text-slate-400 flex items-center justify-center cursor-not-allowed"
            title={t('settings.avatarSoon')}
          >
            <Camera className="w-4 h-4" />
          </span>
        </div>
        <div className="min-w-0">
          <h3 className="font-semibold text-white">{t('settings.profilePhoto')}</h3>
          <p className="text-sm text-slate-400">
            {t('settings.profilePhotoHint')}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-5">
        <Field
          label={t('settings.firstName')}
          value={firstName}
          onChange={setFirstName}
          disabled={saving}
        />
        <Field
          label={t('settings.lastName')}
          value={lastName}
          onChange={setLastName}
          disabled={saving}
        />
        <div>
          <label className="block text-sm font-medium text-slate-300 mb-1.5">
            {t('settings.email')}
          </label>
          <input
            value={user?.email ?? ''}
            disabled
            className="input opacity-60 cursor-not-allowed"
            title={t('settings.emailHint')}
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-slate-300 mb-1.5">
            {t('settings.role')}
          </label>
          <input
            value={user?.role ?? 'USER'}
            disabled
            className="input opacity-60 cursor-not-allowed"
          />
        </div>
      </div>

      {error && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <div>{error}</div>
        </div>
      )}

      <div className="flex items-center gap-2 pt-2 flex-wrap">
        <button
          onClick={save}
          disabled={saving || !dirty}
          className="btn-primary disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {saving ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            t('settings.saveChanges')
          )}
        </button>
        <button
          onClick={reset}
          disabled={saving || !dirty}
          className="btn-secondary disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {t('common.cancel')}
        </button>
        {savedFlash && (
          <span className="inline-flex items-center gap-1.5 text-xs text-emerald-300">
            <CheckCircle2 className="w-3.5 h-3.5" />
            {t('settings.saved')}
          </span>
        )}
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Preferences — local-only (theme, language, default region filter).
// Persistence is via localStorage so the values survive across
// sessions; nothing is sent to the backend.
// ────────────────────────────────────────────────────────────────────

function PreferencesForm() {
  const { t } = useI18n()
  // Theme is stored under the same localStorage key the ThemeContext
  // writes to. Reading it lets the picker show the current value on
  // mount.
  const [theme, setTheme] = useState(() => {
    try {
      return localStorage.getItem('theme') || 'dark'
    } catch {
      return 'dark'
    }
  })
  const [lang, setLang] = useAdminLang()
  const [region, setRegion] = useAdminDefaultRegion()
  const [savedFlash, setSavedFlash] = useState(false)

  function applyTheme(next) {
    setTheme(next)
    try {
      localStorage.setItem('theme', next)
    } catch {
      // ignore
    }
  }

  function save() {
    // All three values are already persisted live as the user clicks.
    // The Save button is mostly visual reassurance; it just flashes a
    // "Saved." chip so the user knows the picks stuck.
    setSavedFlash(true)
    setTimeout(() => setSavedFlash(false), 1800)
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h3 className="font-semibold text-white mb-1">{t('settings.theme')}</h3>
        <p className="text-sm text-slate-400 mb-3">
          {t('settings.themeHint')}
        </p>
        <div className="grid grid-cols-2 gap-3">
          <ThemeOption
            active={theme === 'dark'}
            onClick={() => applyTheme('dark')}
            icon={Moon}
            label={t('settings.themeDark')}
            sub={t('settings.themeDarkSub')}
          />
          <ThemeOption
            active={theme === 'light'}
            onClick={() => applyTheme('light')}
            icon={Sun}
            label={t('settings.themeLight')}
            sub={t('settings.themeLightSub')}
          />
        </div>
      </div>

      <div>
        <h3 className="font-semibold text-white mb-1">{t('settings.language')}</h3>
        <p className="text-sm text-slate-400 mb-3">{t('settings.languageHint')}</p>
        <div className="grid grid-cols-2 gap-3">
          <LangOption
            active={lang === 'en'}
            onClick={() => setLang('en')}
            flag="🇬🇧"
            label={t('settings.langEnglish')}
            sub={t('settings.langEnglishSub')}
          />
          <LangOption
            active={lang === 'ar'}
            onClick={() => setLang('ar')}
            flag="🇸🇦"
            label={t('settings.langArabic')}
            sub={t('settings.langArabicSub')}
          />
        </div>
      </div>

      <div>
        <h3 className="font-semibold text-white mb-1">{t('settings.defaultRegion')}</h3>
        <p className="text-sm text-slate-400 mb-3">
          {t('settings.defaultRegionHint')}
        </p>
        <select
          value={region}
          onChange={(e) => setRegion(e.target.value)}
          className="input max-w-xs"
        >
          <option>GLOBAL</option>
          <option>GCC</option>
          <option>MENA</option>
          <option>US</option>
          <option>EU</option>
          <option>ASIA</option>
        </select>
      </div>

      <div className="pt-2 flex items-center gap-2">
        <button onClick={save} className="btn-primary">
          {t('settings.savePreferences')}
        </button>
        {savedFlash && (
          <span className="inline-flex items-center gap-1.5 text-xs text-emerald-300">
            <CheckCircle2 className="w-3.5 h-3.5" />
            {t('settings.savedLocally')}
          </span>
        )}
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Features — admin feature flags. The community kill-switch: one master
// toggle turns the entire community system off (browsing, joining, chats,
// posts) for every user; chat + posts sub-toggles for finer control.
// Wired to GET/PATCH /admin/settings. Optimistic flip + rollback on error.
// Nothing is deleted — disabling just blocks access; flip back on to restore.
// ────────────────────────────────────────────────────────────────────

function FeaturesForm() {
  const [flags, setFlags] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [saving, setSaving] = useState(null)

  useEffect(() => {
    let cancelled = false
    api
      .get('/admin/settings')
      .then((f) => {
        if (!cancelled) {
          setFlags(f)
          setLoading(false)
        }
      })
      .catch((e) => {
        if (!cancelled) {
          setError(e instanceof ApiError ? e.message : 'Failed to load settings')
          setLoading(false)
        }
      })
    return () => {
      cancelled = true
    }
  }, [])

  async function toggle(key, next) {
    if (!flags) return
    const previous = flags
    setFlags({ ...flags, [key]: next })
    setSaving(key)
    try {
      const updated = await api.patch('/admin/settings', { [key]: next })
      setFlags(updated)
    } catch (e) {
      setFlags(previous)
      setError(e instanceof ApiError ? e.message : 'Failed to save setting')
    } finally {
      setSaving(null)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-sm text-slate-400">
        <Loader2 className="w-4 h-4 animate-spin" />
        Loading…
      </div>
    )
  }

  const items = [
    {
      key: 'communityEnabled',
      title: 'Communities',
      desc: 'Master switch — turns ALL community features off for every user (browsing, joining, chats, posts).',
      master: true,
    },
    {
      key: 'communityChatEnabled',
      title: 'Community chat',
      desc: 'Sending / reading messages and polls inside communities.',
    },
    {
      key: 'communityPostsEnabled',
      title: 'Community posts',
      desc: 'Creating and viewing posts inside communities.',
    },
  ]

  return (
    <div className="space-y-3 max-w-2xl">
      <div className="rounded-md bg-cyan-500/[0.06] ring-1 ring-cyan-500/20 px-3 py-2 text-xs text-cyan-200/90 leading-relaxed">
        Turn the whole community system on or off in one click. Nothing is
        deleted — disabling just hides &amp; blocks it for users; flip it back
        on to restore everything exactly as it was.
      </div>
      {error && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <div className="flex-1">{error}</div>
          <button
            onClick={() => setError(null)}
            className="text-rose-300 hover:text-rose-200"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}
      {items.map((it) => {
        const value = !!flags?.[it.key]
        // Sub-toggles are moot when the master is off — dim + disable them.
        const disabled = !it.master && flags?.communityEnabled === false
        return (
          <div
            key={it.key}
            className={`flex items-start justify-between gap-3 p-3 sm:p-4 rounded-xl bg-white/[0.02] border transition-opacity ${
              it.master ? 'border-cyan-500/20' : 'border-white/5'
            } ${disabled ? 'opacity-50' : ''}`}
          >
            <div className="min-w-0">
              <p className="font-medium text-white flex items-center gap-2">
                {it.title}
                {it.master && (
                  <span className="text-[10px] font-bold uppercase tracking-wide text-cyan-400">
                    Master
                  </span>
                )}
              </p>
              <p className="text-sm text-slate-400">{it.desc}</p>
            </div>
            {saving === it.key ? (
              <Loader2 className="w-5 h-5 animate-spin text-cyan-400 shrink-0" />
            ) : (
              <Toggle
                on={value}
                onChange={(v) => toggle(it.key, v)}
                disabled={disabled}
              />
            )}
          </div>
        )
      })}
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Notifications — wired to /me/notification-prefs (Phase 2.8). Each
// toggle flips optimistically and rolls back on a server error.
// ────────────────────────────────────────────────────────────────────

function NotificationsForm() {
  const { t } = useI18n()
  const items = [
    {
      key: 'pushEnabled',
      title: t('settings.notifPushTitle'),
      desc: t('settings.notifPushDesc'),
      master: true,
    },
    {
      key: 'emailEnabled',
      title: t('settings.notifEmailTitle'),
      desc: t('settings.notifEmailDesc'),
    },
    {
      key: 'subscriptionsEnabled',
      title: t('settings.notifSubsTitle'),
      desc: t('settings.notifSubsDesc'),
    },
    {
      key: 'communitiesEnabled',
      title: t('settings.notifCommTitle'),
      desc: t('settings.notifCommDesc'),
    },
    {
      key: 'commentsEnabled',
      title: t('settings.notifCommentsTitle'),
      desc: t('settings.notifCommentsDesc'),
    },
    {
      key: 'likesEnabled',
      title: t('settings.notifLikesTitle'),
      desc: t('settings.notifLikesDesc'),
    },
    {
      key: 'marketingEnabled',
      title: t('settings.notifPromoTitle'),
      desc: t('settings.notifPromoDesc'),
    },
  ]

  const [prefs, setPrefs] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [saving, setSaving] = useState(null)

  useEffect(() => {
    let cancelled = false
    api
      .get('/me/notification-prefs')
      .then((p) => {
        if (!cancelled) {
          setPrefs(p)
          setLoading(false)
        }
      })
      .catch((e) => {
        if (!cancelled) {
          setError(
            e instanceof ApiError ? e.message : t('settings.notifLoadFailed'),
          )
          setLoading(false)
        }
      })
    return () => {
      cancelled = true
    }
  }, [])

  async function toggle(key, next) {
    if (!prefs) return
    const previous = prefs
    setPrefs({ ...prefs, [key]: next })
    setSaving(key)
    try {
      const updated = await api.patch('/me/notification-prefs', { [key]: next })
      setPrefs(updated)
    } catch (e) {
      setPrefs(previous)
      setError(e instanceof ApiError ? e.message : t('settings.notifSaveFailed'))
    } finally {
      setSaving(null)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-sm text-slate-400">
        <Loader2 className="w-4 h-4 animate-spin" />
        {t('settings.notifLoading')}
      </div>
    )
  }

  return (
    <div className="space-y-3 max-w-2xl">
      {error && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <div className="flex-1">{error}</div>
          <button
            onClick={() => setError(null)}
            className="text-rose-300 hover:text-rose-200"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}
      {items.map((it) => {
        const value = !!prefs?.[it.key]
        const disabled =
          !it.master &&
          prefs?.pushEnabled === false &&
          it.key !== 'emailEnabled'
        return (
          <div
            key={it.key}
            className={`flex items-start justify-between gap-3 p-3 sm:p-4 rounded-xl bg-white/[0.02] border border-white/5 transition-opacity ${
              disabled ? 'opacity-50' : ''
            }`}
          >
            <div className="min-w-0">
              <p className="font-medium text-white">{it.title}</p>
              <p className="text-sm text-slate-400">{it.desc}</p>
            </div>
            {saving === it.key ? (
              <Loader2 className="w-5 h-5 animate-spin text-cyan-400 shrink-0" />
            ) : (
              <Toggle
                on={value}
                onChange={(v) => toggle(it.key, v)}
                disabled={disabled}
              />
            )}
          </div>
        )
      })}
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Security — change password. Backed by POST /me/change-password
// (Phase 1.9).
// ────────────────────────────────────────────────────────────────────

function SecurityForm() {
  const { t } = useI18n()
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [confirm, setConfirm] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [savedFlash, setSavedFlash] = useState(false)

  const mismatch = next.length > 0 && confirm.length > 0 && next !== confirm
  const tooShort = next.length > 0 && next.length < 6
  const canSubmit =
    !saving &&
    current.length > 0 &&
    next.length >= 6 &&
    next === confirm &&
    next !== current

  async function save() {
    if (!canSubmit) return
    setSaving(true)
    setError(null)
    setSavedFlash(false)
    try {
      await api.post('/me/change-password', {
        currentPassword: current,
        newPassword: next,
      })
      setCurrent('')
      setNext('')
      setConfirm('')
      setSavedFlash(true)
      setTimeout(() => setSavedFlash(false), 2400)
    } catch (e) {
      setError(e instanceof ApiError ? e.message : t('settings.changePasswordFailed'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-5 max-w-md">
      <div>
        <h3 className="font-semibold text-white mb-1">{t('settings.changePassword')}</h3>
        <p className="text-sm text-slate-400">
          {t('settings.changePasswordHint')}
        </p>
      </div>
      <PasswordField
        label={t('settings.currentPassword')}
        value={current}
        onChange={setCurrent}
        disabled={saving}
      />
      <PasswordField
        label={t('settings.newPassword')}
        value={next}
        onChange={setNext}
        disabled={saving}
      />
      <PasswordField
        label={t('settings.confirmNewPassword')}
        value={confirm}
        onChange={setConfirm}
        disabled={saving}
      />
      {tooShort && (
        <p className="text-xs text-rose-300">
          {t('settings.passwordTooShort')}
        </p>
      )}
      {mismatch && (
        <p className="text-xs text-rose-300">{t('settings.passwordMismatch')}</p>
      )}
      {error && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <div>{error}</div>
        </div>
      )}
      <div className="flex items-center gap-2 pt-1">
        <button
          onClick={save}
          disabled={!canSubmit}
          className="btn-primary disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {saving ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            t('settings.updatePassword')
          )}
        </button>
        {savedFlash && (
          <span className="inline-flex items-center gap-1.5 text-xs text-emerald-300">
            <CheckCircle2 className="w-3.5 h-3.5" />
            {t('settings.passwordUpdated')}
          </span>
        )}
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Small primitives
// ────────────────────────────────────────────────────────────────────

function Field({ label, value, onChange, disabled }) {
  return (
    <div>
      <label className="block text-sm font-medium text-slate-300 mb-1.5">
        {label}
      </label>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
        className="input"
      />
    </div>
  )
}

function PasswordField({ label, value, onChange, disabled }) {
  return (
    <div>
      <label className="block text-sm font-medium text-slate-300 mb-1.5">
        {label}
      </label>
      <input
        type="password"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
        autoComplete="new-password"
        className="input"
      />
    </div>
  )
}

function ThemeOption({ active, onClick, icon: Icon, label, sub }) {
  return (
    <button
      onClick={onClick}
      className={`p-4 rounded-xl border text-start transition-colors ${
        active
          ? 'border-cyan-500/40 bg-cyan-500/10'
          : 'border-white/10 bg-white/[0.02] hover:bg-white/5'
      }`}
    >
      <Icon
        className={`w-5 h-5 mb-2 ${active ? 'text-cyan-400' : 'text-slate-400'}`}
      />
      <p className="font-medium text-white">{label}</p>
      <p className="text-xs text-slate-500">{sub}</p>
    </button>
  )
}

function LangOption({ active, onClick, flag, label, sub }) {
  return (
    <button
      onClick={onClick}
      className={`p-4 rounded-xl border text-start transition-colors flex items-center gap-3 ${
        active
          ? 'border-cyan-500/40 bg-cyan-500/10'
          : 'border-white/10 bg-white/[0.02] hover:bg-white/5'
      }`}
    >
      <span className="text-2xl">{flag}</span>
      <div>
        <p className="font-medium text-white">{label}</p>
        <p className="text-xs text-slate-500">{sub}</p>
      </div>
      {active && <span className="ms-auto w-2 h-2 rounded-full bg-cyan-400" />}
    </button>
  )
}

function Toggle({ on, onChange, disabled }) {
  return (
    <button
      onClick={() => !disabled && onChange(!on)}
      disabled={disabled}
      className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors shrink-0 disabled:cursor-not-allowed ${
        on ? 'bg-cyan-500' : 'bg-white/10'
      }`}
    >
      <span
        className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${
          on ? 'translate-x-5' : 'translate-x-0.5'
        }`}
      />
    </button>
  )
}

function Placeholder({ title }) {
  const { t } = useI18n()
  return (
    <div className="text-center py-12 text-slate-500">
      {t('settings.comingSoon', { title })}
    </div>
  )
}

// Helpers — pure-string utilities, no state.

function splitName(full) {
  const parts = (full || '').trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return { first: '', last: '' }
  if (parts.length === 1) return { first: parts[0], last: '' }
  return { first: parts[0], last: parts.slice(1).join(' ') }
}

function initialsOf(s) {
  const parts = s.trim().split(/\s+|\./).filter(Boolean)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0][0].toUpperCase()
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
}

// ────────────────────────────────────────────────────────────────────
// BackupExport — unchanged from the existing implementation. Kept
// inline so the file stays self-contained.
// ────────────────────────────────────────────────────────────────────

function BackupExport() {
  const { t } = useI18n()
  const [busy, setBusy] = useState(null)
  const [error, setError] = useState(null)
  const [lang, setLang] = useAdminLang()
  const isArabic = lang === 'ar'

  async function download(kind) {
    setBusy(kind)
    setError(null)
    try {
      const base =
        import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080/api'
      const token = getToken()
      const res = await fetch(`${base}/admin/export/${kind}`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      })
      if (!res.ok) {
        let msg = t('settings.backupExportFailed', { status: res.status })
        try {
          const j = await res.json()
          if (j?.error) msg = j.error
        } catch {
          // ignore — keep the default msg
        }
        throw new Error(msg)
      }
      const blob = await res.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `halalstocks-export.${kind}`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(null)
    }
  }

  return (
    <div
      dir={isArabic ? 'rtl' : 'ltr'}
      className="space-y-5 sm:space-y-6 max-w-2xl"
    >
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h2 className="text-lg sm:text-xl font-bold text-white flex items-center gap-2">
            <Database className="w-5 h-5 text-cyan-400" />
            {t('settings.backupTitle')}
          </h2>
          <p className="text-sm text-slate-400 mt-1">{t('settings.backupSubtitle')}</p>
        </div>
        <div className="flex items-center gap-1 rounded-md bg-white/[0.04] ring-1 ring-white/10 p-0.5">
          <button
            onClick={() => setLang('en')}
            className={`px-2.5 py-1 rounded text-[11px] font-bold transition-colors ${
              !isArabic
                ? 'bg-cyan-500/20 text-cyan-300'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            EN
          </button>
          <button
            onClick={() => setLang('ar')}
            className={`px-2.5 py-1 rounded text-[11px] font-bold transition-colors ${
              isArabic
                ? 'bg-cyan-500/20 text-cyan-300'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            AR
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {/* JSON */}
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 flex flex-col gap-3">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-lg bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center">
              <FileJson className="w-5 h-5 text-cyan-300" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-bold text-white" dir="ltr">JSON</p>
              <p className="text-[11px] text-slate-400 truncate">
                {t('settings.backupJsonDesc')} <code dir="ltr">{'{name: [rows]}'}</code>
              </p>
            </div>
          </div>
          <p className="text-xs text-slate-400 leading-relaxed">{t('settings.backupJsonHint')}</p>
          <button
            onClick={() => download('json')}
            disabled={busy === 'json'}
            className="mt-auto px-3 py-2 rounded-md bg-cyan-500/15 hover:bg-cyan-500/25 ring-1 ring-cyan-500/30 text-cyan-300 text-sm font-bold disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
          >
            <Download className="w-4 h-4" />
            {busy === 'json' ? t('settings.backupDownloading') : t('settings.backupDownloadJson')}
          </button>
        </div>

        {/* SQL */}
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 flex flex-col gap-3">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-lg bg-emerald-500/15 ring-1 ring-emerald-500/30 flex items-center justify-center">
              <FileCode className="w-5 h-5 text-emerald-300" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-bold text-white" dir="ltr">SQL</p>
              <p className="text-[11px] text-slate-400 truncate" dir="ltr">
                <code>pg_dump --clean --inserts</code>
              </p>
            </div>
          </div>
          <p className="text-xs text-slate-400 leading-relaxed">{t('settings.backupSqlHint')}</p>
          <button
            onClick={() => download('sql')}
            disabled={busy === 'sql'}
            className="mt-auto px-3 py-2 rounded-md bg-emerald-500/15 hover:bg-emerald-500/25 ring-1 ring-emerald-500/30 text-emerald-300 text-sm font-bold disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
          >
            <Download className="w-4 h-4" />
            {busy === 'sql' ? t('settings.backupDownloading') : t('settings.backupDownloadSql')}
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-xs">
          {error}
        </div>
      )}

      <div className="rounded-md bg-amber-500/[0.08] ring-1 ring-amber-500/30 px-3 py-3 text-[12px] text-amber-200 leading-relaxed">
        <strong className="font-bold">{t('settings.backupWarningLead')}</strong> {t('settings.backupWarningBody')}
      </div>
    </div>
  )
}
