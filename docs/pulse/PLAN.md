# UNMU Pulse (نبض أنمو) — Phase 1 MVP plan

Source: "UNMU Pulse MVP" PDF from Easy Technology (sections 2-23, 15 pages).
Audit date: 2026-10-22. OPOS office 16 "-104- UNMU", tasks 117504-117516.

## 1. What Pulse is (from the spec)

A daily, **manually curated** briefing at the front of the app. Four items a day:

| Slot key | Meaning |
|---|---|
| `global` | most important world event |
| `gulf` | most important Gulf event |
| `sharia` | most important Sharia change |
| `opportunity` | top opportunity to follow |

Every item: AR + EN title / summary / details, source name + link, evidence,
verification date + time, classification (`confirmed` = verified fact with
source; `analysis` = interpretation), optional link to a stock/company/asset,
status marker (new / updated / corrected), publish time, last-update time.

User can: view today's Pulse, open an item, see source + evidence, save, share,
jump to the linked stock, see a marker if the stock is in their portfolio or
watchlist, browse the archive, set Pulse notification preferences.

Admin dashboard: CRUD, drafts, review -> approve -> publish, scheduled publish,
corrections (previous version kept), full change log, roles (editor, reviewer,
approver, system admin), basic analytics, short operations doc.

**Explicitly out of phase 1:** AI engine, automatic news/data collection,
automatic Sharia rulings, historical Sharia simulation, portfolio-impact
analysis, predictive analysis, B2B/API, comments, discussions, likes,
reactions, any link to the community section.

Acceptance criteria are section 22 of the spec; they become the test list in
task Pulse 11.

## 2. What exists today (verified in code)

| Area | Finding | Reuse? |
|---|---|---|
| Backend | Go + Gin, one router in `backend/cmd/api/main.go`; public group, `protected` group (`AuthMiddleware`), `/admin` group (`RequireAdmin`). Layers: handlers -> repositories -> services. | Yes, same layering |
| Roles | `users.role` CHECK = `USER/EXPERT/ADMIN` (SCHOLAR removed in migration 0013). `RequireAdmin` reads role from DB each request. | Do **not** alter this CHECK (auth path). Pulse staff roles go in a new table. |
| Scheduled publish | `services/scheduled_publisher.go`: 60 s ticker, one atomic `UPDATE ... RETURNING`, runs once at startup. | Copy the pattern for `pulse_items` |
| Push | `services/notifier.go` (`PushToUser(s)`), FCM sender, `scheduled_push_sender.go`. | Yes |
| Notification prefs | `user_notification_prefs` (one row per user, boolean per category). | Add `pulse_enabled` column |
| Saves | `post_saves` has an FK to `posts`; Flutter `SaveService` + `SavedController`. | Cannot reuse the table; new `pulse_saves`; mirror the service/controller shape |
| Audit | `audit_logs` + `AuditRepository.Write`. | Use for coarse events; Pulse also needs its own per-item history |
| Stocks | `stocks(id SERIAL, ticker, exchange, name, ...)`, `UNIQUE(ticker, exchange)`. App opens `StockDetailScreen(ticker, exchange)`. | Link by `stock_id` FK; app navigates with ticker+exchange |
| Portfolio / watchlist | `user_portfolios` served by `GET /user/portfolio`; `WatchlistController` reads the same data. | Yes, for the "in your portfolio" marker |
| Flutter | GetX controllers, `services/*_service.dart`, `screens/<feature>/`, one `i18n_*.dart` per surface merged in `app_translations.dart` (en and ar maps must have identical keys). 4 tabs after the nav rework (branch `feat/nav-aurora-pill`). | Yes |
| Admin dashboard | React + Vite + Tailwind, `pages/*.tsx`, routes in `App.tsx`, i18n in `src/i18n/sections`, API in `src/api/client.ts`. Login = same `/auth/login`, gated on ADMIN. | Yes |
| Tests | Go tests exist (`*_test.go`); Flutter has `test/widgets/modern_bottom_nav_test.dart`; `test/widget_test.dart` is the untouched counter template and fails (pre-existing). | Add Go + widget tests |

## 3. Decisions and assumptions (flag for review)

1. **Pulse staff roles live in a new table** `pulse_staff(user_id, pulse_role)`
   with `editor | reviewer | approver`. `users.role = ADMIN` is the "system
   admin". Reason: avoids touching `users_role_check` and the login/JWT path.
   Needs a new middleware `RequirePulseStaff(roles...)` that reads from the DB.
2. **One published item per (pulse_date, slot)**: partial unique index on
   published rows. Older/replaced rows are archived, not deleted.
3. **Versioning**: `pulse_item_versions` stores a full JSON snapshot on every
   edit or correction; `pulse_item_events` stores who/when/what for the section
   15 change log (created, edited, sent to review, reviewed, approved,
   scheduled, published, updated, corrected).
4. **Review gate**: an item cannot reach `published` unless status passed
   `in_review -> approved` by a user with reviewer/approver role who is not the
   author. Items in the `sharia` slot, or flagged `sensitive`, additionally
   require an approver. Enforced in the service layer and with a DB CHECK on
   status values.
5. **"Company / asset"** in the spec maps to `stocks` rows in this app (the
   only asset type with a detail screen). Link column is `stock_id`.
6. **Today's Pulse is served from the protected group** (login required),
   like the rest of the app. Say if it should be public.
7. **Bilingual**: both AR and EN are required before an item can leave draft
   for review.
8. **Analytics** (section 18): `pulse_events(item_id, user_id, event, at)` with
   events `view_day`, `open_item`, `save`, `share`, `read_complete`. Aggregates
   computed on read for MVP.
9. **Deploy trap**: `start-railway.sh` **does not run migrations** (schema is
   managed out of band). Every Pulse migration must be applied by hand to the
   test and production databases before the matching backend deploy. Record
   this in HANDOFF and in the operations doc.

## 4. Data model (draft, finalised in Pulse 2)

- `pulse_items`: id, pulse_date, slot, classification, status, sensitive,
  title_ar/en, summary_ar/en, details_ar/en, source_name, source_url,
  evidence_ar/en, verified_at, stock_id NULL, version (int), publish_at,
  published_at, last_updated_at, correction_flag, created_by, timestamps.
- `pulse_item_versions`, `pulse_item_events`, `pulse_saves`, `pulse_events`,
  `pulse_staff`; `user_notification_prefs.pulse_enabled`.
- All with `id`, `created_at`, `updated_at`, indexes on FKs and on
  `(pulse_date, slot)`, `(status, publish_at)`, reversible down migration.

## 5. API sketch

Public (protected group): `GET /v1/pulse/today`, `GET /v1/pulse/items/:id`,
`GET /v1/pulse/archive?from&to&q&page`, `POST|DELETE /v1/pulse/items/:id/save`,
`GET /v1/pulse/saved`, `POST /v1/pulse/events`, prefs via existing
notification-prefs endpoints.

Admin (`/admin/pulse/...`, `RequirePulseStaff`): list/filter, create, update,
delete (draft only), submit-for-review, review, approve, schedule, publish,
correct, versions, events, analytics, staff management (ADMIN only).

## 6. Client work

- Flutter: new first tab "Pulse" (default on open), nav goes 4 -> 5 items
  (check pill width at 5 on small phones, and the iPad rail), `PulseController`,
  `PulseService`, screens: home (4 cards), detail, sources/evidence, archive,
  saved, notification settings; `i18n_pulse.dart`; skeleton/error/empty states;
  Cupertino/Material adaptive; RTL verified.
- Admin dashboard: pages for list, editor, review queue, versions/log, staff,
  analytics; sidebar entry; AR/EN labels.

## 7. Order of work (OPOS tasks)

0 commit nav work (done) -> 1 audit (this doc) -> 2 migrations -> 3 public API
-> 4 admin API -> 5 notifications -> 6 dashboard -> 7-9 Flutter -> 10 l10n/RTL
-> 11 tests + staging -> 12 docs. Code review + security review before any PR.

## 8. Open questions

1. Public or login-required for today's Pulse? (assumed login-required)
2. Is a test/staging environment separate from production available? Spec
   section 21 asks for deploy to a test environment first; today the app
   talks to the live Railway backend in all builds.
3. Who are the first editors/reviewers/approvers (accounts)?
4. Are notification texts sent in the user's app language (assumed yes, using
   the existing locale sync)?
