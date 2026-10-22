// A tiny browser event that tells the sidebar "something in Pulse changed", so
// the review-queue badge refreshes right after an action instead of waiting for
// its 60-second poll. Kept in its own file so the Sidebar and the Pulse editor
// can share it without importing each other.

export const PULSE_CHANGED_EVENT = 'pulse:changed'

/** Call after any successful Pulse save, workflow action, correction or delete. */
export function notifyPulseChanged(): void {
  window.dispatchEvent(new Event(PULSE_CHANGED_EVENT))
}
