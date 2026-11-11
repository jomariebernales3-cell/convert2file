-- Enable Supabase Realtime events for admin-controlled app settings.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_control_settings'
  ) then
    execute 'alter publication supabase_realtime add table public.app_control_settings';
  end if;
end
$$;
