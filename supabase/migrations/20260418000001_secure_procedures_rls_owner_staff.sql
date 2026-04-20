-- Garantir isolamento por clínica para procedures:
-- - owner acessa registros com user_id = auth.uid()
-- - staff acessa registros com user_id = parent_user_id (owner)

begin;
create or replace function public.current_owner_user_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(parent_user_id, id)
  from public.user_profiles
  where id = auth.uid()
  limit 1
$$;
revoke all on function public.current_owner_user_id() from public;
grant execute on function public.current_owner_user_id() to authenticated, service_role;
alter table public.procedures enable row level security;
grant select, insert, update, delete on table public.procedures to authenticated, service_role;
-- Compatibilidade de defaults esperados no app iOS
alter table public.procedures
  alter column stock_categories set default '[]'::jsonb;
-- Se existir valor inválido antigo, remove constraint e recria no formato atual
alter table public.procedures
  drop constraint if exists procedures_return_interval_unit_check;
alter table public.procedures
  add constraint procedures_return_interval_unit_check
  check (
    return_interval_unit is null
    or return_interval_unit in ('days', 'weeks', 'months')
  );
-- Remove todas as policies existentes para evitar regras antigas conflitantes
do $$
declare
  p record;
begin
  for p in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'procedures'
  loop
    execute format('drop policy if exists %I on public.procedures', p.policyname);
  end loop;
end $$;
create policy procedures_select_owner_or_staff
on public.procedures
for select
to authenticated
using (
  auth.uid() is not null
  and user_id = public.current_owner_user_id()
);
create policy procedures_insert_owner_or_staff
on public.procedures
for insert
to authenticated
with check (
  auth.uid() is not null
  and user_id = public.current_owner_user_id()
);
create policy procedures_update_owner_or_staff
on public.procedures
for update
to authenticated
using (
  auth.uid() is not null
  and user_id = public.current_owner_user_id()
)
with check (
  auth.uid() is not null
  and user_id = public.current_owner_user_id()
);
create policy procedures_delete_owner_or_staff
on public.procedures
for delete
to authenticated
using (
  auth.uid() is not null
  and user_id = public.current_owner_user_id()
);
create index if not exists idx_procedures_user_active_name
  on public.procedures (user_id, is_active, name);
commit;
