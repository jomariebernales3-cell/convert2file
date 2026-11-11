create table if not exists public.problem_reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid null default auth.uid(),
  reporter_email text null,
  area text not null check (area in (
    'conversion', 'study_guide', 'quiz', 'qr_code', 'text_to_file',
    'my_materials', 'offline_ai', 'login', 'settings', 'other'
  )),
  description text not null check (char_length(description) between 10 and 2000),
  app_version text,
  platform text,
  device_info text,
  context jsonb not null default '{}',
  source_file_path text null,
  output_file_path text null,
  status text not null default 'new' check (status in ('new', 'seen', 'in_progress', 'resolved')),
  admin_note text null
);

alter table public.problem_reports enable row level security;

drop policy if exists problem_reports_public_insert on public.problem_reports;
create policy problem_reports_public_insert
  on public.problem_reports for insert to anon, authenticated
  with check (status = 'new' and (user_id is null or user_id = (select auth.uid())));

drop policy if exists problem_reports_admin_read on public.problem_reports;
create policy problem_reports_admin_read
  on public.problem_reports for select to authenticated
  using (public.is_active_admin());

drop policy if exists problem_reports_admin_update on public.problem_reports;
create policy problem_reports_admin_update
  on public.problem_reports for update to authenticated
  using (public.is_active_admin())
  with check (public.is_active_admin());

grant insert on public.problem_reports to anon, authenticated;
grant select, update on public.problem_reports to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('report-files', 'report-files', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists report_files_client_insert on storage.objects;
create policy report_files_client_insert
  on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'report-files' and (storage.foldername(name))[1] = 'reports');

drop policy if exists report_files_admin_read on storage.objects;
create policy report_files_admin_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'report-files'
    and exists (
      select 1 from public.admin_users au
      join public.profiles p on p.id = au.user_id
      where au.user_id = (select auth.uid()) and p.account_status = 'active'
    )
  );

-- Reports can be inserted anonymously or by signed-in users. Only active
-- accounts listed in public.admin_users can read or update report records/files.
