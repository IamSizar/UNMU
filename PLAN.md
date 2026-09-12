# UNMU Upsell Implementation Plan

Tracks every gap/upsell item from the growth-memo audit. Checked off as implemented on
branch `feat/upsell-implementation`. Money/fiqh-sensitive items are built with the
engineering complete but the exact methodology constants clearly flagged
`// SHARIAH-REVIEW:` for a scholar/compliance sign-off before shipping to production.

## Quick wins
- [ ] Event-driven push: wire fcm_sender into watchlist price-cross, new post from
      followed expert, reply/comment notifications.
- [ ] Weekly halal-market digest email (new compliant stocks, watchlist movers, top posts).
- [ ] Referral program on top of existing promo-code infra.

## Core bets
- [ ] Dividend purification calculator (flagship) — backend calc + endpoint + Flutter screen.
- [ ] Portfolio tracking UI in Flutter, wired to existing `repositories/portfolio.go`.
- [ ] Admin-configurable Shariah screening thresholds (migration + repo + admin handler
      + admin-dashboard page), screener reads from DB with constants as fallback.
- [ ] App-wide Pro tier (entitlement model + gating).

## Trust foundation
- [ ] Real zakat engine (nisab/hawl calc across portfolio + gold/silver ledger).
- [ ] Compliance certificate export (per-stock, dated, methodology-versioned).
- [ ] Error monitoring (Sentry) wired into backend + Flutter + admin dashboard.
- [ ] Basic CI pipeline (build + test on PR) for backend and admin-dashboard.

## Deferred / needs client input (not attempted automatically)
- Google Play Billing parity — needs the client's Play Console service-account
  credentials; engineering scaffold only, cannot verify real purchases without them.
- Licensed halal index cross-check (Dow Jones Islamic / S&P Shariah) — needs a paid
  data license the client must procure.
- Verified-expert credentialing UI polish, purified model portfolios, sukuk/ETF
  discovery, sadaqah/waqf giving, portfolio challenges — flagged in the memo as
  net-new bets; picked up after the above if time allows.

## Working notes
(appended per session as work lands — file, migration id, what's left)
