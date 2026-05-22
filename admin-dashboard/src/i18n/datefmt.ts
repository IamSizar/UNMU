// Locale-aware date / number formatting for the admin dashboard.
//
// Product decision (mirrors the mobile app): Arabic mode uses Arabic MONTH
// names but keeps WESTERN digits (0-9) — standard for finance UIs. English
// mode keeps the browser's default toLocale* output. These are pure helpers
// (locale passed in) so they work in components AND module-level helpers.
//
// Pass the current locale from `useI18n().locale`.

import type { Locale } from './translations';

const AR_MONTHS = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

function toDate(input: string | number | Date): Date | null {
  const d = input instanceof Date ? input : new Date(input);
  return isNaN(d.getTime()) ? null : d;
}

/** "12 May 2026" (en, browser format) / "12 مايو 2026" (ar, Western digits). */
export function fmtDate(input: string | number | Date, locale: Locale): string {
  const d = toDate(input);
  if (!d) return '';
  if (locale === 'ar') return `${d.getDate()} ${AR_MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  return d.toLocaleDateString();
}

/** Date + 12h time. Arabic: Arabic month + Western digits + ص/م marker. */
export function fmtDateTime(input: string | number | Date, locale: Locale): string {
  const d = toDate(input);
  if (!d) return '';
  if (locale === 'ar') {
    return `${fmtDate(d, locale)}، ${fmtTime(d, locale)}`;
  }
  return d.toLocaleString();
}

/** 12h time. "2:30 PM" (en) / "2:30 م" (ar), Western digits. */
export function fmtTime(input: string | number | Date, locale: Locale): string {
  const d = toDate(input);
  if (!d) return '';
  if (locale === 'ar') {
    const h = d.getHours();
    const m = String(d.getMinutes()).padStart(2, '0');
    const h12 = h % 12 === 0 ? 12 : h % 12;
    return `${h12}:${m} ${h >= 12 ? 'م' : 'ص'}`;
  }
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

/** Number with grouping, ALWAYS Western digits (never Arabic-Indic). */
export function fmtNum(n: number): string {
  return n.toLocaleString('en-US');
}
