// Realtime WebSocket client for the admin dashboard.
//
// Connects to /api/ws?token=<jwt> on the Go backend, decodes JSON events,
// and emits them through a tiny pub/sub. React components subscribe via the
// useRealtime hook (defined in the same module for compactness).

import { useEffect, useRef, useState } from 'react'
import { getToken } from './client'

const BASE_URL =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) ??
  'http://localhost:8080/api'

export type RealtimeEvent = {
  type: string
  data?: Record<string, unknown>
  timestamp?: string
}

type Listener = (ev: RealtimeEvent) => void

class RealtimeClient {
  private socket: WebSocket | null = null
  private listeners = new Set<Listener>()
  private reconnectTimer: number | null = null
  private retry = 0
  private connected = false

  on(listener: Listener) {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  isConnected() {
    return this.connected
  }

  connect() {
    const token = getToken()
    if (!token) return
    // Already connecting or open — don't churn.
    if (this.socket && this.socket.readyState <= 1) return

    this.disconnect()
    const url = this.buildUrl(token)
    try {
      this.socket = new WebSocket(url)
    } catch {
      this.scheduleReconnect()
      return
    }

    this.socket.onopen = () => {
      this.connected = true
      this.retry = 0
    }
    this.socket.onmessage = (e) => {
      try {
        const ev = JSON.parse(e.data) as RealtimeEvent
        this.listeners.forEach((l) => l(ev))
      } catch {
        // ignore malformed
      }
    }
    this.socket.onerror = () => this.scheduleReconnect()
    this.socket.onclose = () => {
      this.connected = false
      this.scheduleReconnect()
    }
  }

  disconnect() {
    if (this.reconnectTimer) {
      window.clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    if (this.socket) {
      this.socket.onclose = null
      this.socket.close()
      this.socket = null
    }
    this.connected = false
  }

  private scheduleReconnect() {
    this.disconnect()
    this.retry++
    const delay = this.retry > 6 ? 30_000 : 1000 * 2 ** this.retry
    this.reconnectTimer = window.setTimeout(() => this.connect(), delay)
  }

  private buildUrl(token: string) {
    const base = new URL(BASE_URL)
    const scheme = base.protocol === 'https:' ? 'wss:' : 'ws:'
    return `${scheme}//${base.host}${base.pathname}/ws?token=${encodeURIComponent(token)}`
  }
}

export const realtime = new RealtimeClient()

/**
 * React hook — subscribes to one event type and re-renders when the
 * provided callback signals a refresh is needed. Calling code typically
 * passes an `onChange` that re-fetches via the REST API.
 */
export function useRealtime(types: string[], onEvent: Listener) {
  const onEventRef = useRef(onEvent)
  onEventRef.current = onEvent

  useEffect(() => {
    realtime.connect()
    const off = realtime.on((ev) => {
      if (types.includes(ev.type)) onEventRef.current(ev)
    })
    return () => {
      off()
    }
    // We intentionally do not depend on `onEvent`; the ref keeps it fresh.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [types.join(',')])
}

/**
 * Convenience hook for components that just want a connected/disconnected
 * indicator (for an "online" dot in the topbar, etc).
 */
export function useRealtimeStatus() {
  const [connected, setConnected] = useState(realtime.isConnected())
  useEffect(() => {
    realtime.connect()
    const interval = window.setInterval(() => {
      setConnected(realtime.isConnected())
    }, 1000)
    return () => window.clearInterval(interval)
  }, [])
  return connected
}
