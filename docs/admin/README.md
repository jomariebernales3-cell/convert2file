# Convert2File Admin Portal

This is a separate static website from the Flutter app. It uses the mockup's appearance language and the app's Day, Night, DBZ, and System color roles. The first version contains Dashboard, Users, Bug reports, Admin team, and Audit log. Announcements and App control are intentionally excluded from v1.

## Backend setup

Use a **new Supabase project** so existing app accounts and data remain untouched.

1. Create the first Owner account in the new project's Auth settings (email/password).
2. In the new project's SQL Editor, run `supabase/migrations/202611090001_admin_portal.sql` from the repository.
3. In SQL Editor, bootstrap the first Owner, replacing the email:

   ```sql
   insert into public.admin_users(user_id, role)
   select id, 'owner' from auth.users
   where lower(email) = lower('owner@example.com');
   ```

4. Set the new project's Project URL and **anon/publishable key** in `config.js`. This key is designed for browser use; the database RLS policies are the security boundary. Never place the `service_role` or secret key in this website, the Flutter app, or GitHub.
5. Serve `docs/` locally with VS Code Live Server and open `/admin/`. The page must be served over HTTP/HTTPS; opening the HTML as `file://` will prevent its ES module imports from loading.
6. For GitHub Pages, this portal is available at `https://jomariebernales3-cell.github.io/convert2file/admin/` after the `docs/admin` files and public `config.js` are pushed to `main`. Because the URL and anon key are public client settings, protect the data with the included RLS and RPC authorization.

## First admin

The Owner account is bootstrapped in SQL. To add Admin/Support accounts, create the Auth user in Supabase Dashboard first; the Owner can then assign that account's email from Admin team. The portal does not create or invite Auth users and has no service-role credential.

## Account suspension

Suspension changes `profiles.account_status`. RLS and the admin RPCs check that status, blocking access to protected online tables and portal actions. It does not delete local files, stop offline work, or revoke the Supabase Auth session on every device. Existing sessions lose access to protected database operations; the portal re-checks status when it refreshes.

## App integration still needed

The current Flutter app is still configured for the existing Supabase project, and its bug reports are local-only. To populate this new project, the mobile app must later be pointed at the new project, submit text-only reports after clear consent, and check account status at sign-in/session refresh. Existing accounts in the old project do not automatically transfer; either users register again or account migration is planned separately.
