-- Keep Save report limited to internal report fields. Sending a user reply is
-- a separate explicit action handled by admin_send_problem_report_reply.
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
begin
  if not public.is_active_admin() then
    raise exception 'Active admin access required';
  end if;
  if p_status not in ('new', 'seen', 'in_progress', 'resolved') then
    raise exception 'Invalid report status';
  end if;

  update public.problem_reports
    set status = p_status,
        admin_note = p_admin_note
    where id = p_report_id;
  if not found then
    raise exception 'Problem report not found';
  end if;
end;
$$;

create or replace function public.admin_send_problem_report_reply(
  p_report_id uuid,
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
  if reply_text is null then
    raise exception 'Write a reply before sending';
  end if;
  if char_length(reply_text) > 8000 then
    raise exception 'Reply cannot exceed 8000 characters';
  end if;

  select user_id into recipient_id
    from public.problem_reports
    where id = p_report_id
    for update;
  if not found then
    raise exception 'Problem report not found';
  end if;
  if recipient_id is null then
    raise exception 'This report has no signed-in user to receive a private reply';
  end if;

  update public.problem_reports
    set admin_reply = reply_text
    where id = p_report_id;

  insert into public.user_announcements(report_id, user_id, body, created_at, updated_at)
    values (p_report_id, recipient_id, reply_text, now(), now())
    on conflict (report_id) do update
      set user_id = excluded.user_id,
          body = excluded.body,
          created_at = now(),
          updated_at = now();
end;
$$;

revoke all on function public.admin_save_problem_report(uuid, text, text, text) from public, anon;
revoke all on function public.admin_send_problem_report_reply(uuid, text) from public, anon;
grant execute on function public.admin_save_problem_report(uuid, text, text, text) to authenticated;
grant execute on function public.admin_send_problem_report_reply(uuid, text) to authenticated;
