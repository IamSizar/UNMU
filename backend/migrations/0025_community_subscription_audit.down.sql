DROP TRIGGER IF EXISTS comm_subs_audit ON community_subscriptions;
DROP TRIGGER IF EXISTS comm_subs_notify ON community_subscriptions;
DROP FUNCTION IF EXISTS audit_community_subscription_change();
DROP FUNCTION IF EXISTS notify_community_subscription_event();
ALTER TABLE community_subscriptions DROP COLUMN IF EXISTS receipt_url;
