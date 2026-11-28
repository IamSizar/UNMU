-- Reverts 0059_expert_sub_store_payments.sql. NOT VALID keeps existing
-- store-paid rows (no data is removed); only new rows are held to cash/fib.
BEGIN;
ALTER TABLE expert_subscriptions
    DROP CONSTRAINT IF EXISTS expert_subscriptions_payment_method_check;
ALTER TABLE expert_subscriptions
    ADD CONSTRAINT expert_subscriptions_payment_method_check
    CHECK (payment_method IN ('cash', 'fib')) NOT VALID;
COMMIT;
