alter table public.announcements
  add column if not exists hide_after_version text null;

comment on column public.announcements.hide_after_version is
  'Hide this announcement from app versions equal to or newer than this dotted numeric version.';
