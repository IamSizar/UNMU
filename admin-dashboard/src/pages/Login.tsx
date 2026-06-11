import { useState, type FormEvent } from 'react'
import { Navigate } from 'react-router-dom'
import { ShieldCheck, AlertCircle } from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { useI18n } from '../i18n/I18nContext'

export default function Login() {
  const { t } = useI18n()
  const { login, user, loading } = useAuth()
  const [email, setEmail] = useState('admin@test.com')
  const [password, setPassword] = useState('test')
  const [error, setError] = useState<string | null>(null)

  if (user) return <Navigate to="/dashboard" replace />

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    const result = await login(email, password)
    if (!result.ok) setError(result.error ?? t('login.failed'))
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-midnight-500 relative overflow-hidden">
      <div className="absolute -top-40 -right-40 w-96 h-96 bg-cyan-500/15 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute -bottom-40 -left-40 w-96 h-96 bg-gold-500/10 rounded-full blur-3xl pointer-events-none" />

      <div className="card p-8 w-full max-w-sm relative">
        <div className="flex items-center gap-2.5 mb-8">
          {/* Real UNMU wordmark (same asset as the sidebar header). */}
          <img
            src="/unmu-wordmark.png"
            alt="UNMU"
            className="h-9 w-auto shrink-0"
            draggable={false}
          />
          <span className="text-[10px] text-cyan-400/80 tracking-wider uppercase font-bold">
            {t('login.adminBadge')}
          </span>
        </div>

        <h1 className="text-2xl font-extrabold tracking-tight text-white">{t('login.title')}</h1>
        <p className="text-sm text-slate-400 mt-1">{t('login.subtitle')}</p>

        <form onSubmit={onSubmit} className="mt-6 space-y-4">
          <div>
            <label className="block text-xs uppercase tracking-wider text-slate-500 mb-1.5">{t('login.emailLabel')}</label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="input"
              placeholder="admin@test.com"
            />
          </div>
          <div>
            <label className="block text-xs uppercase tracking-wider text-slate-500 mb-1.5">{t('login.passwordLabel')}</label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="input"
              placeholder="••••••"
            />
          </div>

          {error && (
            <div className="flex items-start gap-2 p-3 rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 text-sm">
              <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full btn-primary justify-center disabled:opacity-50"
          >
            <ShieldCheck className="w-4 h-4" />
            {loading ? t('login.signingIn') : t('login.signIn')}
          </button>
        </form>

        <p className="mt-6 text-[11px] text-slate-500 text-center">
          {t('login.testCredentials')} <span className="text-cyan-400">admin@test.com / test</span>
        </p>
      </div>
    </div>
  )
}
