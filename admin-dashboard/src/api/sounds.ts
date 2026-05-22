// Tiny notification-sound generator. Uses Web Audio (no asset files) so the
// admin dashboard can ping the user when a realtime event arrives without
// shipping mp3s.
//
// Each severity gets a distinct, short "earcon" — recognizable but not
// annoying. The mute state is persisted in localStorage so the user's
// choice survives reloads.

type Severity = 'info' | 'success' | 'warning' | 'error'

const MUTE_KEY = 'admin_sounds_muted'

let _ctx: AudioContext | null = null

function getCtx(): AudioContext | null {
  if (typeof window === 'undefined') return null
  if (_ctx) return _ctx
  try {
    const Ctor =
      (window as any).AudioContext ?? (window as any).webkitAudioContext
    _ctx = new Ctor()
    return _ctx
  } catch {
    return null
  }
}

export function isMuted(): boolean {
  return localStorage.getItem(MUTE_KEY) === '1'
}

export function setMuted(muted: boolean) {
  if (muted) localStorage.setItem(MUTE_KEY, '1')
  else localStorage.removeItem(MUTE_KEY)
}

/** Play a single sine-wave note at `freq` Hz for `durMs` ms with attack/release. */
function note(ctx: AudioContext, freq: number, durMs: number, startOffsetMs = 0, gain = 0.18) {
  const start = ctx.currentTime + startOffsetMs / 1000
  const dur = durMs / 1000

  const osc = ctx.createOscillator()
  osc.type = 'sine'
  osc.frequency.setValueAtTime(freq, start)

  // Quick attack, gentle release — keeps it from clicking.
  const g = ctx.createGain()
  g.gain.setValueAtTime(0, start)
  g.gain.linearRampToValueAtTime(gain, start + 0.012)
  g.gain.exponentialRampToValueAtTime(0.001, start + dur)

  osc.connect(g).connect(ctx.destination)
  osc.start(start)
  osc.stop(start + dur + 0.05)
}

/** Patterns per severity. Higher / cheerful for good news, low for bad. */
export function play(severity: Severity) {
  if (isMuted()) return
  const ctx = getCtx()
  if (!ctx) return
  // Browsers suspend audio context until first user gesture — resume best-effort.
  if (ctx.state === 'suspended') ctx.resume().catch(() => {})

  switch (severity) {
    case 'info':
      // Single soft "ding"
      note(ctx, 880, 140)
      break
    case 'success':
      // Two ascending notes — cheerful
      note(ctx, 659, 110, 0)   // E5
      note(ctx, 987, 180, 110) // B5
      break
    case 'warning':
      // Two descending notes — alert
      note(ctx, 740, 110, 0, 0.22)   // F#5
      note(ctx, 494, 200, 130, 0.22) // B4
      break
    case 'error':
      // Low buzz — negative
      note(ctx, 220, 220, 0, 0.25)
      note(ctx, 175, 220, 230, 0.25)
      break
  }
}
