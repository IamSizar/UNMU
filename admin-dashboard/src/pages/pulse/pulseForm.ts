// Pure (no React) helpers for the Pulse item form: converting between the
// stored item and the editable input, client-side validation, dirty checks.
//
// The limits below mirror backend/internal/pulse/rules.go. The browser checks
// them only to give instant feedback; the server checks again and is the
// source of truth.

import type { PulseItem, PulseItemInput } from '../../api/pulse'

export const LIMITS = {
  title: 200,
  summary: 600,
  details: 20000,
  evidence: 5000,
  source: 200,
  url: 2000,
} as const

// A verification time a few minutes ahead is clock skew, not a mistake.
const CLOCK_SKEW_MS = 5 * 60 * 1000

export type FormErrors = Record<string, string>

/** A blank draft for the given day (Pulse day, YYYY-MM-DD). */
export function emptyInput(pulseDate: string): PulseItemInput {
  return {
    pulseDate,
    slot: 'global',
    classification: 'confirmed',
    isSensitive: false,
    titleAr: '',
    titleEn: '',
    summaryAr: '',
    summaryEn: '',
    detailsAr: '',
    detailsEn: '',
    evidenceAr: '',
    evidenceEn: '',
    sourceName: '',
    sourceUrl: '',
    verifiedAt: null,
    stockId: null,
  }
}

/** The editable part of a stored item. */
export function toInput(item: PulseItem): PulseItemInput {
  return {
    pulseDate: item.pulseDate,
    slot: item.slot,
    classification: item.classification,
    isSensitive: item.isSensitive,
    titleAr: item.titleAr,
    titleEn: item.titleEn,
    summaryAr: item.summaryAr,
    summaryEn: item.summaryEn,
    detailsAr: item.detailsAr,
    detailsEn: item.detailsEn,
    evidenceAr: item.evidenceAr,
    evidenceEn: item.evidenceEn,
    sourceName: item.sourceName,
    sourceUrl: item.sourceUrl,
    verifiedAt: item.verifiedAt,
    stockId: item.stock?.id ?? null,
  }
}

/** The Sharia slot is always sensitive; keep the flag consistent with the slot. */
export function normalizeInput(input: PulseItemInput): PulseItemInput {
  return input.slot === 'sharia' ? { ...input, isSensitive: true } : input
}

/** True when the two inputs differ in any editable field. */
export function isDirty(a: PulseItemInput, b: PulseItemInput): boolean {
  return JSON.stringify(normalizeInput(a)) !== JSON.stringify(normalizeInput(b))
}

/** Only http(s) links with a host are accepted (no javascript:, file:, ...). */
export function isValidSourceUrl(url: string): boolean {
  if (!url) return true
  try {
    const u = new URL(url)
    return (u.protocol === 'http:' || u.protocol === 'https:') && u.host !== ''
  } catch {
    return false
  }
}

/**
 * Instant checks shown next to the field. Values are error KEYS, not text, so
 * the form can translate them; the server may add its own messages on top.
 */
export function validateClient(input: PulseItemInput, now: number = Date.now()): FormErrors {
  const errs: FormErrors = {}
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.pulseDate)) errs.pulseDate = 'date'
  if (!isValidSourceUrl(input.sourceUrl)) errs.sourceUrl = 'url'
  if (input.verifiedAt) {
    const t = new Date(input.verifiedAt).getTime()
    if (!Number.isNaN(t) && t > now + CLOCK_SKEW_MS) errs.verifiedAt = 'future'
  }
  return errs
}

/** Fields the server requires before an item may leave draft (spec §5, §19). */
export const REQUIRED_FOR_REVIEW: (keyof PulseItemInput)[] = [
  'titleAr',
  'titleEn',
  'summaryAr',
  'summaryEn',
  'sourceName',
  'verifiedAt',
]

/** Which required-for-review fields are still empty. */
export function missingForReview(input: PulseItemInput): (keyof PulseItemInput)[] {
  return REQUIRED_FOR_REVIEW.filter((k) => {
    const v = input[k]
    return v === null || v === '' || v === undefined
  })
}
