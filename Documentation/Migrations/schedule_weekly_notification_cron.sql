-- Schedule Weekly Financial Notification
-- Sends every Saturday at 22:00 (horário de Brasília)
-- Cron: 0 1 * * 6 = 01:00 UTC on Saturday = 22:00 BRT on Friday (wait, need to check conversion)
-- Actually: 22:00 BRT = 01:00 UTC next day
-- Saturday 22:00 BRT = Sunday 01:00 UTC
-- So cron should be: 0 1 * * 0 (Sunday at 01:00 UTC)

SELECT cron.schedule(
  'weekly-financial-notification-saturday-22h',
  '0 1 * * 0', -- Sunday 01:00 UTC = Saturday 22:00 BRT
  $$
  SELECT
    net.http_post(
      url := 'https://zgdxszwjbbxepsvyjtrb.supabase.co/functions/v1/send-weekly-financial-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnZHhzendqYmJ4ZXBzdnlqdHJiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1OTQxNTgxMCwiZXhwIjoyMDc0OTkxODEwfQ.SGMcaNsBiLa4jl2cL9Bq6KCJfzrZJdhWZKyuNRx1ebs'
      )
    ) as request_id;
  $$
);

-- Verify the cron job was created:
-- SELECT * FROM cron.job WHERE jobname = 'weekly-financial-notification-saturday-22h';
