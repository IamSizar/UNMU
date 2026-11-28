-- One-time cut-off of cash/FIB subscription requests (2026-11-28).
--
-- Rejects every expert and community subscription that is still waiting
-- for an admin to confirm a cash or FIB payment, now that payment is App
-- Store / Google Play only (docs/payments/IAP_ONLY_PLAN.md). Active rows
-- are NOT touched: they run until they expire.
--
-- The status triggers send the user the normal "rejected" notification
-- with the reason below. These users may already have paid: refund them
-- by hand from the rows this script returns.
--
-- Run once per environment, after migration 0063:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f docs/payments/cutoff_pending_cash_fib.sql
BEGIN;

UPDATE expert_subscriptions
   SET status = 'rejected',
       rejected_at = NOW(),
       rejection_reason = 'Cash and FIB payments have ended. Please subscribe '
           || 'through the App Store or Google Play. If you already paid, '
           || 'contact support for a refund.'
 WHERE status = 'pending' AND payment_method IN ('cash', 'fib')
RETURNING 'expert' AS kind, id, user_id, expert_id AS target_id,
          payment_method, price_cents, payment_ref, created_at;

UPDATE community_subscriptions
   SET status = 'rejected',
       rejected_at = NOW(),
       rejection_reason = 'Cash and FIB payments have ended. Please subscribe '
           || 'through the App Store or Google Play. If you already paid, '
           || 'contact support for a refund.'
 WHERE status = 'pending' AND payment_method IN ('cash', 'fib')
RETURNING 'community' AS kind, id, user_id, community_id AS target_id,
          payment_method, price_cents, payment_ref, created_at;

COMMIT;
