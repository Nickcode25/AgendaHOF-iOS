-- Schedule Supabase Edge Function to run daily at 21:00 (São Paulo time)
-- 21:00 BRT (UTC-3) = 00:00 UTC (next day during standard time)
-- Run this SQL in Supabase SQL Editor after deploying the Edge Function

-- Step 1: Store Edge Function URL and service role key in Vault (one-time setup)
-- Replace 'your-project-ref' with your actual Supabase project reference
-- Replace 'your-service-role-key' with your actual service role key from Project Settings > API

-- WARNING: Only run these if the secrets don't already exist!
-- Check existing secrets first with: SELECT name FROM vault.decrypted_secrets;

SELECT vault.create_secret(
  'https://your-project-ref.supabase.co', 
  'supabase_url'
);

SELECT vault.create_secret(
  'your-service-role-key-here',
  'service_role_key'
);

-- Step 2: Schedule the Edge Function to run daily at 00:00 UTC (21:00 BRT)
-- Cron format: minute hour day month weekday
-- '0 0 * * *' = every day at 00:00 UTC

SELECT cron.schedule(
  'daily-financial-notification', -- Job name
  '0 0 * * *',                     -- At 00:00 UTC daily (21:00 BRT)
  $$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') 
           || '/functions/v1/send-daily-financial-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
    ),
    body := '{}'::jsonb
  ) as request_id;
  $$
);

-- Verify the cron job was created
SELECT * FROM cron.job WHERE jobname = 'daily-financial-notification';

-- To view cron job execution history (useful for debugging):
-- SELECT * FROM cron.job_run_details 
-- WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'daily-financial-notification')
-- ORDER BY start_time DESC
-- LIMIT 10;

-- To unschedule/delete the job (if needed):
-- SELECT cron.unschedule('daily-financial-notification');
