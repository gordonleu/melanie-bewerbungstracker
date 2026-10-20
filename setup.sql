-- Setup for a NEW dedicated Supabase project. Access is enabled separately.
begin;
create schema if not exists tracker_private;
revoke all on schema tracker_private from public, anon;
grant usage on schema tracker_private to authenticated;
create table tracker_private.allowed_emails (email text primary key check (email = lower(email)));
alter table tracker_private.allowed_emails enable row level security;
revoke all on tracker_private.allowed_emails from public, anon, authenticated;

create function tracker_private.has_access() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from auth.users u join tracker_private.allowed_emails a on a.email = lower(u.email)
    where u.id = auth.uid() and u.email_confirmed_at is not null
  );
$$;
revoke all on function tracker_private.has_access() from public, anon;
grant execute on function tracker_private.has_access() to authenticated;

create table public.tracker_state (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  applications jsonb not null default '[]',
  documents jsonb not null default '[]',
  revision integer not null default 0 check (revision >= 0),
  updated_at timestamptz not null default now()
);
alter table public.tracker_state enable row level security;
revoke all on public.tracker_state from public, anon, authenticated;
grant select, insert, update on public.tracker_state to authenticated;
create policy tracker_read on public.tracker_state for select to authenticated
using (owner_id = (select auth.uid()) and (select tracker_private.has_access()));
create policy tracker_insert on public.tracker_state for insert to authenticated
with check (owner_id = (select auth.uid()) and (select tracker_private.has_access()));
create policy tracker_update on public.tracker_state for update to authenticated
using (owner_id = (select auth.uid()) and (select tracker_private.has_access()))
with check (owner_id = (select auth.uid()) and (select tracker_private.has_access()));

create function tracker_private.validate_state() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare a jsonb; d jsonb; total_bytes bigint := 0; app_ids text[] := '{}'; doc_ids text[] := '{}'; doc_paths text[] := '{}'; k text;
begin
  if tg_op = 'UPDATE' and (new.owner_id <> old.owner_id or new.revision <> old.revision + 1) then
    raise exception 'INVALID_REVISION';
  end if;
  if tg_op = 'INSERT' and new.revision <> 0 then raise exception 'INVALID_REVISION'; end if;
  if jsonb_typeof(new.applications) is distinct from 'array' or jsonb_typeof(new.documents) is distinct from 'array' then raise exception 'INVALID_DATA'; end if;
  if jsonb_array_length(new.applications)>10000 or jsonb_array_length(new.documents)>1000
     or octet_length(new.applications::text)>10485760 then raise exception 'DATA_LIMIT'; end if;
  for a in select value from jsonb_array_elements(new.applications) loop
    if jsonb_typeof(a) is distinct from 'object' or jsonb_typeof(a->'id') is distinct from 'string'
      or length(a->>'id') not between 1 and 200 or (a->>'id') = any(app_ids)
      or jsonb_typeof(a->'company') is distinct from 'string' or length(trim(a->>'company'))=0
      or jsonb_typeof(a->'role') is distinct from 'string' or length(trim(a->>'role'))=0
      or coalesce(a->>'status','') not in ('Interessant','Beworben','Antwort offen','1. Gespräch','2. Gespräch','Angebot','Absage','Zurückgezogen') then raise exception 'INVALID_APPLICATION'; end if;
    foreach k in array array['company','role','status','appliedDate','workModel','location','salary','url','nextStep','priority','notes'] loop
      if a ? k and (jsonb_typeof(a->k) is distinct from 'string' or length(a->>k)>100000) then raise exception 'INVALID_FIELD'; end if;
    end loop;
    app_ids := array_append(app_ids,a->>'id');
  end loop;
  for d in select value from jsonb_array_elements(new.documents) loop
    if jsonb_typeof(d) is distinct from 'object' or jsonb_typeof(d->'id') is distinct from 'string'
      or length(d->>'id') not between 1 and 200 or (d->>'id') = any(doc_ids)
      or coalesce((d->>'applicationId') = any(app_ids),false) = false
      or jsonb_typeof(d->'name') is distinct from 'string' or length(d->>'name') not between 1 and 1024
      or jsonb_typeof(d->'size') is distinct from 'number' or (d->>'size') !~ '^[0-9]+$'
      or (d->>'size')::bigint not between 1 and 20971520
      or jsonb_typeof(d->'path') is distinct from 'string'
      or (d->>'path') !~ ('^' || new.owner_id::text || '/[0-9a-f-]{36}$')
      or (d->>'path') = any(doc_paths)
      or coalesce(d->>'type','') not in ('application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif','image/bmp','image/tiff') then raise exception 'INVALID_DOCUMENT'; end if;
    total_bytes := total_bytes + (d->>'size')::bigint;
    doc_ids := array_append(doc_ids,d->>'id');doc_paths := array_append(doc_paths,d->>'path');
  end loop;
  if total_bytes>104857600 then raise exception 'DOCUMENT_LIMIT'; end if;
  new.updated_at := now();return new;
end;
$$;
revoke all on function tracker_private.validate_state() from public, anon, authenticated;
create trigger tracker_validate before insert or update on public.tracker_state
for each row execute function tracker_private.validate_state();

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('bewerbungsunterlagen','bewerbungsunterlagen',false,20971520,
array['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif','image/bmp','image/tiff']);
create policy tracker_files_read on storage.objects for select to authenticated
using (bucket_id='bewerbungsunterlagen' and (storage.foldername(name))[1]=(select auth.uid())::text and (select tracker_private.has_access()));
create policy tracker_files_insert on storage.objects for insert to authenticated
with check (bucket_id='bewerbungsunterlagen' and (storage.foldername(name))[1]=(select auth.uid())::text and (select tracker_private.has_access()));
create policy tracker_files_delete on storage.objects for delete to authenticated
using (bucket_id='bewerbungsunterlagen' and (storage.foldername(name))[1]=(select auth.uid())::text and (select tracker_private.has_access()));
-- Restrict Supabase's optional automatic-RLS event-trigger helper.
do $$ begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end $$;
commit;
