-- Run this in Supabase SQL Editor.
-- It lets logged-in admins list all Auth users for the mobile Admin Dashboard.

create or replace function public.admin_list_users()
returns table (
  id uuid,
  email text,
  name text,
  role text,
  status text,
  bio text,
  phone text,
  location text,
  profile_image_path text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public, auth
as $$
  select
    au.id,
    au.email::text,
    coalesce(p.name, au.raw_user_meta_data ->> 'name', split_part(au.email, '@', 1)) as name,
    coalesce(p.role, 'user') as role,
    coalesce(p.status, 'active') as status,
    p.bio,
    p.phone,
    p.location,
    p.profile_image_path,
    au.created_at,
    coalesce(p.updated_at, au.updated_at, au.created_at) as updated_at
  from auth.users au
  left join public.profiles p on p.id = au.id
  where exists (
    select 1
    from public.profiles requester
    where requester.id = auth.uid()
      and requester.role = 'admin'
      and coalesce(requester.status, 'active') = 'active'
  )
  order by au.created_at desc;
$$;

revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;
