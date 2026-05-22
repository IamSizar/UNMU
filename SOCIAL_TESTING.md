# HalalStocks — Social testing guide

This build wires up the role system, paywall, and post composer end-to-end on
both the Flutter app (test mode, no backend required) and the Go/Postgres
backend (when you're ready to swap from mocks).

---

## What you can test right now (no backend needed)

The Flutter app runs entirely on in-memory mocks plus four preset accounts.
Reels, videos and chats are hidden — only **Posts** is visible.

### 1. Test accounts

| Email             | Role    | expertId | Tier    | Linked profile             |
|-------------------|---------|----------|---------|----------------------------|
| user@test.com     | USER    | —        | FREE    | (none)                     |
| expert@test.com   | EXPERT  | e2       | PREMIUM | Sarah Chen                 |
| scholar@test.com  | SCHOLAR | e1       | PREMIUM | Ahmad Al-Rashid            |
| you@test.com      | USER    | —        | FREE    | (none)                     |

Any password works. Any non-listed email logs in as a generic USER.

### 2. Switching accounts in-app

Profile tab → scroll to **Test mode → Accounts** → tap **Switch test account**.
A bottom sheet opens with all four presets, the active one is highlighted with
a green check.

### 3. Things to verify

**a. Subscription paywall** — log in as `user@test.com`, open Social →
   tap any expert (Sarah or Ahmad). The Posts tab is covered by a frosted
   blur with a "Subscribe to view" card. Tap **Subscribe** → the blur
   disappears and posts are visible.

**b. Self bypass** — switch to `expert@test.com`. Open Sarah Chen's profile:
   no paywall (she sees her own posts) and a cyan **New post** FAB appears
   in the bottom-right.

**c. Post on your own profile** — tap **New post**. Fill body + tickers →
   tap **Publish**. The new post appears at the top of the list.

**d. Self bypass for a different expert** — same expert account, open
   Ahmad's profile: paywall is back (you're not subscribed to him).

**e. Community posting** — open any community (Saudi / UAE / US / Global) →
   tap **New post** → fill title, body, ticker, and pick BUY/HOLD/SELL →
   Publish. Newest-first ordering.

**f. Per-account subscriptions persist** — subscribe to Sarah as
   `user@test.com`, then switch to `you@test.com`. You'll see the paywall
   on Sarah again. Switch back: Sarah is still unlocked.

---

## What's wired up on the backend

The Postgres schema and Go endpoints are ready; once you switch the
Flutter `AuthProvider` from `loginTest` to the real `login`, everything
falls into place.

### Schema (`backend/migrations/0001_social_schema.sql`)

- `users.role`, `users.expert_id`, `users.bio`, `users.avatar_url`
- `experts(id, name, expertise, bio, tier, subscriber_count, …)`
- `communities(id, name, region_code, tagline, member_count, active_now, …)`
- `community_members(user_id, community_id)`
- `subscriptions(user_id, expert_id)` — drives the paywall
- `posts(id, target_type, community_id, expert_id, author_id, …)` —
  polymorphic, with a CHECK that forces exactly one target FK to be set

Seed data includes all four test accounts (ids 1001–1004), the two experts
(`e1`, `e2`), four communities, and a handful of starter posts. All
inserts use `ON CONFLICT DO NOTHING` so the migration is idempotent.

To run it:

```bash
psql "$DATABASE_URL" -f backend/migrations/0001_social_schema.sql
```

### Endpoints (`backend/internal/handlers/social.go`)

Public:

```
GET    /api/experts
GET    /api/experts/:id
GET    /api/communities
GET    /api/communities/:id
GET    /api/communities/:id/posts
```

Auth (Bearer JWT):

```
GET    /api/me                              → current user + following list
GET    /api/experts/:id/posts               → 402 if not subscribed
POST   /api/experts/:id/posts               → only the owner may post
POST   /api/experts/:id/subscribe
DELETE /api/experts/:id/subscribe
POST   /api/communities/:id/join
POST   /api/communities/:id/posts
```

The expert-posts endpoint returns **402 Payment Required** when the caller
isn't a subscriber, which the Flutter client treats as "render the paywall".
Self-bypass is implemented in SQL: `IsSubscribed` returns true when the
caller's `expert_id` equals the requested expert.

### Bringing up the API

```bash
cd backend
go run ./cmd/api
# server starts on $SERVER_PORT (default 8080)
```

cURL smoke tests:

```bash
# Login (any test account) — note the password is just "test"
curl -s -X POST localhost:8080/api/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"user@test.com","password":"test"}'

# List communities (public)
curl -s localhost:8080/api/communities

# Try to read Sarah's posts as a non-subscriber → expect 402
TOKEN=… # paste from login response
curl -i localhost:8080/api/experts/e2/posts \
  -H "Authorization: Bearer $TOKEN"

# Subscribe, then re-fetch → expect 200
curl -s -X POST localhost:8080/api/experts/e2/subscribe \
  -H "Authorization: Bearer $TOKEN"
curl -s localhost:8080/api/experts/e2/posts \
  -H "Authorization: Bearer $TOKEN"
```

---

## File map of the changes

Flutter:
- `lib/models/user.dart` — `UserRole` enum, `expertId` field
- `lib/providers/auth_provider.dart` — test accounts, `switchTestAccount`,
  `isSubscribedTo`, `toggleSubscription`, persistent per-user subs
- `lib/screens/social/feed_screen.dart` — collapsed to Posts only
- `lib/screens/social/community_detail_screen.dart` — Posts only + compose FAB
- `lib/screens/social/expert_profile_screen.dart` — Posts only + paywall
  + own-profile compose FAB + AuthProvider-driven Subscribe button
- `lib/screens/social/create_post_screen.dart` — dual-mode composer
- `lib/widgets/social/subscription_gate.dart` — frosted paywall overlay
- `lib/widgets/social/test_account_switcher.dart` — bottom-sheet picker
- `lib/screens/profile/profile_screen.dart` — Test mode card with switcher
- `lib/screens/social/mock_social_data.dart` — `prepend*Post` helpers

Backend:
- `backend/migrations/0001_social_schema.sql` — schema + seeds
- `backend/internal/models/stock.go` — User gains `Role` and `ExpertID`
- `backend/internal/models/social.go` — Expert / Community / Post + ScanPost
- `backend/internal/repositories/user.go` — selects role + expert_id
- `backend/internal/repositories/social.go` — all reads/writes
- `backend/internal/handlers/social.go` — REST handlers
- `backend/internal/handlers/auth.go` — login response now includes role
- `backend/cmd/api/main.go` — wires repo + handler + routes
