create extension if not exists pgcrypto;
create table if not exists public.clinical_evolutions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  date timestamptz not null,
  professional_name text not null,
  evolution_type text not null check (evolution_type in ('consultation', 'procedure', 'follow_up', 'complication', 'other')),
  subjective text,
  objective text,
  assessment text,
  plan text,
  procedure_performed text,
  products_used text,
  dosage text,
  application_areas text,
  observations text,
  complications text,
  next_appointment_date timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);
create table if not exists public.medical_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  photo_url text not null,
  photo_type text not null check (photo_type in ('before', 'after', 'during', 'complication')),
  procedure_name text,
  body_area text,
  clinical_evolution_id uuid references public.clinical_evolutions(id) on delete set null,
  description text,
  taken_at timestamptz not null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);
create table if not exists public.patient_compare_layouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  before_photo_id uuid not null references public.medical_photos(id) on delete cascade,
  after_photo_id uuid not null references public.medical_photos(id) on delete cascade,
  before_view jsonb not null default '{}'::jsonb,
  after_view jsonb not null default '{}'::jsonb,
  divider_position double precision not null default 0.5 check (divider_position >= 0 and divider_position <= 1),
  saved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint patient_compare_layouts_distinct_photos check (before_photo_id <> after_photo_id)
);
create unique index if not exists ux_patient_compare_layouts_pair
on public.patient_compare_layouts (user_id, patient_id, before_photo_id, after_photo_id);
create index if not exists idx_medical_photos_patient_taken_at
on public.medical_photos (patient_id, taken_at desc);
create index if not exists idx_medical_photos_user_id
on public.medical_photos (user_id);
create index if not exists idx_clinical_evolutions_patient_date
on public.clinical_evolutions (patient_id, date desc);
create index if not exists idx_clinical_evolutions_user_id
on public.clinical_evolutions (user_id);
create index if not exists idx_patient_compare_layouts_patient_saved_at
on public.patient_compare_layouts (patient_id, saved_at desc);
create index if not exists idx_patient_compare_layouts_user_id
on public.patient_compare_layouts (user_id);
do $$
begin
  if not exists (
    select 1
    from pg_proc
    where proname = 'set_row_updated_at'
      and pronamespace = 'public'::regnamespace
  ) then
    create function public.set_row_updated_at()
    returns trigger
    language plpgsql
    as $fn$
    begin
      new.updated_at = now();
      return new;
    end;
    $fn$;
  end if;
end $$;
drop trigger if exists trg_clinical_evolutions_updated_at on public.clinical_evolutions;
create trigger trg_clinical_evolutions_updated_at
before update on public.clinical_evolutions
for each row
execute function public.set_row_updated_at();
drop trigger if exists trg_patient_compare_layouts_updated_at on public.patient_compare_layouts;
create trigger trg_patient_compare_layouts_updated_at
before update on public.patient_compare_layouts
for each row
execute function public.set_row_updated_at();
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
grant select, insert, update, delete on table public.clinical_evolutions to authenticated, service_role;
grant select, insert, update, delete on table public.medical_photos to authenticated, service_role;
grant select, insert, update, delete on table public.patient_compare_layouts to authenticated, service_role;
alter table public.clinical_evolutions enable row level security;
alter table public.medical_photos enable row level security;
alter table public.patient_compare_layouts enable row level security;
drop policy if exists clinical_evolutions_select on public.clinical_evolutions;
create policy clinical_evolutions_select on public.clinical_evolutions
for select to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists clinical_evolutions_insert on public.clinical_evolutions;
create policy clinical_evolutions_insert on public.clinical_evolutions
for insert to authenticated
with check (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists clinical_evolutions_update on public.clinical_evolutions;
create policy clinical_evolutions_update on public.clinical_evolutions
for update to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
)
with check (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists clinical_evolutions_delete on public.clinical_evolutions;
create policy clinical_evolutions_delete on public.clinical_evolutions
for delete to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists medical_photos_select on public.medical_photos;
create policy medical_photos_select on public.medical_photos
for select to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists medical_photos_insert on public.medical_photos;
create policy medical_photos_insert on public.medical_photos
for insert to authenticated
with check (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists medical_photos_update on public.medical_photos;
create policy medical_photos_update on public.medical_photos
for update to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
)
with check (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists medical_photos_delete on public.medical_photos;
create policy medical_photos_delete on public.medical_photos
for delete to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists patient_compare_layouts_select on public.patient_compare_layouts;
create policy patient_compare_layouts_select on public.patient_compare_layouts
for select to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists patient_compare_layouts_insert on public.patient_compare_layouts;
create policy patient_compare_layouts_insert on public.patient_compare_layouts
for insert to authenticated
with check (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists patient_compare_layouts_update on public.patient_compare_layouts;
create policy patient_compare_layouts_update on public.patient_compare_layouts
for update to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
)
with check (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
drop policy if exists patient_compare_layouts_delete on public.patient_compare_layouts;
create policy patient_compare_layouts_delete on public.patient_compare_layouts
for delete to authenticated
using (
  auth.uid() is not null
  and user_id::text = public.current_owner_user_id()::text
);
