-- ============================================================
-- Migration: Add missing columns to fix Railway webhook errors
-- Issues fixed:
--   1. cancel_at_period_end missing from user_subscriptions
--   2. cancelled_at missing from user_subscriptions
--   3. subscription_id missing from payment_history
-- ============================================================

-- 1. Add cancel_at_period_end to user_subscriptions
ALTER TABLE user_subscriptions
  ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE;
-- 2. Add cancelled_at to user_subscriptions
ALTER TABLE user_subscriptions
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
-- 3. Add subscription_id to payment_history
--    (stores the Stripe subscription ID for recurring payments)
ALTER TABLE payment_history
  ADD COLUMN IF NOT EXISTS subscription_id TEXT;
-- Index for faster lookups by subscription_id
CREATE INDEX IF NOT EXISTS idx_payment_history_subscription_id
  ON payment_history(subscription_id);
-- Comment
COMMENT ON COLUMN user_subscriptions.cancel_at_period_end IS 'True when the subscription is set to cancel at the end of the current billing period (from Stripe cancel_at_period_end)';
COMMENT ON COLUMN user_subscriptions.cancelled_at IS 'Timestamp when the subscription was cancelled';
COMMENT ON COLUMN payment_history.subscription_id IS 'Stripe subscription ID (sub_xxx) for recurring payments';
