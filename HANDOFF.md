# HANDOFF — UNMU

Running log for this repo. Newest entry on top. Written for a stranger with zero
context: read this before planning any work here.

---

## 2026-10-27 — Pulse run on the iOS simulator against staging; 2 real bugs fixed, push-tap NOT device-verified (3 commits local, NOT pushed)

**Asked for:** keep building Pulse; run it on the iOS simulator against staging (OPOS 137987) and fix what breaks. OPOS office 16, tasks 137986 (push tap, Under Review), 137987 (this run), 137988 (review leftovers, still To Do), as account 6.

### What changed (branch `feat/unmu-pulse`, 3 commits ahead of origin, not pushed)
- `3df2ef4` push tap: new `lib/services/pulse_push_router.dart` (+ test), wired in `push_token_service.dart` (`onMessageOpenedApp`, `handleLaunchNotification`) and `main.dart`.
- `648c460` **fix:** teal/ink Pulse cards painted no solid base (a `BoxDecoration` paints gradient OR color, never both), so white text sat on a pale see-through card. Now two nested boxes in `pulse_tokens.dart`. Test `test/widgets/pulse_surface_box_test.dart`. Same commit adds a `--dart-define=API_BASE_URL=...` override in `lib/config/api_config.dart` (default is still production).
- `e96fc52` **fix:** `LanguageController._loadLanguage` never called `Get.updateLocale`, so after a restart layout and content were Arabic but every `.tr` label was English, for the WHOLE app, not just Pulse. Test `test/controllers/language_controller_test.dart` (fails without the fix, passes with it). Also `debugPrint` lines in the push path.

### Verified (commands and results, 2026-10-27)
- `flutter test` -> 75 pass, 1 fail (`test/widget_test.dart` template counter test, pre-existing). `flutter analyze lib test` -> No issues found.
- Built with `flutter build ios --simulator --debug --dart-define=API_BASE_URL=https://backend-staging-33c5.up.railway.app/api`, run on iPhone 17 Pro Max 26.1, logged in as a throw-away staging reader. Seen working: Pulse home with 4 items, confirmed/analysis, "In your portfolio" chip, item detail (source, link, evidence, verified/published times), save + Saved tab, archive with day strip, notification prefs, switching to Arabic (RTL mirrored, Arabic content), and after the fix a cold restart stays fully Arabic.

### NOT verified / still open
- **Push tap does not work on the simulator and I could not prove why.** `xcrun simctl push` with a `gcm.message_id` payload shows the banner and opens the app, but neither `[push] onMessageOpenedApp fired` nor the existing foreground `onMessage` log appears, so the simulated payload may not be treated as an FCM message at all. Staging has no Firebase credentials by design, so a real FCM push cannot be sent. Only the payload-to-route function is unit tested. Needs a real device plus a real FCM push.
- `pulse_new_many` push only returns to the first screen; it does not switch tab.
- Share sheet, "Open source" and stock-link tap were not exercised. OPOS 137988 (Retry spinner, save/load races, saved item replaced in slot) not started.
- Not pushed; PR #4 does not contain these commits. Production still untouched.
- Seen, not Pulse and not fixed: the profile Language/Currency dropdowns use a Material popup on iOS (house rule is Cupertino on iOS).

### External actions
- Staging DB/API only: ran `scratchpad/seed_staging.py` (not in repo), which created 5 `sim-*@example.test` users and 8 published Pulse items (2026-10-26 and 10-27), linked the `opportunity` items to the one staging stock and gave the reader a holding. Rows are harmless; delete them with the 1992 acceptance data when done. The simulator registered a real APNs token for the reader on staging.
- Nothing pushed to GitHub, nothing deployed.

### Traps
- Another session (Nav iQ) put its app on the shared simulator `iPhone 17 Pro` mid-run. Boot your own device by UDID and pass `device` on every simulator call.
- Build lock `~/.cache/heavy-build.lock` was held for a long time by another session; wait with a monitor, release it after your build.
- The login form on a fresh install is pre-filled with `demo@unmu.app`; typing fast right after "Allow notifications" loses the input. Type step by step and check a screenshot before tapping Log in.
- In a plain `test()` `Get.updateLocale` fails (`inTest` assertion); use `testWidgets` with a `GetMaterialApp`.
- The fact-forcing hook demands the importers and the instruction quote before the first edit or write of each file.

---

## 2026-10-22 — UNMU Pulse (نبض أنمو) Phase 1 built end to end; PR #4 open (feat/unmu-pulse → main); staging only, NOT in production

**Asked for:** build Pulse Phase 1 from the spec PDF (daily curated briefing, four
slots, confirmed/analysis items with source + evidence, CMS with workflow/roles/
analytics, app archive/saves/share/stock links). Plan and decisions: `docs/pulse/PLAN.md`;
how to operate it: `docs/pulse/OPERATING.md`. OPOS office for UNMU, tasks "Pulse 1..12"
(117511-117516 are the last six), recorded as account 6 "Zaid Aqrawi".

### What changed (commits on `feat/unmu-pulse`, PR #4; the older branch `feat/nav-aurora-pill` is the same history, unpushed)
`f78ce47` DB schema (migration `0056_pulse.sql` + down + SQL constraint test) · `7a405bb`
public API · `45f411f` admin CMS API, workflow rules, scheduler, staff, analytics ·
`5d19c21` push + per-user switches · `a06cc35` stock search · `b6c9f78` dashboard pages ·
`2f83d24` Flutter (Pulse is now tab 0, 5-tab nav, home/detail/archive/saved/prefs).
Docs/mockups: `42ac136`, `beeec44`, `df13024`.

### Verified (commands run 2026-10-22)
- `cd backend && go build ./... && go test ./internal/pulse/... ./internal/handlers/... ./internal/services/...` → all `ok`.
- `PULSE_TEST_DSN="host=/tmp dbname=unmu_pulse_dev sslmode=disable" go test ./internal/repositories/...` → `ok` (real Postgres; migration up and down were applied separately and checked).
- `flutter analyze` → `No issues found`.
- `flutter test` → 67 pass, 1 fail. The one failure is the template `test/widget_test.dart` (counter smoke test), untouched since the initial commit; it fails regardless of Pulse.
- Dashboard exercised in a real browser against the local API (create → submit → approve → publish, staff view, analytics).
- A bug found by the new tests and fixed: archive day strip overflowed in Arabic / large text (`lib/screens/pulse/pulse_archive_screen.dart`).

### External actions (updated 2026-10-22, after Zaid approved staging)
- **Created Railway environment `staging`** in project UNMU (`8b72ea8e-...`) by duplicating production's config. It has its own Postgres. Production was only READ (table list, community schema dump); nothing in production changed.
- On the staging backend I **deleted** the inherited Firebase, Resend and AWS credentials so staging can never push, mail or write to real systems. FCM and sharing-to-S3 are therefore OFF on staging by design.
- Staging dashboard's `VITE_API_BASE_URL` pointed at the PRODUCTION backend after duplication; changed to the staging backend.
- Loaded schema into the staging DB from the local dev DB (`pg_dump --schema-only`), plus the 6 `community_*` tables copied from production's schema (the local DB lacked them). One trigram index failed (`gin_trgm_ops`: pg_trgm not installed on staging); irrelevant to Pulse.
- Deployed local code with `railway up` from the REPO ROOT (not `--path-as-root`: the services' root dir is `backend` / `admin-dashboard` and a path-as-root upload fails with "directory .../backend does not exist"). Backend: live. Dashboard: builds failed twice on a Railway builder outage ("failed to list workers"); a third attempt (3290769b) was still initializing when this was written.
- URLs: backend https://backend-staging-33c5.up.railway.app/api , dashboard https://dashboard-staging-98ea.up.railway.app (may still be the old production build until 3290769b succeeds).
- Staging data left behind: throw-away users `pulse-*-<timestamp>@example.test`, items dated 1992-03-1x, and a test stock `ACCP`. Harmless; delete the environment or those rows when done.
- Pushed on Zaid's approval: branch `feat/unmu-pulse`, PR https://github.com/IamSizar/UNMU/pull/4 (no CI checks are configured on it). Not merged.

### Acceptance run on staging
`docs/pulse/acceptance/pulse_acceptance.py` (needs STAGING_API, STAGING_DB_URL, PSQL; refuses production URLs) → originally 38/38, now **44/44 checks passed** (after the four-eyes change; see below) on the spec §22 list: four items, detail, source/evidence/verified time, confirmed vs analysis, save/share, stock link, drafts, review/approve cycle, role enforcement, scheduled publishing (real scheduler, ~90 s), archive + search, versions, change log, corrections, user prefs, analytics, Arabic+English content.
**Not covered by it:** push delivery (FCM is off on staging), RTL/LTR rendering and the in-app experience on a real device (widget tests only), the dashboard UI on staging.
Review findings fixed in `68f35cc` (future-dated publish leak, event existence oracle). Review findings now FIXED by Zaid's decision: corrections need a second person; sensitive approver != reviewer. Still open: Retry button gives no spinner; toggleSave/loadToday races on fast taps or account switch; a saved item disappears when replaced in its slot.

### Four-eyes change (Zaid, 2026-10-22, OPOS 117682) — commit 58a5505
- **Corrections are now two-person.** `POST /pulse-admin/items/:id/correct` only PROPOSES (202, stored in new table `pulse_pending_corrections`); the live item is untouched. A DIFFERENT approver applies/rejects via `POST .../correction/approve|reject` (`GET .../correction` shows the open one). Reject needs a note. One open proposal per item. The old one-step `repo.Correct` no longer exists (removed on purpose so nothing can bypass it).
- **Sensitive items: approver != reviewer.** Rule in `pulse.CheckApproval(item, actor)` plus DB CHECK `pulse_items_approver_not_reviewer` (NOT VALID, so old rows are not re-checked).
- **New migration `0057_pulse_pending_corrections.sql` (+ `.down.sql`)**: run up/down/up locally; applied by hand to the STAGING DB. NOT applied to production. It also widens the change-log action list (`correction_proposed`, `correction_rejected`).
- Code: `internal/repositories/pulse_corrections.go` (new), `internal/pulse/rules.go`, handlers `pulse_admin.go`, route wiring in `cmd/api/main.go`; dashboard `PendingCorrectionCard.tsx`, editor now says "Send for approval", en+ar strings.
- Tests: rule unit tests, DB integration tests (propose does not change the item, self-apply and editor-apply refused, second proposal refused, reject needs reason, version kept, sensitive reviewer cannot approve), all `ok`. Acceptance script now **44/44** on staging.
- A system ADMIN holds every Pulse role but is bound by the same proposer/reviewer rules, so a lone admin can no longer correct an item. Normal staff are plain users holding one role via Dashboard → Pulse → Staff (NOT admin accounts; an earlier note and my first test script wrongly assumed they had to be).
- Trap: the existing fixture inserted published sensitive items with one user as reviewer AND approver; the new CHECK rightly rejected it (fixed in `pulse_integration_test.go`). Any seed script that does the same will fail the same way.
- Trap: Railway `railway up` must run from the repo root (see above); a stuck "BUILDING" for 10+ minutes is normal for the backend image.

### Production deploy notes
Production DB lacks the `referrals` / `user_referral_codes` tables that the code needs (they exist locally and on staging only). Migrations `0056_pulse.sql`, `0057_pulse_pending_corrections.sql` AND the referrals migration must be applied by hand before shipping this backend.



### Still open
- **Ask Zaid before:** creating the staging Railway environment (decision made: test on a new staging env), and any push.
- Migration 0056 must be applied by hand to staging and production DBs (prod never auto-migrates).
- Flutter was never run on a simulator/device this round; only widget tests and analyze.
- No widget test for `PulseNotificationPrefsScreen` (its service is static HTTP with no seam).
- Tapping a Pulse push only opens the app: the app has no push-tap routing at all (no `onMessageOpenedApp`).
- Untracked and not mine: `backend/scripts/` (demo seeds), this file before today.
- Leftovers to clean: local test API / vite preview processes, scratch rows in `unmu_pulse_dev`, `.env.local`, an added `.claude/launch.json` entry.

### Traps
- Fact-forcing hook denies edits until you state facts; do so, then retry.
- `git add backend` sweeps in the untracked demo seeds. Add paths explicitly.
- `admin-dashboard/node_modules/lines-and-columns` was corrupt and broke `vite build`; reinstalled. `tsc` has 35 pre-existing errors, 0 from Pulse; restore `tsconfig.tsbuildinfo` after type-checks.
- `pkg/jwt` has a pre-existing flaky test.
- Widget tests: call `initializeDateFormatting`, set `VisibilityDetectorController.instance.updateInterval = Duration.zero`, and set `LanguageController.localeRx` directly (`setLanguage` schedules a frame).
- Existing adaptive widgets detect platform with `dart:io`; Pulse widgets use `Theme.of(context).platform` so tests can flip it.

---

## 2026-09-23 — Locate deployment, enumerate roles, seed QA accounts, install on iPhone

**Asked for:** find where the admin dashboard is deployed and produce the link;
install the app on Zaid's iPhone; determine how many user roles exist and seed an
account for each plus the admin dashboard.

### Deployment (Railway)

Everything is in Railway project **UNMU** (`8b72ea8e-9073-403c-81b3-9e047c92aced`),
environment `production`, under the account `easytechnologycompany@gmail.com`.
Services: `Postgres`, `backend`, `dashboard`, `main`.

| What | URL | Verified |
|---|---|---|
| Admin dashboard | https://dashboard-production-7ad1.up.railway.app | HTTP 200 |
| Backend API | https://backend-production-c908.up.railway.app/api | `/api/health` 200 |

- `main` has no public domain.
- A **separate, older Railway project `unmu-dashboard`** (service `web`) also
  exists. It was not touched and its status is unknown — check before assuming
  the dashboard above is the only one.
- The dashboard's `VITE_API_BASE_URL` is already set to the backend URL above.
  It is baked at **build time** (see `admin-dashboard/Dockerfile`), so changing
  it requires a redeploy, not just a variable edit.

### User roles — there are 3

Confirmed against the live production database, not just the source:
`users_role_check` is `CHECK (role = ANY (ARRAY['USER','EXPERT','ADMIN']))`.

- `USER`  — default on signup.
- `EXPERT` — content creator; **must** have a matching row in `experts`, joined
  by `users.expert_id`, or the `posts` / `expert_subscriptions` FKs fail.
- `ADMIN` — admin dashboard access.

`SCHOLAR` appears all over the older migrations but was folded into `EXPERT` by
`backend/migrations/0013_remove_scholar_role.sql`. It no longer exists — ignore it.

`subscription_tier` (`FREE` / `PREMIUM`) is a **separate axis from role**, not a
fourth role. A PREMIUM `USER` is what exercises the Pro-gated screens.

The admin dashboard has **no separate login system**: it posts to the same
`POST /api/auth/login` and is gated on `role = 'ADMIN'`, read from the database
on every request rather than trusted from the JWT
(`backend/internal/middleware/admin.go`).

### Seeded QA accounts (production database)

Four rows added to `users`, plus one `experts` row `e_seed_qa` as the FK target
for the expert account. Emails are `qa.admin@`, `qa.user@`, `qa.premium@` and
`qa.expert@` `unmu.app`, with roles ADMIN / USER / USER(PREMIUM) / EXPERT.

**The shared password is not recorded in this file on purpose** — ask Zaid, or
reset it. Password hashes are bcrypt cost 10, matching `bcrypt.DefaultCost` used
by the Go handlers.

Verification actually run (not assumed):
- All four `POST /api/auth/login` returned a token with the expected role and tier.
- `GET /api/admin/screening-thresholds` → **200** as `qa.admin`, **403** as
  `qa.user`. The admin gate works in both directions.

Writes were purely additive — `ON CONFLICT (email) DO UPDATE` touches only these
four rows. No existing user was modified. Production already holds 10 real users
including `zaid@unmu.app` (ADMIN) and `testadmin@unmu.app` (ADMIN).

### iPhone install

Built and installed to **Zaid's iPhone** (iPhone 11 Pro Max, iOS 26.0.1, UDID
`00008030-001A459A0A6A802E`, devicectl id `5799B1CF-81C2-53C5-AE1C-D4B90CCE9C29`)
**over the network** — the device is paired wirelessly, not cabled.

- `flutter build ios --release` → `build/ios/iphoneos/Runner.app`, 41.3 MB,
  automatically signed with team `SBL65MNY44`, bundle `com.easytech.stocksanalyzer`.
- `xcrun devicectl device install app` → installed.
- `xcrun devicectl device process launch` → launched, and confirmed still alive
  (PID from the installed bundle path) ~20s later, so it is not a splash-screen
  crash-on-launch.
- The installed build talks to the **live Railway backend**, not a local one:
  `ApiConfig.useLocalBackend` is hardcoded `false`, so debug and release builds
  both hit production. Anything done in this app writes to real production data.

### Traps that cost time here

1. **`railway status` in this repo fails with "You do not have access to this
   resource."** This is misleading — it is not a permissions problem. The repo is
   not linked, so the CLI walks up to the parent directory
   `~/Documents/Projects`, which *is* linked, to an unrelated project
   (`lucid-vision`) the account genuinely cannot access. Link this directory
   explicitly, or run `railway list --json` and match on the project name.
2. **`railway list` output is long** — UNMU is far down it. Do not conclude the
   project is missing from a truncated listing.
3. **The `*@test.com` seed accounts in migrations `0001` / `0002` / `0012` do not
   exist in production.** Those migrations never ran there. Every credential in
   the repo's docs and on the dashboard login screen's hint text
   (`admin@test.com / test`) is dead. `/api/auth/check-email` returns
   `{"exists":false}` for all of them.
4. **`pod install` fails with a bare CocoaPods backtrace ending in
   `verify_podfile_exists!` when `LANG` is unset**, even though `ios/Podfile` is
   right there. Export `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` first.
5. **`FirebaseCrashlytics 11.15.0` clones the entire `firebase-ios-sdk` repo** and
   failed three times on this connection (`RPC failed`, `Recv failure: Operation
   timed out`). It succeeded after
   `git config --global http.lowSpeedLimit 0; http.lowSpeedTime 999999;
   core.compression 0` plus a retry loop. The local CocoaPods cache holds
   12.18.0, which does **not** satisfy the 11.15.0 pin.
6. **`flutter devices` reports Zaid's iPhone as an error** ("Ensure the device is
   unlocked... code -27") on the default timeout while `devicectl` already lists
   it as `available (paired)`. Use `--device-timeout 30`.

### Still open

- `admin-dashboard` has ~15 pre-existing TypeScript errors; its Dockerfile skips
  `tsc -b` to build at all. CI reports but does not block.
- Sentry is wired into the API server only — not Flutter, not the admin dashboard.
- The old `unmu-dashboard` Railway project is unexamined; delete it if dead.
- OPOS tasks were **not** created for this work. The OPOS MCP server needed
  authorization and the session could not run the OAuth flow.
- Nothing was committed or pushed. This file is the only working-tree change.
