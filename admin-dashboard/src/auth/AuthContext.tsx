import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import { api, clearSession, getStoredUser, getToken, setSession, type AdminUser } from '../api/client'
import { realtime } from '../api/realtime'

type AuthState = {
  user: AdminUser | null
  loading: boolean
  login: (email: string, password: string) => Promise<{ ok: boolean; error?: string }>
  logout: () => void
  /** Swap the cached AdminUser in-place — Settings calls this after a
   *  successful PATCH /me/profile so the AppBar / Sidebar avatar +
   *  name reflect the change without a page reload. */
  updateUser: (partial: Partial<AdminUser>) => void
}

const Ctx = createContext<AuthState | null>(null)

type LoginResponse = {
  token: string
  user: {
    id: number
    email: string
    name?: string
    role?: string
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AdminUser | null>(getStoredUser())
  const [loading, setLoading] = useState(false)

  // Connect / disconnect the realtime WebSocket whenever the user changes.
  // Without this, the WS tries to connect at mount before the token is in
  // localStorage and bails out — and nothing re-triggers it after login.
  useEffect(() => {
    if (user) {
      realtime.connect()
    } else {
      realtime.disconnect()
    }
  }, [user])

  async function login(email: string, password: string) {
    setLoading(true)
    try {
      const data = await api.post<LoginResponse>('/auth/login', { email, password })
      const role = (data.user.role ?? 'USER').toUpperCase()
      if (role !== 'ADMIN') {
        return { ok: false, error: 'This account is not an admin.' }
      }
      const adminUser: AdminUser = {
        id: data.user.id,
        email: data.user.email,
        name: data.user.name,
        role,
      }
      setSession(data.token, adminUser)
      setUser(adminUser)
      return { ok: true }
    } catch (e: any) {
      return { ok: false, error: e?.message ?? 'Login failed' }
    } finally {
      setLoading(false)
    }
  }

  function logout() {
    clearSession()
    setUser(null)
  }

  function updateUser(partial: Partial<AdminUser>) {
    setUser((prev) => {
      if (!prev) return prev
      const next: AdminUser = { ...prev, ...partial }
      // Persist alongside the existing token so a page refresh keeps
      // the latest name/email/etc.
      const token = getToken()
      if (token) setSession(token, next)
      return next
    })
  }

  return (
    <Ctx.Provider value={{ user, loading, login, logout, updateUser }}>
      {children}
    </Ctx.Provider>
  )
}

export function useAuth() {
  const v = useContext(Ctx)
  if (!v) throw new Error('useAuth must be used inside AuthProvider')
  return v
}
