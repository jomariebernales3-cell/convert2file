alter table public.problem_reports
  add column if not exists admin_reply text;

alter table public.problem_reports
  drop constraint if exists problem_reports_admin_reply_length_check;
alter table public.problem_reports
  add constraint problem_reports_admin_reply_length_check
  check (admin_reply is null or char_length(admin_reply) <= 8000);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'problem_reports'
     ) then
    alter publication supabase_realtime add table public.problem_reports;
  end if;
end;
$$;
