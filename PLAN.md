# UNMU Upsell Implementation Plan

Tracks every gap/upsell item from the growth-memo audit. Checked off as implemented on
branch `feat/upsell-implementation`. Money/fiqh-sensitive items are built with the
engineering complete but the exact methodology constants clearly flagged
`// SHARIAH-REVIEW:` for a scholar/compliance sign-off before shipping to production.

## Quick wins
- [x] Event-driven push — compliance-drift alerts done (commit 9bc49fe): a
      HALAL<->HARAM flip or significant purification-rate change now pushes
      to every watcher/holder, wired into the real production ingest_eodhd
      cron. (Note: new-post-to-subscribers push already existed pre-audit —
      see git history f1ab8a2/7bd2d48 — the actual gap was market-driven
      alerts, not social ones, which is what got built.)
- [x] Weekly halal-market digest email — done (commit 8e5bbfa): `cmd/weekly_digest`,
      reviewed by ecc:go-reviewer (fixed a query-logic bug + N+1 before commit).
- [x] Referral program — done (commit 71fe8d2): migration 0055, ReferralRepository,
      ReferralHandler, 3 endpoints. ecc:go-reviewer caught and fixed a guaranteed-
      failure bug (deterministic reward codes) and a redemption race condition
      before commit. Flutter referral-code share screen not built yet.

## Core bets
- [x] Dividend purification calculator (flagship) — backend calc + endpoint done
      (`GET /api/tools/purification`, commit 14aeac9). Flutter screen still open.
- [ ] Portfolio tracking UI in Flutter, wired to existing `repositories/portfolio.go`.
- [x] Admin-configurable Shariah screening thresholds — backend done (commit dbf4cd1):
      migration 0054, `AppSettingsRepository` float support, `shariah.Thresholds`,
      `GET/PUT /api/admin/screening-thresholds`. Admin-dashboard page still open.
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

### Session 1 — 2026-09-12
Branch `feat/upsell-implementation`, 4 commits, backend only so far, `go build`
+ `go vet` + `go test ./...` all green after each commit (existing
screener_test.go confirms the threshold refactor is behavior-preserving).

- d562918 — plan file
- 14aeac9 — dividend purification calculator (`GET /api/tools/purification`)
- dbf4cd1 — admin-configurable Shariah thresholds (migration 0054 +
  `shariah.Thresholds` + `GET/PUT /api/admin/screening-thresholds`)
- 9bc49fe — compliance-drift push alerts (`services.DriftDetector`,
  wired into the real ingest_eodhd cron, not just the unused
  IngestionService path)

Not started yet: Flutter portfolio screen, Flutter purification/zakat UI,
admin-dashboard pages for the two new endpoints above, weekly digest
email, referral program, real zakat + gold/silver, compliance
certificates, error monitoring, CI pipeline. Deferred items (Google Play
billing, licensed index) still need client-provided credentials/licenses
per the original scoping questions — not attempted.

Nothing has been pushed to GitHub yet — everything is local commits on
`feat/upsell-implementation` pending your go-ahead to push + open the PR.
