create table if not exists public.user_announcements (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null unique references public.problem_reports(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Reply to your problem report',
  body text not null check (char_length(body) between 1 and 8000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_announcements_user_created_idx
  on public.user_announcements(user_id, created_at desc);

alter table public.user_announcements enable row level security;

drop policy if exists user_announcements_read_recipient_or_admin on public.user_announcements;
create policy user_announcements_read_recipient_or_admin
  on public.user_announcements for select to authenticated
  using (user_id = (select auth.uid()) or public.is_active_admin());

drop policy if exists user_announcements_admin_insert on public.user_announcements;
create policy user_announcements_admin_insert
  on public.user_announcements for insert to authenticated
  with check (public.is_active_admin());

drop policy if exists user_announcements_admin_update on public.user_announcements;
create policy user_announcements_admin_update
  on public.user_announcements for update to authenticated
  using (public.is_active_admin())
  with check (public.is_active_admin());

drop policy if exists user_announcements_admin_delete on public.user_announcements;
create policy user_announcements_admin_delete
  on public.user_announcements for delete to authenticated
  using (public.is_active_admin());

revoke all on public.user_announcements from anon, authenticated;
grant select, insert, update, delete on public.user_announcements to authenticated;

create or replace function public.admin_save_problem_report(
  p_report_id uuid,
  p_status text,
  p_admin_note text,
  p_admin_reply text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  recipient_id uuid;
  reply_text text := nullif(btrim(coalesce(p_admin_reply, '')), '');
begin
  if not public.is_active_admin() then
    raise exception 'Active admin access required';
  end if;
  if p_status not in ('new', 'seen', 'in_progress', 'resolved') then
    raise exception 'Invalid report status';
  end if;

  select user_id into recipient_id
    from public.problem_reports
    where id = p_report_id
    for update;
  if not found then
    raise exception 'Problem report not found';
  end if;
  if reply_text is not null and recipient_id is null then
    raise exception 'This report has no signed-in user to receive a private reply';
  end if;

  update public.problem_reports
    set status = p_status,
        admin_note = p_admin_note,
        admin_reply = reply_text
    where id = p_report_id;

  if reply_text is null then
    delete from public.user_announcements where report_id = p_report_id;
  else
    insert into public.user_announcements(report_id, user_id, body, created_at, updated_at)
      values (p_report_id, recipient_id, reply_text, now(), now())
      on conflict (report_id) do update
        set user_id = excluded.user_id,
            body = excluded.body,
            created_at = now(),
            updated_at = now();
  end if;
end;
$$;

revoke all on function public.admin_save_problem_report(uuid, text, text, text) from public, anon;
grant execute on function public.admin_save_problem_report(uuid, text, text, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'user_announcements'
     ) then
    alter publication supabase_realtime add table public.user_announcements;
  end if;
end;
$$;
