-- Normalize legacy short migration IDs to avoid recurring drift in Supabase CLI.
-- Removes old 8-digit versions that conflict with normalized 14-digit files.

do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    delete from supabase_migrations.schema_migrations
    where version in ('20260211', '20260223', '20260227');
  end if;

  if to_regclass('supabase_migrations.migrations') is not null then
    delete from supabase_migrations.migrations
    where version in ('20260211', '20260223', '20260227');
  end if;
end
$$;
