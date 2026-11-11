-- Normalize report status values for databases where problem_reports existed
-- before all admin status options were added.
do $$
declare
  status_check record;
begin
  for status_check in
    select conname
    from pg_constraint
    where conrelid = 'public.problem_reports'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.problem_reports drop constraint %I', status_check.conname);
  end loop;
end;
$$;

alter table public.problem_reports
  add constraint problem_reports_status_check
  check (status in ('new', 'seen', 'in_progress', 'resolved'));