-- Let active admin portal users read and update reports submitted by the app.
drop policy if exists problem_reports_admin_read on public.problem_reports;
create policy problem_reports_admin_read
  on public.problem_reports for select to authenticated
  using (public.is_active_admin());

drop policy if exists problem_reports_admin_update on public.problem_reports;
create policy problem_reports_admin_update
  on public.problem_reports for update to authenticated
  using (public.is_active_admin())
  with check (public.is_active_admin());

grant select, update on public.problem_reports to authenticated;
