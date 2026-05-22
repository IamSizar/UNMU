import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { TRANSLATIONS, en, type Locale, type TranslationKey } from './translations'

// I18n provider for the admin dashboard. Tiny on purpose — no library
// dependency, no async loading. Both translation tables are in the
// bundle.
//
// Usage:
//   const { t, locale, setLocale } = useI18n()
//   <h1>{t('posts.title')}</h1>
//
// Behaviour:
//   * Locale persists in localStorage under "admin_locale".
//   * RTL languages (currently only Arabic) flip <html dir="rtl"> +
//     a `lang` attribute via a useEffect.
//   * Missing translation keys fall back to English so a half-translated
//     UI never throws or shows raw keys.

const STORAGE_KEY = 'admin_locale'
const RTL_LOCALES: ReadonlySet<Locale> = new Set<Locale>(['ar'])

type I18nContextValue = {
  locale: Locale
  setLocale: (next: Locale) => void
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string
  isRTL: boolean
}

const I18nContext = createContext<I18nContextValue | null>(null)

export function I18nProvider({ children }: { children: ReactNode }) {
  // Read once on mount; never re-read from storage so a runtime change
  // doesn't fight the React state.
  const [locale, setLocaleState] = useState<Locale>(() => readStoredLocale())

  // Sync <html lang/dir> on every locale change so Tailwind's logical
  // properties (ms-/me-/ps-/pe-) flip naturally and the browser picks
  // the right font / line-break rules for Arabic.
  useEffect(() => {
    const root = document.documentElement
    root.setAttribute('lang', locale)
    root.setAttribute('dir', RTL_LOCALES.has(locale) ? 'rtl' : 'ltr')
  }, [locale])

  const setLocale = useCallback((next: Locale) => {
    try {
      localStorage.setItem(STORAGE_KEY, next)
    } catch {
      // localStorage unavailable (private mode etc.) — ignore. Locale
      // still applies for the session.
    }
    setLocaleState(next)
  }, [])

  const t = useCallback(
    (key: TranslationKey, vars?: Record<string, string | number>): string => {
      const table = TRANSLATIONS[locale] ?? {}
      const raw = (table as Record<string, string | undefined>)[key] ?? en[key] ?? key
      if (!vars) return raw
      // Lightweight {placeholder} substitution — no escaping, no
      // pluralisation rules. Plenty for our admin surface; if we need
      // ICU later we'll swap in formatjs.
      return raw.replace(/\{(\w+)\}/g, (_, name: string) =>
        vars[name] !== undefined ? String(vars[name]) : `{${name}}`,
      )
    },
    [locale],
  )

  const value = useMemo<I18nContextValue>(
    () => ({ locale, setLocale, t, isRTL: RTL_LOCALES.has(locale) }),
    [locale, setLocale, t],
  )

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export function useI18n(): I18nContextValue {
  const ctx = useContext(I18nContext)
  if (!ctx) {
    throw new Error('useI18n must be used inside <I18nProvider>')
  }
  return ctx
}

function readStoredLocale(): Locale {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw === 'ar' || raw === 'en') return raw
  } catch {
    /* ignore */
  }
  return 'en'
}
