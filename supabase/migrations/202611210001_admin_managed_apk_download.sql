-- Keep the website download URL under admin control and sync it from release CI.
alter table public.app_control_settings
  add column if not exists apk_download_url text not null default
    'https://github.com/jomariebernales3-cell/convert2file/releases/download/v3.0.2.31/Convert2File_v3.0.2.31_.apk';

alter table public.app_control_settings
  drop constraint if exists app_control_settings_apk_download_url_check;
alter table public.app_control_settings
  add constraint app_control_settings_apk_download_url_check
  check (char_length(apk_download_url) <= 1000 and apk_download_url ~ '^https://[^[:space:]]+$');

drop function if exists public.admin_update_app_settings(boolean, text, text, jsonb);
create function public.admin_update_app_settings(
  p_maintenance_enabled boolean,
  p_latest_version text,
  p_minimum_supported_version text,
  p_feature_flags jsonb,
  p_apk_download_url text
)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_active_admin() then raise exception 'Administrator access required'; end if;
  if char_length(btrim(p_latest_version)) not between 1 and 32
     or char_length(btrim(p_minimum_supported_version)) not between 1 and 32 then
    raise exception 'Version values must be 1 to 32 characters';
  end if;
  if jsonb_typeof(p_feature_flags) <> 'object' then raise exception 'Feature flags must be an object'; end if;
  if char_length(btrim(p_apk_download_url)) > 1000
     or btrim(p_apk_download_url) !~ '^https://[^[:space:]]+$' then
    raise exception 'APK download URL must be a valid HTTPS URL up to 1000 characters';
  end if;

  update public.app_control_settings set
    maintenance_enabled = p_maintenance_enabled,
    latest_version = btrim(p_latest_version),
    minimum_supported_version = btrim(p_minimum_supported_version),
    feature_flags = p_feature_flags,
    apk_download_url = btrim(p_apk_download_url),
    updated_by = (select auth.uid()), updated_at = now()
  where id = true;
  perform public.write_admin_audit('app_settings.updated', 'app_settings', 'global',
    jsonb_build_object('maintenance_enabled', p_maintenance_enabled,
      'latest_version', btrim(p_latest_version),
      'minimum_supported_version', btrim(p_minimum_supported_version),
      'apk_download_url', btrim(p_apk_download_url),
      'feature_flags', p_feature_flags));
end;
$$;

revoke all on function public.admin_update_app_settings(boolean, text, text, jsonb, text) from public, anon;
grant execute on function public.admin_update_app_settings(boolean, text, text, jsonb, text) to authenticated;

drop function if exists public.ci_publish_app_release_version(text, text);
create function public.ci_publish_app_release_version(
  p_latest_version text,
  p_minimum_supported_version text,
  p_apk_download_url text
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
  if char_length(p_apk_download_url) > 1000
     or p_apk_download_url !~ '^https://[^[:space:]]+$' then
    raise exception 'APK download URL must be a valid HTTPS URL up to 1000 characters';
  end if;

  update public.app_control_settings
  set latest_version = p_latest_version,
      minimum_supported_version = coalesce(p_minimum_supported_version, minimum_supported_version),
      apk_download_url = p_apk_download_url,
      updated_by = null,
      updated_at = now()
  where id = true;
  if not found then raise exception 'App control settings row is missing'; end if;

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
      'apk_download_url', p_apk_download_url,
      'source', 'github_actions'
    )
  );
end;
$$;

revoke all on function public.ci_publish_app_release_version(text, text, text)
  from public, anon, authenticated;
grant execute on function public.ci_publish_app_release_version(text, text, text)
  to service_role;
