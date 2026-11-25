drop policy if exists report_files_admin_delete on storage.objects;
create policy report_files_admin_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'report-files'
    and exists (
      select 1 from public.admin_users au
      join public.profiles p on p.id = au.user_id
      where au.user_id = (select auth.uid())
        and p.account_status = 'active'
    )
  );
