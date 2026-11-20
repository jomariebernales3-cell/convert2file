-- Lets the release workflow update only the latest/minimum version fields.
-- The minimum stays unchanged unless the workflow explicitly enables enforcement.
create or replace function public.ci_publish_app_release_version(
  p_latest_version text,
  p_minimum_supported_version text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(p_latest_version, '') !~ '^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' then
    raise exception 'Latest version must be v followed by four numeric parts';
  end if;
  if p_minimum_supported_version is not null
     and p_minimum_supported_version !~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' then
    raise exception 'Minimum version must contain four numeric parts';
  end if;

  update public.app_control_settings
  set latest_version = p_latest_version,
      minimum_supported_version = coalesce(
        p_minimum_supported_version,
        minimum_supported_version
      ),
      updated_by = null,
      updated_at = now()
  where id = true;

  if not found then
    raise exception 'App control settings row is missing';
  end if;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, details)
  values (
    null,
    'app_settings.release_published',
    'app_settings',
    'global',
    jsonb_build_object(
      'latest_version', p_latest_version,
      'minimum_supported_version', p_minimum_supported_version,
      'minimum_enforced', p_minimum_supported_version is not null,
      'source', 'github_actions'
    )
  );
end;
$$;

revoke all on function public.ci_publish_app_release_version(text, text)
  from public, anon, authenticated;
grant execute on function public.ci_publish_app_release_version(text, text)
  to service_role;
