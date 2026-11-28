-- 0059_expert_sub_store_payments.sql — let store purchases create expert
-- subscriptions.
--
-- 0007 limited expert_subscriptions.payment_method to cash/fib. The Apple
-- in-app purchase path (handlers/iap.go → ActivateFromIAP) writes
-- 'apple_iap', so every Apple expert purchase failed this CHECK and the
-- error was ignored: users paid and got nothing. 'google_iap' is added for
-- the Google Play path (models.PaymentMethodGoogleIAP).
BEGIN;

ALTER TABLE expert_subscriptions
    DROP CONSTRAINT IF EXISTS expert_subscriptions_payment_method_check;
ALTER TABLE expert_subscriptions
    ADD CONSTRAINT expert_subscriptions_payment_method_check
    CHECK (payment_method IN ('cash', 'fib', 'apple_iap', 'google_iap'));

COMMIT;
