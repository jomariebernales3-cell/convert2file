-- Adds announcement publishing and remote app-control settings to the admin portal.
-- Apply after 202611090001_admin_portal.sql in the new Supabase project.

create table if not exists public.admin_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 180),
  message text not null check (char_length(message) between 1 and 4000),
  status text not null default 'active' check (status in ('active', 'ended')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists admin_announcements_created_idx
  on public.admin_announcements(created_at desc);

create table if not exists public.app_control_settings (
  id boolean primary key default true check (id),
  maintenance_enabled boolean not null default false,
  latest_version text not null default '1.0.0',
  minimum_supported_version text not null default '1.0.0',
  feature_flags jsonb not null default '{"offline_ai":true,"quiz_generator":true,"study_guides":true,"document_conversion":true}'::jsonb,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.app_control_settings(id) values (true) on conflict (id) do nothing;

alter table public.admin_announcements enable row level security;
alter table public.app_control_settings enable row level security;

drop policy if exists announcements_public_active_read on public.admin_announcements;
create policy announcements_public_active_read on public.admin_announcements
  for select to anon, authenticated using (status = 'active');
drop policy if exists announcements_admin_read on public.admin_announcements;
create policy announcements_admin_read on public.admin_announcements
  for select to authenticated using (public.is_active_admin());
drop policy if exists app_settings_public_read on public.app_control_settings;
create policy app_settings_public_read on public.app_control_settings
  for select to anon, authenticated using (true);

revoke all on public.admin_announcements from anon, authenticated;
revoke all on public.app_control_settings from anon, authenticated;
grant select on public.admin_announcements, public.app_control_settings to anon, authenticated;

create or replace function public.admin_publish_announcement(p_title text, p_message text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare new_id uuid;
begin
  if not public.is_active_admin() then raise exception 'Administrator access required'; end if;
  if char_length(btrim(p_title)) not between 1 and 180 then raise exception 'Title must be 1 to 180 characters'; end if;
  if char_length(btrim(p_message)) not between 1 and 4000 then raise exception 'Message must be 1 to 4000 characters'; end if;
  insert into public.admin_announcements(title, message, created_by)
  values (btrim(p_title), btrim(p_message), (select auth.uid())) returning id into new_id;
  perform public.write_admin_audit('announcement.published', 'announcement', new_id::text,
    jsonb_build_object('title', btrim(p_title)));
  return new_id;
end;
$$;

create or replace function public.admin_end_announcement(p_announcement_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare announcement_title text;
begin
  if not public.is_active_admin() then raise exception 'Administrator access required'; end if;
  update public.admin_announcements set status = 'ended', ended_at = now()
    where id = p_announcement_id and status = 'active' returning title into announcement_title;
  if not found then raise exception 'Active announcement not found'; end if;
  perform public.write_admin_audit('announcement.ended', 'announcement', p_announcement_id::text,
    jsonb_build_object('title', announcement_title));
end;
$$;

create or replace function public.admin_update_app_settings(
  p_maintenance_enabled boolean,
  p_latest_version text,
  p_minimum_supported_version text,
  p_feature_flags jsonb
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
  update public.app_control_settings set
    maintenance_enabled = p_maintenance_enabled,
    latest_version = btrim(p_latest_version),
    minimum_supported_version = btrim(p_minimum_supported_version),
    feature_flags = p_feature_flags,
    updated_by = (select auth.uid()), updated_at = now()
  where id = true;
  perform public.write_admin_audit('app_settings.updated', 'app_settings', 'global',
    jsonb_build_object('maintenance_enabled', p_maintenance_enabled,
      'latest_version', btrim(p_latest_version),
      'minimum_supported_version', btrim(p_minimum_supported_version),
      'feature_flags', p_feature_flags));
end;
$$;

revoke all on function public.admin_publish_announcement(text, text) from public, anon;
revoke all on function public.admin_end_announcement(uuid) from public, anon;
revoke all on function public.admin_update_app_settings(boolean, text, text, jsonb) from public, anon;
grant execute on function public.admin_publish_announcement(text, text) to authenticated;
grant execute on function public.admin_end_announcement(uuid) to authenticated;
grant execute on function public.admin_update_app_settings(boolean, text, text, jsonb) to authenticated;
