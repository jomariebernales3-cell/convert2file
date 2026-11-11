-- Admin-only bulk deletion for app-submitted problem reports.
-- Each removed report is recorded individually in the existing audit log.
create or replace function public.admin_delete_problem_reports(p_report_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report record;
  v_deleted integer := 0;
  v_scope text;
begin
  if not public.is_active_admin() then
    raise exception 'Administrator access required';
  end if;

  if p_report_ids is not null and cardinality(p_report_ids) = 0 then
    return 0;
  end if;

  v_scope := case
    when p_report_ids is null then 'all'
    when cardinality(p_report_ids) = 1 then 'individual'
    else 'selected'
  end;

  for v_report in
    select r.id, r.area
    from public.problem_reports as r
    where p_report_ids is null or r.id = any(p_report_ids)
    for update
  loop
    perform public.write_admin_audit(
      'problem_report.deleted',
      'problem_report',
      v_report.id::text,
      jsonb_build_object('area', v_report.area, 'scope', v_scope)
    );

    delete from public.problem_reports where id = v_report.id;
    v_deleted := v_deleted + 1;
  end loop;

  return v_deleted;
end;
$$;

revoke all on function public.admin_delete_problem_reports(uuid[]) from public, anon;
grant execute on function public.admin_delete_problem_reports(uuid[]) to authenticated;
