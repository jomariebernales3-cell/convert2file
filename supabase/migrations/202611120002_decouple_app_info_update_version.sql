-- App Info history labels are descriptive text and must not control APK updates.
-- Restore the APK update setting when it was copied from the current history entry.
update public.app_control_settings as controls
set latest_version = '1.0.26',
    updated_at = now()
where controls.id = true
  and controls.latest_version is distinct from '1.0.26'
  and exists (
    select 1
    from public.app_info_content as info,
         jsonb_array_elements(info.release_notes) as history_entry(item)
    where info.id = true
      and history_entry.item->>'is_latest' = 'true'
      and history_entry.item->>'version' = controls.latest_version
  );

create or replace function public.admin_update_app_info(
  p_sections jsonb,
  p_release_notes jsonb
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  section_item jsonb;
  release_item jsonb;
  latest_count integer;
  current_release_version text;
begin
  if not public.is_active_admin() then
    raise exception 'Administrator access required';
  end if;
  if coalesce(jsonb_typeof(p_sections), '') <> 'array' then
    raise exception 'App Info sections must be an array';
  end if;
  if jsonb_array_length(p_sections) not between 1 and 30 then
    raise exception 'Add between 1 and 30 App Info sections';
  end if;
  if coalesce(jsonb_typeof(p_release_notes), '') <> 'array' then
    raise exception 'Release history must be an array';
  end if;
  if jsonb_array_length(p_release_notes) not between 1 and 100 then
    raise exception 'Add between 1 and 100 release entries';
  end if;
  for section_item in select value from jsonb_array_elements(p_sections) loop
    if jsonb_typeof(section_item) <> 'object'
       or char_length(btrim(coalesce(section_item->>'title', ''))) not between 1 and 80
       or coalesce(jsonb_typeof(section_item->'details'), '') <> 'array'
       or jsonb_array_length(section_item->'details') < 1 then
      raise exception 'Each section needs a title and at least one detail';
    end if;
  end loop;
  for release_item in select value from jsonb_array_elements(p_release_notes) loop
    if jsonb_typeof(release_item) <> 'object'
       or char_length(btrim(coalesce(release_item->>'version', ''))) not between 1 and 32
       or char_length(btrim(coalesce(release_item->>'date', ''))) not between 1 and 64
       or coalesce(jsonb_typeof(release_item->'features'), '') <> 'array'
       or coalesce(jsonb_typeof(release_item->'fixes'), '') <> 'array' then
      raise exception 'Each release entry needs a version, date, features, and fixes';
    end if;
  end loop;
  select count(*), max(item->>'version') into latest_count, current_release_version
    from jsonb_array_elements(p_release_notes) as releases(item)
    where item->>'is_latest' = 'true';
  if latest_count <> 1 then
    raise exception 'Mark exactly one release entry as the current version';
  end if;
  update public.app_info_content
    set sections = p_sections,
        release_notes = p_release_notes,
        updated_by = (select auth.uid()),
        updated_at = now()
    where id = true;
  perform public.write_admin_audit(
    'app_info.updated', 'app_info', 'global',
    jsonb_build_object(
      'section_count', jsonb_array_length(p_sections),
      'release_count', jsonb_array_length(p_release_notes),
      'current_version', current_release_version
    )
  );
end;
$$;

revoke all on function public.admin_update_app_info(jsonb, jsonb) from public, anon;
grant execute on function public.admin_update_app_info(jsonb, jsonb) to authenticated;
