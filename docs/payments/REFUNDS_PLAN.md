# Plan: remove access when a store purchase is refunded

Status: **approved ("go") and built on branch `feat/iap-only`** (2026-11-28). Not deployed. Builds on `IAP_ONLY_PLAN.md` (branch `feat/iap-only`).

## How it works today

- Each tier purchase is recorded once in `store_access_grants`. It adds 30 or 365 days (pro-rated if the tier rose during checkout) and its price to the user's active row in `expert_subscriptions` or `community_subscriptions`.
- Nothing listens for refunds. A refunded buyer keeps access until expiry, and payouts still count the price.
- Apple refunds of transactions that were never verified are already skipped (receipt `cancellation_date`).

## How each store tells us about a refund

- **Apple:** App Store Server Notifications v2, a webhook Apple POSTs to us.
  - Types `REFUND` and `REVOKE` carry a signed transaction with the `transactionId`.
  - The body is a JWS (ES256). We check the certificate chain in its `x5c` header against Apple Root CA G3, which is public and is embedded in the code. We also check Apple's marker OIDs on the intermediate and leaf certificates, the signature, and our bundle id.
  - No secret or API key is needed. Zaid sets the URL in App Store Connect.
- **Google:** the Voided Purchases API (`purchases.voidedpurchases.list`, verified to exist in our Go client).
  - It returns the `purchaseToken` of every refunded, charged-back or cancelled one-time purchase.
  - We poll it once a day with the existing daily job runner. It uses the same service account as purchase checks, which needs the Play Console "View financial data" permission.

## What a refund does

1. **Migration 0064 (reversible):**
   - Add `days` to `store_access_grants`. Old rows are filled with 30 or 365 from the product id; new grants store the days actually granted.
   - Add `refunded_at`.
2. **`Revoke(store, transactionRef)`**, one transaction:
   - Find the grant that is not yet refunded. If it is missing or already refunded, do nothing (safe to repeat).
   - Mark it refunded.
   - On the user's active row for that expert or community: subtract the grant's days from `expires_at` and its price from `price_cents` (never below 0).
   - If no time is left, set the row to `expired` and, for a community, remove the member row, as the normal expiry does.
   - With no active row (access already ended), only mark the grant refunded.
3. **Apple:** new public endpoint `POST /api/webhooks/apple/notifications`.
   - A notification that fails verification gets 400, and Apple retries.
   - Verified `REFUND` / `REVOKE` notifications for a `com.unmu.access.*` product call `Revoke`.
   - Every other type is answered 200 and ignored.
4. **Google:** new daily job `store_refunds`, off by default (`STORE_REFUNDS_ENABLED`).
   - It lists voided one-time purchases from the last 30 days (Google's limit), page by page, and calls `Revoke` for each token.
   - The run is recorded in `job_runs` like the other jobs; admins can see it and run it by hand.
5. **Refund reversed** (Apple `REFUND_REVERSED`): logged only. Support can re-grant by hand, as this is rare.

## Tests first (each fails until done)

- `Revoke`:
  - Subtracts days and price.
  - Expires the row and removes the member when no time is left.
  - Repeating it changes nothing.
  - An unknown transaction does nothing.
  - With no active row, it only marks the grant.
- Apple verifier:
  - A test chain signed by a test root is accepted.
  - A wrong root is rejected, and so is a bad signature, a missing OID or a wrong bundle id.
  - `REFUND` calls `Revoke`; other types do not.
- Google job:
  - A fake Play API with two pages of voided purchases revokes each token.
  - An API error fails the run.
- Migration: up, down, up on the local DB, with existing rows getting the right `days`.

## Zaid's tasks (outside the code)

- App Store Connect → App → App Information → App Store Server Notifications: set the production and sandbox URL to `https://<api host>/api/webhooks/apple/notifications`, version 2.
- Play Console → Users and permissions: give the API service account "View financial data" so the Voided Purchases API answers.
- Turn on `STORE_REFUNDS_ENABLED=true` on staging, then production.

## Risks

- **Apple certificate rotation:** the chain is checked against the root, so a new intermediate or leaf is fine. If Apple replaces Root G3 itself, we embed the new root.
- **Days already used:** a buyer refunded late loses the remaining paid days, which can include time they had before. This is the fair rule: the refunded days are removed, not "all access".

## As built (after review, 2026-11-28)

- Migration 0064 stores, per grant, the subscription row it extended (`subscription_id`) and the span it added (`period_start`/`period_end`), instead of a day count.
- A refund removes only the **unused part of that purchase's own span**, from **that row only**. Later purchases stacked on the same row move earlier by the same amount, so their own refunds stay exact. The price always comes off the row.
- A refund for a period that is already used up, or whose row has ended or has no expiry, only marks the grant and removes the price. It never touches a newer subscription.
- Grants and refunds share one lock per user + target.
- Google job: a failing token is reported and skipped, and the run fails so it is retried.
- Webhook: the body is capped at 64 KB, x5c must have exactly 3 certificates, and there is a per-client rate limit.
- **Not built:** a record of each Apple notification, and reconciliation through Apple's Refund History API. If Apple's retries for a refund all fail (about 3 days), only the Sentry alert remains. The environment (Sandbox vs Production) is not checked against the grant.
