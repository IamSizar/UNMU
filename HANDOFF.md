# HANDOFF — UNMU

Running log for this repo. Newest entry on top. Written for a stranger with zero
context: read this before planning any work here.

---

## 2026-11-28 (later) — Daily screening refresh + AI-drafted Pulse (PR #7, branch `feat/pulse-autodraft`; STAGING deployed, production NOT)

**Asked for:** Pulse "automate it and make it fetch daily news", then "go ahead all approved and agreed lets buld this". The plan and test list are in `docs/pulse/AUTODRAFT.md`. The Phase 3 public API product is NOT built: it waits on the EODHD redistribution licence and a Sharia sign-off.

**What changed (`00f5a11`):**
- **Daily job runner** (`services/daily_jobs.go`, migration **0062** `job_runs`): it runs each job once per UTC day across replicas, with up to 3 attempts a day and takeover of a stale run. Admin endpoints: `GET /api/admin/jobs` and `POST /api/admin/jobs/:name/run`.
- **Screening refresh:** the `cmd/ingest_eodhd` loop moved to `services/screening_refresh.go`. The command keeps the same behaviour and log lines.
- **EODHD news fetcher** (`marketdata/eodhd_news.go`).
- **Pulse auto-draft** (`services/pulse_autodraft*.go`, `pulse_claude.go`): Claude `claude-opus-5-5` with structured output and the server-side refusal fallback, effort medium, one call a day. Picks are saved as drafts with no author (`created_by` NULL) and the change-log note "auto-draft from news"; editors still verify, review and approve.
- **New env vars, all off by default:** `DAILY_SCREENING_ENABLED`, `DAILY_SCREENING_HOUR_UTC` (2), `PULSE_AUTODRAFT_ENABLED`, `PULSE_AUTODRAFT_HOUR_UTC` (3), `PULSE_AUTODRAFT_MODEL`, `ANTHROPIC_API_KEY`.

**Verified:**
- `go vet ./...` is clean; `PULSE_TEST_DSN=... go test ./...` all passes. New tests are listed in AUTODRAFT.md.
- **Local API** (`unmu_pulse_dev`, EODHD `demo` key):
  - `GET /admin/jobs` lists both jobs.
  - An unknown job returns 404.
  - `screening_refresh` ran with 0 refreshed and 2 skipped; the local stocks are not covered by EODHD.
  - `pulse_autodraft` failed cleanly: the demo key gets 403 on the general feed. The failure is recorded in `job_runs`.
- **Not run for real:** the Claude call. The shell's `ANTHROPIC_API_KEY` is rejected (401). The first real run needs a valid key.

**Traps:**
- EODHD news takes ONE ticker per request (`s=A,B` returns 422). The demo key only covers a few US tickers and returns 403 on the general feed.
- Gulf names are not in `eodhdSymbolMap`, so the gulf slot will often be empty.
- `pulse_item_versions.reason` only allows create/edit/update/correction, so auto-drafts use `create`.

**Staging (done, Zaid approved "push it and deploy"):**
- Migration 0062 applied.
- Set `DAILY_SCREENING_ENABLED=true`, `DAILY_SCREENING_HOUR_UTC=0` and `PULSE_AUTODRAFT_ENABLED=true`.
- `railway up` deployment `f6dd010a` succeeded; health returns 200.
- The job ran on start-up and `job_runs` shows `screening_refresh | succeeded | 0 refreshed, 1 skipped`. Staging has only 1 test stock, which EODHD doesn't cover.
- Auto-draft logged "ANTHROPIC_API_KEY not set: auto-draft off", as designed.
- `/api/admin/jobs` without auth returns 401.

**To deploy (needs Zaid's go):**
1. Apply 0062 to staging, then to production.
2. Set `ANTHROPIC_API_KEY`, and set `DAILY_SCREENING_ENABLED=true` and `PULSE_AUTODRAFT_ENABLED=true` on the backend.
3. Deploy, then watch `GET /api/admin/jobs` the next morning.

---

## 2026-11-28 — DEPLOYED to staging and production (main `6e4afe9`)

**Asked for:** "push it and update the PR", "upgrade gradle to 8.14", "draft" the privacy manifest, then "deploy all". Zaid approved each production step in chat (migrations: "You run them"; CORS + merges: "Yes, deploy").

**Code added after the overnight entry below:** `b75042c` Gradle 8.14.3 / AGP 8.11.1 / Kotlin 2.2.20 plus a Jetifier ignore list for Flutter engine jars; `29caa5b` iOS privacy manifest `NSPrivacyCollectedDataTypes` (9 types, drafted from the code).

**Merges:** PR #5 squash-merged into `feat/unmu-pulse`, then PR #4 squash-merged into `main` → `6e4afe9`. Railway production auto-deploys from `main`: backend and dashboard `6e4afe9`, both SUCCESS.

**Staging** (`railway up` from the repo root, branch `fix/release-blockers` at `29caa5b`):
- Migrations 0058–0061 applied by hand (0055–0057 were already there).
- `CORS_ALLOWED_ORIGINS=https://dashboard-staging-98ea.up.railway.app` set on the backend.

**Production:**
- **Backup first:** `pg_dump` 18, custom format, 55 tables, about 280 KB. Saved only to Claude's session scratchpad as `prod_backup_2026-11-28_pre0055.dump`. Move it somewhere durable; it contains user data.
- **Migrations:** 0055–0061 applied by hand with `psql -v ON_ERROR_STOP=1`. All 30 users intact; the `expert_subscriptions` payment-method check now allows `apple_iap` and `google_iap`. No `@test.com` seed accounts exist in production.
- **CORS:** `CORS_ALLOWED_ORIGINS=https://dashboard-production-7ad1.up.railway.app` set before the merge.
- **Unchanged settings:** `JWT_SECRET` was already 64 characters, so nobody was logged out. `APP_ENV` is unset, which now means production behaviour.

**Smoke checks (staging and production):**
- `/api/health` returns 200 and `POST /api/dev/impersonate` returns 404.
- Without auth, `/me/iap/google/verify`, `/admin/push/history` and `/pulse/today` return 401.
- CORS preflight is allowed for the dashboard origin and gets no allow header for another origin.
- The dashboard returns 200, and `check-email` answers.
- The production backend logs show no errors.
- Not done: logging in to the app against production, or making a real purchase.

**Still open (Zaid):**
- Google Play: set `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (Android purchase verification fails until it is set) and create the upload keystore (`key.properties`).
- Set `APPLE_IAP_ALLOW_SANDBOX=false` after TestFlight; it defaults to true.
- Check App Store Connect privacy answers against the manifest.
- Decide whether cash/FIB stays for expert subscriptions on iOS.

**Traps:**
- Use `/opt/homebrew/opt/postgresql@18/bin/pg_dump`; the default pg_dump 14 refuses the Postgres 18 server.
- The migration files have their own BEGIN/COMMIT, so `psql -1` prints harmless "transaction in progress" warnings.
- zsh has no `PIPESTATUS`.
- Left uncommitted locally (Flutter tooling side effects): iOS 15 Podfile bump, `Podfile.lock`, `project.pbxproj`, scheme, `pubspec.lock`, `analysis_options.yaml`, swiftpm folders, `backend/scripts/demo_seed*.sql`.

---

## 2026-11-28 — Overnight run: Apple + Google purchases, dashboard, polish, iOS e2e (branch `fix/release-blockers`, local commits only: NOT pushed, NOT deployed)

**Asked for:** "Apple purchase fixes", then "finish this app 100% … /loop … fully e2e tested and verified by 9 am". Scope I set for the loop: Apple fixes, dashboard tsc, iOS simulator build/run, polish, code-only Google Play verification. Rule kept: nothing pushed, deployed or run against production. The commits below are **local** on `fix/release-blockers` (on top of the pushed PR #5 head `fa872e1`); Zaid has not reviewed them yet.

### Commits (oldest first)
| Commit | What |
|---|---|
| `b17ec58` | **Apple IAP holes.** Product ID required and matched exactly; sandbox receipts refused unless `APPLE_IAP_ALLOW_SANDBOX` is true (default true; set `false` in production once TestFlight is done); one owner per `original_transaction_id` (advisory lock, earliest owner wins, others get 409 `RECEIPT_OWNED_BY_ANOTHER_USER`); expert renewals only ever extend `expires_at`; generic 500 text. Migration **0059** lets `expert_subscriptions.payment_method` be `apple_iap` / `google_iap`. |
| `2dcd2c5` | Dashboard: `tsc -b` 35 errors → 0 (types only; deploy runs `vite build` so these never blocked deploys). |
| `c35e7d3` | Push history: migration **0060** `push_send_log`, `GET /admin/push/history`, dashboard Notifications page shows real sends (loading / error+retry / empty), en+ar strings. |
| `5c5b009` | Android `namespace` = `com.easytech.stocks` (matches `MainActivity`'s package). |
| `f2f8291` | Communities looked up on the backend (`CommunityDirectory`), not sample data; removed a random-number chart from expert profile. |
| `147923c` | Removed 15 unreachable lib files (~5 000 lines) and the failing template test. |
| `0d2d432` | **Google Play verification** (code only): `POST /me/iap/google/verify`, `subscriptionsv2.get` + acknowledge, one owner per purchase token incl. `linkedPurchaseToken` upgrades, migration **0061** `google_play_purchases`. App: Android posts `purchaseToken` there. |
| `b45b4c1` | Native iOS spinner (`PlatformSpinner`) at 83 sites. |
| `b829969`, `560176c` | Native iOS confirm dialogs (`PlatformDialog`) for 15 plain confirms (leave community, delete post/message, remove/transfer member, cancel subscription, …). Dialogs with text fields left as they were. |
| `7614a15` | **Bug found in e2e:** tapping Log in flipped the app back to the splash (`authChecked` was `!isLoading`), so the login request was never sent. Now a separate flag set once after session load. |
| `230e364` | **Bug found in e2e:** login screen didn't rebuild on auth state, so errors never showed and the spinner never stopped. Wrapped in `Obx`. |
| `fc1ac0c` | **Fake profile stats** ("12" watchlist, "+8.2%" network, "May '26" for everyone) → real watchlist count + real member-since (API now returns `createdAt` on login/register/Firebase/impersonate/profile). "Network" had no data, so that cell is gone — say if you want it back with a real metric. |
| `655d2a3` | **Android never built.** `build.gradle.kts` used `java.util.Properties()` (my Phase A signing code, `16eaafa`; doesn't compile in a `.kts` script) → `import java.util.Properties`. `settings.gradle.kts`: google-services 4.3.15 → **4.4.2** (Crashlytics plugin 3.0.2 requires ≥ 4.4.1; mismatch was there since the initial commit). |

### Verified (2026-11-28, all local)
- Go: `go vet` clean; `PULSE_TEST_DSN="host=/tmp dbname=unmu_pulse_dev sslmode=disable" go test ./...` all ok.
- Migrations 0059, 0060, 0061: up → down → up on local `unmu_pulse_dev`.
- Flutter: `flutter analyze` clean; `flutter test` 115/115.
- Dashboard: `tsc -b` 0 errors, `vite build` ok; push history page checked in the browser (rows + empty state).
- Live Apple (local API in production mode + fake Apple server): no product → 400; wrong expert → 400; buy → 200 active; other account replays renewal → 409; owner renewal → 200 extended; same receipt again → 200; expired → 200 no sub.
- Live Google (fake Play API): premium → 200 + acknowledged; other account same token → 409; other account linked-upgrade token → 409; owner upgrade → 200; on-hold / wrong product / unknown token → 400; expert purchase → 200, `payment_method = google_iap`.
- iOS simulator (iPhone 17 Pro Max, iOS 26.1, debug build against the local API): splash → login (wrong password shows banner, spinner stops; right password lands in the app) → Pulse (empty state), Discover, Indexes, Social hub, community detail, Leave dialog (native, cancelled), Feed (empty state), Profile (real stats), Logout (native dialog) → guest profile → Sign in again. Test-account tools and the demo login prefill are debug-only (`!kReleaseMode` / `kDebugMode`).
- Release builds: `flutter build ios --release --no-codesign` ✓ (37.1 MB); `flutter build apk --release --android-skip-build-dependency-validation` ✓ (73.3 MB, signed with the debug key because `android/key.properties` is absent; Play will reject that, by design).
- Android emulator (Pixel 9 Pro XL image, API 36, debug APK against the local API via `10.0.2.2`): launches into `com.easytech.stocks/.MainActivity` (namespace fix confirmed), notification prompt, unknown email → error banner + spinner stops, `user@test.com` login → Pulse, Social, Profile (real stats). No crash. Two ANR dialogs happened only while I flooded `adb input` key events; with paced input there were none, idle had none.

### Deploy additions (all need Zaid's go; nothing applied anywhere but local)
- Apply migrations **0059, 0060, 0061** by hand after 0055–0058 (staging, then production).
- New env: `APPLE_IAP_ALLOW_SANDBOX` (set `false` in production after TestFlight), `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` or `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE`, optional `GOOGLE_PLAY_PACKAGE_NAME` (default `com.easytech.stocks`). `GOOGLE_PLAY_ALLOW_TEST` / `GOOGLE_PLAY_API_ENDPOINT` are for local tests only (endpoint accepted on loopback only).
- Old app builds keep working: `createdAt` is a new optional field.

### Blockers that need Zaid
0. ~~Gradle 8.12 below Flutter's minimum~~ **Fixed 2026-11-28:** Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20 (Flutter's minimums). `android/gradle.properties` keeps the migrator flags (`android.builtInKotlin=false`, `android.newDsl=false`) and adds `android.jetifier.ignorelist` for the Flutter engine jars: without it Jetifier runs out of heap on AGP 8.11. `flutter build apk --debug` and `--release` (73.3 MB) both pass with no bypass flag. Trap: if a build fails with "Java heap space", run `./gradlew --stop` first; stale daemons caused one false failure. Not re-run on the emulator after the bump.
1. Push `fix/release-blockers` / update PR #5, deploy, run the 3 migrations.
2. Play Console: service account with "View financial data" + "Manage orders", and the upload keystore. Expert SKUs are `com.unmu.expert.<expertId>.<monthly|yearly>`; expert IDs with hyphens (UUIDs) are **not valid Play product IDs**, so expert subscriptions on Android need a different SKU scheme before they can be sold through Play.
3. iOS: expert subscriptions still offer cash / FIB on Android and iOS; Apple requires IAP for digital content on iOS. Decision is Zaid's.
4. `ios/Runner/PrivacyInfo.xcprivacy`: fill `NSPrivacyCollectedDataTypes` (email, name, purchases, user ID) before submission.
5. 51 files are over the 500-line limit (not touched).

### Traps for the next agent
- **Debug builds hit production** unless you pass `--dart-define=API_BASE_URL=...` (`ApiConfig.baseUrl`). For the simulator use `http://127.0.0.1:8091/api`; Android emulator `http://10.0.2.2:8091/api`.
- Uncommitted, NOT mine to commit: `analysis_options.yaml` (excludes build/platform dirs), `ios/Podfile` iOS 14→15 bump, `Podfile.lock`, `project.pbxproj`, `Runner.xcscheme`, `pubspec.lock` bumps, `ios/**/swiftpm/`, `backend/scripts/demo_seed*.sql`. They came from local iOS builds / earlier work; review before committing.
- `dart format` and `gofmt -w` on whole files reformat unrelated code in this repo (files were never formatted). Edit without them or format only your lines.
- Local test login: `user@test.com` / `test1234` (seed hash from `0012_seed_community_demo.sql`; I reset it in the local DB only). Local API runs with `STOCK_API_PROVIDER=mock`, so index prices there are fake.
- `AuthController.refreshFromBackend` rebuilds `User` from `/me` and drops `avatarUrl` (pre-existing; `createdAt` is now carried over). Not fixed.
- Local DB lacks `community_polls` (the poll closer logs an error every minute); local only, not a code bug.
- Social hub: the "Discover communities" section's title reads "Your communities" (copy bug, not fixed).

---


## 2026-11-27 (later) — PR #5 review findings fixed (same branch, pushed to PR #5)

**Asked for:** run code + security review on PR https://github.com/IamSizar/UNMU/pull/5, then "go on all five" fixes. Reviews: two Sonnet agents (code-reviewer, security-reviewer), each finding checked against the code before fixing.

### What changed
1. **Rate-limit bypass (HIGH).** gin trusted every proxy, so `ClientIP()` was the caller-written leftmost `X-Forwarded-For`. New `middleware.ConfigureClientIP`: no proxy trusted for XFF; only `TRUSTED_CLIENT_IP_HEADER` (default `X-Real-IP`, which Railway's edge sets and overwrites per https://docs.railway.com/networking/public-networking/specs-and-limits ; `none` = TCP peer only).
2. **Limiter growth (MEDIUM).** Idle sweep at most once a minute (was every request), cap 50 000 tracked clients (new clients get 429 past the cap). `Retry-After` now matches the refill (6 s), message says "a few seconds".
3. **Pulse bookmark stuck (MEDIUM).** `PulseController.handleUserChanged` acts only when the user ID changes (profile/email edits re-emit the same user); every account change, incl. A→B, clears `_savingIds`, `savedLoading`, etc.
4. **Replaced items (MEDIUM/LOW).** Migration **`0058_pulse_replaced_by.sql` (+ down)**: `pulse_items.replaced_by` (FK, partial index, CHECK only-archived, backfilled from the change-log note). Publish sets it; Saved/detail use it (no more note matching) and only for users who SAVED the item; `archive` on a replaced item = takedown (clears the link); a second takedown → 409 "already taken down". Dashboard shows Archive on replaced items (`replacedBy` in `api/pulse.ts`, `pulseUi.tsx`).
5. `ios/Podfile.lock`: removed the 6 `app_tracking_transparency` lines by hand (no `pod install`: network too slow, and it would have picked up the uncommitted iOS 15 bump).

### Verified (2026-11-27)
- `flutter analyze lib test` clean; `flutter test` 100 pass, 1 fail (template test, pre-existing).
- `go vet` clean; `PULSE_TEST_DSN=... go test ./...` all ok (new: spoof tests, cap, sweep, Retry-After, client-IP config, archive rule, replaced-link/takedown/saver-only DB tests).
- 0058 up/down/up on the local DB `unmu_pulse_dev`.
- Live (local API, production mode): 12 logins with a new fake XFF each → 10×401 then 429; `Retry-After: 6`; another `X-Real-IP` gets its own bucket. Replaced item 219: admin sees `replacedBy 220`, saver 200, non-saver 404, takedown 200, then saver 404 and Saved empty, second takedown 409.
- NOT run: dashboard `tsc` (no `node_modules`; network too slow to install), app on a simulator/device (see entry below).

### Deploy additions
- Apply **0058** by hand after 0055/0056/0057 (staging + production), same as before.
- Optional `TRUSTED_CLIENT_IP_HEADER` (default `X-Real-IP` fits Railway). If a CDN is ever put in front, set it to the CDN's client-IP header.

### Still open (pre-existing, from the security review, not fixed)
- Apple IAP replay protection keys only on `transaction_id`; check the owner of `original_transaction_id` too.
- Sandbox receipts unlock paid access in production (TestFlight testers).
- Empty `productId` matches any product; raw error text returned by `handlers/iap.go`.

---

## 2026-11-27 — Release-readiness audit + Phase A release blockers fixed (branch `fix/release-blockers`, NOT pushed, NOT deployed)

**Asked for:** deep audit of how close UNMU is to release, then fix the blockers ASAP. Zaid approved "Phase A" (code-only fixes, nothing deployed, production untouched). OPOS 137988 is folded in; OPOS itself was skipped on Zaid's word (`start_task` returned `PRESENCE_NOT_WORKING`).

### Audit verdict (read-only, two Sonnet agents + spot checks)
App features are mostly real; ~1554 en keys all have ar; backend ~250 routes all real, every app/dashboard call has a route; admin authZ is DB-based; SQL parameterized; no secrets in git. Blockers were release config + hardening + ops, listed below. Phase B/C (not done) at the end.

### What changed (branch `fix/release-blockers`, cut from `feat/unmu-pulse`)
App:
- **Test-account switcher never in store builds.** `AppConfigController.showTestTools` = not-release build AND server flag; flag now defaults OFF (also on fetch failure). Login + profile use it. Dead fake-offline-session code removed from `auth_controller.dart` (`loginTest`, `registerTest`, `switchTestAccount`, `testPassword`).
- **Restore purchases** (App Review 3.1.1): `RestorePurchasesButton` (iOS only) in My Subscriptions app bar; `IAPService.restorePurchases()` now returns whether it started; restored expert SKUs get their expert id parsed from the SKU (`expertIdFromProductId`) so the backend can re-activate them; `verifiedRestores` makes the list reload.
- **Release config:** iOS `NSAllowsArbitraryLoads` removed (local networking still allowed); Android cleartext moved to the debug manifest only; mic purpose string now says voice messages (the `record` package IS used in community chat; old text said "not needed"); App Tracking prompt removed entirely (no tracking SDK: `tracking_service.dart`, `app_tracking_transparency` dep and `NSUserTrackingUsageDescription` gone); new `ios/Runner/PrivacyInfo.xcprivacy` (no tracking, UserDefaults CA92.1) added to the Runner target; Android release signing reads `android/key.properties` (falls back to debug key with a Gradle warning when missing).
- **Pulse (OPOS 137988):** Retry on the error state now shows skeletons; Retry on the "couldn't refresh" notice shows a spinner (`PulseController.refreshing`); stale `loadToday` replies and replies for a previous account are dropped (`_loadSeq`, `_accountSeq`, `handleUserChanged`); a second save tap while one is in flight is ignored and a today snapshot can't undo an in-flight save (`_savingIds`).
- Login now links to Forgot password (the screen existed but was unreachable). Indexes and Watchlist show a designed error with Retry (`LoadErrorView`) instead of an endless skeleton / a false "empty" state; new throwing `ApiService.fetchMarketIndexes` / `fetchUserPortfolio` (the old never-throwing ones still serve the decorative widgets).
Backend:
- New `internal/appenv`: dev behaviour ONLY when `APP_ENV` is development/dev/local/test. Before, an UNSET `APP_ENV` counted as dev, which opened `/dev/impersonate` (JWT for any user), `/dev/reset` (wipe), and echoed verification codes and **password-reset tokens** in API responses.
- `config.Load` refuses to start outside dev without a `JWT_SECRET` of 32+ chars (no more silent `change-me-in-production`).
- CORS: `middleware.CORS` with `CORS_ALLOWED_ORIGINS` (comma list); no `Allow-Credentials`; WebSocket origin uses the same check (native apps send no Origin, unaffected).
- Auth endpoints rate-limited per client IP (`middleware.RateLimiter`, burst 10, then 1 per 6 s) → 429.
- Apple receipts must match the app bundle (`APPLE_BUNDLE_ID`, default `com.easytech.stocksanalyzer`); sandbox still accepted (App Review uses sandbox).
- Pulse: a saved item replaced in its slot stays in Saved and keeps opening (`pulseSelectSaveable`, matched on `ReplacedNotePrefix` in the change log); items an approver archived on purpose stay hidden.

### Verified (2026-11-27)
- `flutter analyze lib test` → No issues found. `flutter test` → 97 pass, 1 fail (template `test/widget_test.dart`, pre-existing).
- `go vet ./cmd/api ./internal/...` clean. `PULSE_TEST_DSN="host=/tmp dbname=unmu_pulse_dev sslmode=disable" go test ./...` → all ok (includes the new replaced-item DB test).
- Every new test was run failing first, then passing. A widget test caught a real bug in my first version (an `Obx` reading no observable in release → crash); fixed in `showTestTools`.
- NOT run: an iOS or Android device/simulator build (pbxproj passes `plutil -lint` only), the dashboard against the new CORS.

### Live verification (2026-11-27, local API built from this branch, local DB `unmu_pulse_dev`, port 8091, `APP_ENV=production`)
- Start-up: no `JWT_SECRET` → refuses ("JWT_SECRET is required"); `change-me-in-production` → refuses. Strong secret → starts.
- `/dev/users`, `/dev/impersonate` → 404. Password-reset request → `devMode:false`, no token in the body.
- CORS: listed origin echoed with `Vary: Origin`, no credentials header; other origin gets no header; preflight 403 vs 204; no-Origin (mobile) 200.
- Rate limit: 10 auth requests pass, the 11th → 429 with `Retry-After: 60`; `/health` unaffected.
- WebSocket `/api/ws`: no Origin 101, listed origin 101, other origin 403.
- Pulse through the real admin + app API: item A published and saved by a reader, B published in the same slot (A archived), C published, saved, then archived by an approver → Saved = [A], `GET /pulse/items/A` 200, `GET /pulse/items/C` 404, today = [B]. Rows left in the LOCAL dev DB only (items 219-221).
- **App on a simulator/emulator: NOT verified.** iOS build failed fetching Swift packages (GitHub at ~3-22 KB/s, connection reset; nothing cached: no Pods, no SPM checkouts, no DerivedData). Android `signingReport` failed downloading the Kotlin compiler (read timeout) before evaluating `build.gradle.kts`. Web is not a target (Firebase has no web options) so it stops at the splash. App changes are covered by widget/unit tests only.
- Side effect left uncommitted for Zaid: the installed Flutter SDK's migrator raised the iOS minimum 14.0 → 15.0 (`ios/Podfile`, `project.pbxproj`). Accepting it drops iOS 14 devices; any build with this SDK re-applies it.

### Deploy requirements BEFORE this backend ships (it will refuse to start / block the dashboard otherwise)
- Production and staging: `JWT_SECRET` must be 32+ chars (check the current value: if it is shorter, every user is logged out when it changes). `APP_ENV` must NOT be a dev value. Set `CORS_ALLOWED_ORIGINS=https://dashboard-production-7ad1.up.railway.app` (staging: its dashboard URL).
- Local dev now needs `APP_ENV=development` for verification codes, `/dev/*` and the built-in JWT secret.

### Still open
- **Phase B (needs Zaid / touches production):** back up prod then apply migrations 0055/0056/0057; scheduled EODHD ingest (Shariah verdicts are stale without a manual run); iOS cash/FIB payments for digital content (App Review risk); Google Play verification; Android upload keystore; read-only check of prod env (`APP_ENV`, `JWT_SECRET`, `STOCK_API_PROVIDER`, S3); check whether seed accounts `*@test.com` / `test1234` (migration 0012) exist in the PRODUCTION DB — if so they are public credentials, including `admin@test.com`.
- `PrivacyInfo.xcprivacy` has no `NSPrivacyCollectedDataTypes`: fill it from the App Privacy answers in App Store Connect; App Store Connect must also say "no tracking" now.
- Rate limiter keys on `ClientIP()`; gin trusts all proxies by default, so `X-Forwarded-For` can be spoofed. Set trusted proxies once Railway's proxy behaviour is confirmed.
- Phase C polish: Cupertino dialogs/spinners on iOS, dead mock social screens, fake dashboard push history, dashboard TS errors, 51 files over 500 lines, Android `namespace` still `com.example.halalstocks` (needs MainActivity package move).

### Traps
- `analysis_options.yaml` and `pubspec.lock` were already modified before this work (likely `flutter test` with a newer SDK, plus unknown); NOT committed with this work. `pubspec.lock` here only drops `app_tracking_transparency`.
- `flutter build apk --config-only` rewrites `android/gradle.properties` (adds `builtInKotlin`/`newDsl` flags); not committed.
- `showTestTools` must read the Rx before the bool (see above).

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
