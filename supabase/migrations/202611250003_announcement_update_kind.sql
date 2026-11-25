alter table public.announcements
  drop constraint if exists announcements_kind_check;

alter table public.announcements
  add constraint announcements_kind_check
  check (kind in ('info', 'update', 'important', 'maintenance'));
