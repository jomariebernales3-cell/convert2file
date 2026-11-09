-- Convert2File admin portal schema for a NEW Supabase project.
-- Apply only to the new project after creating its first user account.
-- No existing tables or data are dropped by this migration.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null default '',
  account_status text not null default 'active'
    check (account_status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'admin')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.bug_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 4 and 180),
  description text not null check (char_length(description) between 12 and 12000),
  app_version text not null default 'unknown',
  device_info jsonb not null default '{}'::jsonb,
  status text not null default 'new'
    check (status in ('new', 'in_review', 'resolved')),
  admin_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists profiles_created_at_idx on public.profiles(created_at desc);
create index if not exists bug_reports_status_created_idx on public.bug_reports(status, created_at desc);
create index if not exists bug_reports_user_created_idx on public.bug_reports(user_id, created_at desc);
create index if not exists admin_audit_created_idx on public.admin_audit_log(created_at desc);

create or replace function public.is_active_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users au
    join public.profiles p on p.id = au.user_id
    where au.user_id = (select auth.uid())
      and p.account_status = 'active'
  );
$$;

create or replace function public.is_owner()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users au
    join public.profiles p on p.id = au.user_id
    where au.user_id = (select auth.uid())
      and au.role = 'owner'
      and p.account_status = 'active'
  );
$$;

revoke all on function public.is_active_admin() from public;
revoke all on function public.is_owner() from public;
grant execute on function public.is_active_admin() to authenticated;
grant execute on function public.is_owner() to authenticated;

create or replace function public.handle_auth_user_profile()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name, created_at, updated_at)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'name', split_part(coalesce(new.email, ''), '@', 1)),
    coalesce(new.created_at, now()),
    now()
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = case
      when public.profiles.display_name = '' then excluded.display_name
      else public.profiles.display_name
    end,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_profile_created on auth.users;
drop trigger if exists on_auth_user_profile_updated on auth.users;
create trigger on_auth_user_profile_created
  after insert on auth.users
  for each row execute function public.handle_auth_user_profile();
create trigger on_auth_user_profile_updated
  after update of email, raw_user_meta_data on auth.users
  for each row execute function public.handle_auth_user_profile();

insert into public.profiles (id, email, display_name, created_at, updated_at)
select id, coalesce(email, ''),
       coalesce(raw_user_meta_data ->> 'name', split_part(coalesce(email, ''), '@', 1)),
       coalesce(created_at, now()), now()
from auth.users
on conflict (id) do nothing;

create or replace function public.write_admin_audit(
  p_action text, p_target_type text, p_target_id text, p_details jsonb default '{}'::jsonb
)
returns void
language sql security definer
set search_path = ''
as $$
  insert into public.admin_audit_log(actor_id, action, target_type, target_id, details)
  values ((select auth.uid()), p_action, p_target_type, p_target_id, coalesce(p_details, '{}'::jsonb));
$$;

create or replace function public.admin_set_user_status(p_user_id uuid, p_status text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare previous_status text;
        target_admin_role text;
begin
  if not public.is_active_admin() then raise exception 'Administrator access required'; end if;
  if p_status not in ('active', 'suspended') then raise exception 'Invalid account status'; end if;
  if p_user_id = (select auth.uid()) and p_status = 'suspended' then
    raise exception 'You cannot suspend your own account';
  end if;
  select account_status into previous_status from public.profiles where id = p_user_id for update;
  if not found then raise exception 'Account not found'; end if;
  select role into target_admin_role from public.admin_users where user_id = p_user_id;
  if target_admin_role is not null and not public.is_owner() then
    raise exception 'Only the Owner can suspend or reactivate an administrator';
  end if;
  if target_admin_role = 'owner' and p_status = 'suspended'
      and (select count(*) from public.admin_users au
           join public.profiles p on p.id = au.user_id
           where au.role = 'owner' and p.account_status = 'active') <= 1 then
    raise exception 'The last active Owner cannot be suspended';
  end if;
  update public.profiles set account_status = p_status, updated_at = now() where id = p_user_id;
  perform public.write_admin_audit(
    case when p_status = 'suspended' then 'user.suspended' else 'user.reactivated' end,
    'profile', p_user_id::text,
    jsonb_build_object('previous_status', previous_status, 'status', p_status)
  );
end;
$$;

create or replace function public.admin_set_report(
  p_report_id uuid, p_status text, p_admin_notes text default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare previous_status text;
begin
  if not public.is_active_admin() then raise exception 'Administrator access required'; end if;
  if p_status not in ('new', 'in_review', 'resolved') then raise exception 'Invalid report status'; end if;
  select status into previous_status from public.bug_reports where id = p_report_id for update;
  if not found then raise exception 'Bug report not found'; end if;
  update public.bug_reports
    set status = p_status,
        admin_notes = coalesce(p_admin_notes, admin_notes),
        updated_at = now()
    where id = p_report_id;
  perform public.write_admin_audit('bug_report.updated', 'bug_report', p_report_id::text,
    jsonb_build_object('previous_status', previous_status, 'status', p_status));
end;
$$;

create or replace function public.owner_set_admin_role(p_user_id uuid, p_role text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare old_role text;
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  if p_role not in ('owner', 'admin', 'user') then raise exception 'Invalid role'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Account not found. The user must create an account first.';
  end if;
  select role into old_role from public.admin_users where user_id = p_user_id;
  if p_role = 'user' then
    if old_role = 'owner' and (select count(*) from public.admin_users where role = 'owner') <= 1 then
      raise exception 'The last owner cannot be removed';
    end if;
    delete from public.admin_users where user_id = p_user_id;
  else
    if p_role = 'admin' and old_role = 'owner'
        and (select count(*) from public.admin_users where role = 'owner') <= 1 then
      raise exception 'The last owner cannot be demoted';
    end if;
    insert into public.admin_users(user_id, role, created_by)
    values (p_user_id, p_role, (select auth.uid()))
    on conflict (user_id) do update set role = excluded.role, created_by = excluded.created_by;
  end if;
  perform public.write_admin_audit('admin.role_changed', 'admin_user', p_user_id::text,
    jsonb_build_object('previous_role', old_role, 'role', p_role));
end;
$$;

create or replace function public.record_my_login()
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  update public.profiles set last_seen_at = now(), updated_at = now() where id = (select auth.uid());
end;
$$;

revoke all on function public.write_admin_audit(text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.admin_set_user_status(uuid, text) from public, anon;
revoke all on function public.admin_set_report(uuid, text, text) from public, anon;
revoke all on function public.owner_set_admin_role(uuid, text) from public, anon;
revoke all on function public.record_my_login() from public, anon;
grant execute on function public.admin_set_user_status(uuid, text) to authenticated;
grant execute on function public.admin_set_report(uuid, text, text) to authenticated;
grant execute on function public.owner_set_admin_role(uuid, text) to authenticated;
grant execute on function public.record_my_login() to authenticated;

alter table public.profiles enable row level security;
alter table public.admin_users enable row level security;
alter table public.bug_reports enable row level security;
alter table public.admin_audit_log enable row level security;

drop policy if exists profiles_read_self_or_admin on public.profiles;
create policy profiles_read_self_or_admin on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_active_admin());
drop policy if exists profiles_update_own_name on public.profiles;
create policy profiles_update_own_name on public.profiles for update to authenticated
  using (id = (select auth.uid()) and account_status = 'active')
  with check (id = (select auth.uid()) and account_status = 'active');

drop policy if exists admins_read_admins on public.admin_users;
create policy admins_read_admins on public.admin_users for select to authenticated
  using (user_id = (select auth.uid()) or public.is_owner());

drop policy if exists reports_read_own_or_admin on public.bug_reports;
create policy reports_read_own_or_admin on public.bug_reports for select to authenticated
  using ((user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.account_status = 'active'
  )) or public.is_active_admin());
drop policy if exists reports_insert_own_active on public.bug_reports;
create policy reports_insert_own_active on public.bug_reports for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.account_status = 'active'
  ));

drop policy if exists audit_read_admin on public.admin_audit_log;
create policy audit_read_admin on public.admin_audit_log for select to authenticated
  using (public.is_active_admin());

revoke all on public.profiles from anon, authenticated;
revoke all on public.admin_users from anon, authenticated;
revoke all on public.bug_reports from anon, authenticated;
revoke all on public.admin_audit_log from anon, authenticated;
grant select on public.profiles, public.admin_users, public.bug_reports, public.admin_audit_log to authenticated;
grant insert (user_id, title, description, app_version, device_info) on public.bug_reports to authenticated;
grant update (display_name) on public.profiles to authenticated;

-- Bootstrap exactly one Owner after creating/signing up that account.
-- Run manually in the Supabase SQL Editor as the project database owner:
-- insert into public.admin_users(user_id, role)
-- select id, 'owner' from auth.users where lower(email) = lower('YOUR_OWNER_EMAIL');
