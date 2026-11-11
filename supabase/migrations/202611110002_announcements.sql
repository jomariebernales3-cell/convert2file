create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  title text not null check (char_length(title) <= 80),
  body text not null check (char_length(body) <= 600),
  kind text not null default 'info' check (kind in ('info', 'important', 'maintenance')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz null,
  is_active boolean not null default true,
  link_url text null,
  link_label text null
);

alter table public.announcements enable row level security;

create policy announcements_public_active_read
  on public.announcements for select to anon, authenticated
  using (
    is_active
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
  );

create policy announcements_admin_read
  on public.announcements for select to authenticated
  using (
    exists (
      select 1 from public.admin_users au
      join public.profiles p on p.id = au.user_id
      where au.user_id = (select auth.uid())
        and p.account_status = 'active'
    )
  );

create policy announcements_admin_insert
  on public.announcements for insert to authenticated
  with check (
    exists (
      select 1 from public.admin_users au
      join public.profiles p on p.id = au.user_id
      where au.user_id = (select auth.uid())
        and p.account_status = 'active'
    )
  );

create policy announcements_admin_update
  on public.announcements for update to authenticated
  using (
    exists (
      select 1 from public.admin_users au
      join public.profiles p on p.id = au.user_id
      where au.user_id = (select auth.uid())
        and p.account_status = 'active'
    )
  )
  with check (
    exists (
      select 1 from public.admin_users au
      join public.profiles p on p.id = au.user_id
      where au.user_id = (select auth.uid())
        and p.account_status = 'active'
    )
  );

create policy announcements_admin_delete
  on public.announcements for delete to authenticated
  using (
    exists (
      select 1 from public.admin_users au
      join public.profiles p on p.id = au.user_id
      where au.user_id = (select auth.uid())
        and p.account_status = 'active'
    )
  );

grant select on public.announcements to anon, authenticated;
grant insert, update, delete on public.announcements to authenticated;

-- To grant admin access in SQL Editor, replace the email below with the
-- existing account's email (it must already exist in auth.users):
-- insert into public.admin_users(user_id, role)
-- select id, 'admin' from auth.users
-- where lower(email) = lower('YOUR_ADMIN_EMAIL')
-- on conflict (user_id) do update set role = excluded.role;
