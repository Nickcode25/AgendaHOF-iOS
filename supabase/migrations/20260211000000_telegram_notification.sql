-- Create a function to trigger the webhook
create or replace function public.trigger_telegram_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  perform
    net.http_post(
      url := 'https://zgdxszwjbbxepsvyjtrb.supabase.co/functions/v1/telegram-new-user-alert',
      headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnZHhzendqYmJ4ZXBzdnlqdHJiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk0MTU4MTAsImV4cCI6MjA3NDk5MTgxMH0.NZdEYYCOZlMUo5h7TM-gsSTxmgMx7ta9W_gsi7ZNHCA"}'::jsonb,
      body := jsonb_build_object(
        'record', row_to_json(new)
      )
    );
  return new;
end;
$$;
-- Create the trigger on user_profiles table
drop trigger if exists on_new_user_created_telegram on public.user_profiles;
create trigger on_new_user_created_telegram
  after insert on public.user_profiles
  for each row execute procedure public.trigger_telegram_new_user();
