# Plan: all subscriptions through in-app purchase only

Status: **approved by Zaid ("go") and built on branch `feat/iap-only`** (2026-11-28). Not deployed.
One change from the draft: the "purchase intent" table (point 3) was replaced by
`store_access_grants` — see "As built" at the end.
Decisions made by Zaid: fixed price tiers; cut off cash/FIB now. The AI drafts are paused (no key).

## How it works today

- **Expert subscriptions:**
  - Payment options are cash, FIB and Apple IAP (iOS only). There is no Google Play button, although the backend can verify Google purchases.
  - Each expert sets any price.
  - Apple product IDs are per expert (`com.unmu.expert.<uuid>.<plan>`), which needs store setup for every expert. Hyphens are also invalid in Google Play product IDs.
  - A store purchase is recorded at a fixed $10 or $96, whatever the expert's price.
- **Community subscriptions:**
  - Payment is cash or FIB only.
  - The DB CHECK allows only `cash` and `fib`.
  - Each community sets any price.
- **Cash/FIB approval:** the user uploads a receipt or a FIB reference, an admin accepts or rejects it in the dashboard, and the subscription becomes active.
- **Production now:** 7 active expert subs and 2 active community subs are on cash/FIB. 5 are pending (3 expert, 2 community).
- **Promo codes:** they only work for cash/FIB.
- **Payout balance:** the sum of `price_cents`, with no store fee taken off.

## Target design

1. **Price tiers.** Each expert and paid community picks a tier instead of a free price. Store prices are set in USD; Apple and Google localise them.

   | Tier | Month | Year |
   |---|---|---|
   | t1 | $4.99 | $49.99 |
   | t2 | $9.99 | $99.99 |
   | t3 | $19.99 | $199.99 |
   | t4 | $49.99 | $499.99 |

2. **Store products:** 8 per store, created once by Zaid. IDs are `com.unmu.access.t1.month` … `com.unmu.access.t4.year`, which is valid on both stores.
   - **Apple:** *non-renewing subscription*. One user can hold many experts and communities at once, and renews by hand.
   - **Google:** *one-time product, consumable*. It is consumed after verification so it can be bought again.
3. **Purchase intent.** Before buying, the app calls `POST /me/iap/intents {targetType: expert|community, targetId, plan}`. The backend checks the target's tier and returns an intent UUID plus the product ID to buy.
   - The UUID goes into the purchase: Apple `appAccountToken`, Google `obfuscatedProfileId`.
   - On verify, the backend matches the store transaction to the intent, so it knows which expert or community was bought.
4. **Verify and grant.**
   - Apple: the existing receipt verification, extended to non-renewing items.
   - Google: `purchases.products.get`, then consume.
   - One owner per transaction or token, as today. The grant is 30 or 365 days, added on top of any time already left.
   - `price_cents` is stored as the tier price, with `payment_method` set to `apple_iap` or `google_iap`.
5. **Cut-off of cash/FIB:**
   - New cash/FIB subscriptions are refused (400).
   - The 5 pending rows are rejected once, with a migration-time note. **Those users may already have paid cash or FIB, so Zaid must refund them by hand.** I will list them for you.
   - The accept/reject endpoints and dashboard buttons are removed.
   - Active rows run until they expire, and the list and detail pages stay so old rows can still be viewed.
6. **Promo codes:** hidden from both purchase sheets, because the stores can't apply our codes.

## Changes by area

- **Database (migration 0063, reversible):**
  - Add `price_tier` to `experts` and `communities`. Existing prices map to the nearest tier, rounding up.
  - New table `iap_intents`.
  - Allow `apple_iap` / `google_iap` in `community_subscriptions.payment_method`.
- **Backend:**
  - Endpoints: the intents endpoint; Apple verify for non-renewing items; Google one-time product verify and consume; community grant.
  - Pricing: the tier is set through `PATCH /me/expert/pricing` and the community edit and admin overrides.
  - Cash/FIB: refused for new subscriptions; approval routes removed.
  - Data: a one-time script rejects the pending rows.
- **App:**
  - The subscribe sheet and the community payment sheet become a single "Subscribe with Apple / Google Play" button.
  - Expert pricing and community edit become tier pickers.
  - The promo field, cash/FIB tiles, receipt upload and their strings are removed (en and ar).
- **Dashboard:** remove the accept/reject actions and the pending counts; show the tier in pricing screens.

## Tests first (each fails until done)

- Intent: creation, a wrong target, and an expired intent.
- Verify: an Apple non-renewing receipt matched to an intent, and the same transaction used twice gives 409.
- Verify: a Google one-time product with its token is verified, consumed and granted.
- Community grant: inserts the member row and extends the expiry date.
- Cash/FIB is refused for experts and communities.
- Tier mapping from old prices.
- Flutter: the sheets show only the store button for each platform, and the tier picker saves.

## Also in this round (small)

- **Profile photo:** keep `avatarUrl` when the account is refreshed from `/me`.
- **Social tab:** the discovery section title "Your communities" becomes "Communities" / "المجتمعات".
- **Uncommitted tooling changes:** commit the iOS 15 minimum, the lock files and the Gradle migrator flags. This drops iOS 14 devices, which the current Flutter SDK requires anyway.

## Not in this round

- Splitting the 51 files over 500 lines. This is large and risky; I suggest a separate, careful pass.
- Payout net of store fees. Payouts currently use the gross price; Zaid to decide the fee rule.

## Zaid's store tasks (needed before release)

- Create the 8 products in App Store Connect (non-renewing) and in Play Console (one-time, consumable), with the tier prices.
- Refund the pending cash/FIB payers from the list I'll give you.

## As built (2026-11-28)

- **No intents.** The app sends the target with the purchase:
  `POST /api/me/iap/access/apple {receiptData, productId, transactionId, targetType, targetId}` or
  `POST /api/me/iap/access/google {purchaseToken, productId, targetType, targetId}`.
  The product's tier must equal the target's current tier (409 `TIER_MISMATCH` otherwise),
  so a buyer always pays the target's own price. Each store transaction (Apple transaction id /
  Google purchase token) grants once: `store_access_grants` UNIQUE(store, transaction_ref).
  Same user + same target again → 200 `alreadyApplied`; anything else → 409 `PURCHASE_ALREADY_USED`.
  This needs no `appAccountToken` / `obfuscatedProfileId`.
- **Grant:** extends the active row by 30/365 days from its expiry (or from now), adds the tier
  price to `price_cents` (payouts sum it), sets `payment_method` to `apple_iap`/`google_iap`.
  Communities also get the `community_members` row. Google purchases are consumed after the grant.
- **App:** a tier purchase is finished with the store only after the backend grants it, and the
  target is saved on the device, so a purchase delivered after a restart is still applied.
- **Old app versions:** cash/FIB subscribe returns 410 `STORE_PURCHASE_REQUIRED`; raw prices
  without `priceTier` return 400 with "Please update the app".
- **Cut-off of pending rows:** `docs/payments/cutoff_pending_cash_fib.sql` (run once per environment
  after migration 0063; it returns the rows to refund).
