-- Convert2File 1.0.27 (build 30) version and release notes.
update public.app_control_settings
set latest_version = '1.0.27', updated_at = now()
where id = true and latest_version = '1.0.26';

update public.app_info_content as info
set release_notes = (
      select coalesce(
        jsonb_agg(
          case
            when release.item->>'is_latest' = 'true'
              then jsonb_set(release.item, '{is_latest}', 'false'::jsonb)
            else release.item
          end
          order by release.ordinality
        ),
        '[]'::jsonb
      )
      from jsonb_array_elements(info.release_notes)
        with ordinality as release(item, ordinality)
    ) || jsonb_build_array(
      jsonb_build_object(
        'version', '1.0.27.30',
        'date', 'November 19, 2026',
        'is_latest', true,
        'features', jsonb_build_array(
          'Let users attach screenshots to problem reports, including reports saved while offline.',
          'Show Online Maintenance in the home greeting area with a wrench icon for guest and signed-in users.'
        ),
        'fixes', jsonb_build_array(
          'Show cached Update History immediately while refreshing managed content online.',
          'Display the current app version in Settings and explain when sign-in needs an internet connection.',
          'Require new and reset passwords to use at least 8 characters and one special character.'
        )
      )
    ),
    updated_at = now()
where info.id = true
  and jsonb_typeof(info.release_notes) = 'array'
  and not exists (
    select 1
    from jsonb_array_elements(info.release_notes) as release(item)
    where release.item->>'version' = '1.0.27.30'
  );
