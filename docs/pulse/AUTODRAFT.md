# Pulse auto-draft and daily screening refresh

Approved by Zaid on 2026-11-28 ("go ahead all approved and agreed lets build this").

## What it does

1. **Daily screening refresh.** Once a day the backend re-pulls EODHD
   fundamentals for every covered stock, re-runs the Sharia screen and fires
   the usual compliance-drift alerts. It is the same logic as
   `go run ./cmd/ingest_eodhd`, which now calls the shared service.
2. **Daily Pulse drafts.** Once a day the backend:
   - reads the last 36 hours of EODHD news for our covered stocks plus the
     general market feed;
   - reads the Sharia verdict changes of the last 7 days;
   - asks Claude (`claude-opus-5-5`) to pick one story per empty slot
     (global, gulf, sharia, opportunity) and write it in Arabic and English.

   Each pick is saved as a **draft** with no author. Editors still verify,
   review and approve every item in the dashboard. `verified_at` is left
   empty on purpose, so nothing can leave draft until a person verifies the
   source.

## Safety rules

- The source name and URL always come from the article we fetched, never
  from the model's text.
- A slot that already has an item for that day is skipped.
- The Sharia slot is always marked sensitive, which the DB enforces.
- If there is no story for a slot, no draft is made; nothing is invented.
- Every job runs at most once per day per job, across all replicas. The
  `job_runs` table plus a unique (job, day) row handle this. A failed run
  is retried on the next tick, up to 3 attempts. A run left "running" for
  more than 2 hours is treated as dead.
- The backend sleeps on Railway when idle, so a missed hour is caught up on
  the next tick after it wakes.

## Settings (env)

| Var | Default | Meaning |
|---|---|---|
| `DAILY_SCREENING_ENABLED` | off | `true` turns the daily refresh on (needs `EODHD_API_KEY`) |
| `DAILY_SCREENING_HOUR_UTC` | 2 | earliest UTC hour to run |
| `PULSE_AUTODRAFT_ENABLED` | off | `true` turns daily drafts on (needs `EODHD_API_KEY` and `ANTHROPIC_API_KEY`) |
| `PULSE_AUTODRAFT_HOUR_UTC` | 3 | earliest UTC hour to run (06:00 Baghdad) |
| `PULSE_AUTODRAFT_MODEL` | `claude-opus-5-5` | Claude model id |

## Admin API

- `GET /api/admin/jobs`: recent job runs.
- `POST /api/admin/jobs/:name/run`: run a job now (admin only).
  The names are `screening_refresh` and `pulse_autodraft`.

## EODHD news notes

- `s` takes ONE ticker per request (`422 Only one ticker is allowed`), so the
  job makes one request per covered stock (8 articles each), plus one
  general-feed request. A failing general feed is logged and skipped.
- Only tickers in `eodhdSymbolMap` get stock news. Gulf/MENA names are not in
  that map, so the gulf slot depends on the general feed and is often left
  empty, which is by design.

## Tests (all passing, 2026-11-28)

| Test | Where |
|---|---|
| due-time logic, run order, once per day, failure recorded, run now | `services/daily_jobs_test.go` |
| `job_runs` claim: once per day, 3 attempts, stale takeover, manual run (Postgres) | `repositories/autodraft_integration_test.go` |
| `CreateAutoDraft` (no author, change-log note), `TakenSlots`, `RecentShariahChanges` (Postgres) | same file |
| EODHD news: one request per ticker, parsing, HTTP error | `marketdata/eodhd_news_test.go` |
| drafter: taken slots, duplicate slot, bad article index, empty fields, source from the article, Sharia from screening data, nothing open | `services/pulse_autodraft_test.go` |
| Claude reply parsing, refusal | same file |

Not yet run for real: the Claude call itself. The local `ANTHROPIC_API_KEY` was
rejected (401), so the first real run happens once a valid key is set on
Railway.
