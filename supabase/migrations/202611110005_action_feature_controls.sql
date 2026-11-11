-- Add the remaining Home action switches to remotely managed app controls.
-- Existing users get enabled defaults; admins can disable each switch afterwards.
alter table public.app_control_settings
  alter column feature_flags set default '{"offline_ai":true,"quiz_generator":true,"study_guides":true,"document_conversion":true,"qr_code":true,"text_to_file":true,"my_materials":true}'::jsonb;

update public.app_control_settings
set feature_flags = coalesce(feature_flags, '{}'::jsonb) || jsonb_build_object(
      'qr_code', coalesce(feature_flags -> 'qr_code', 'true'::jsonb),
      'text_to_file', coalesce(feature_flags -> 'text_to_file', 'true'::jsonb),
      'my_materials', coalesce(feature_flags -> 'my_materials', 'true'::jsonb)
    ),
    updated_at = now()
where id = true;
