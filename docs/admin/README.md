# Convert2File Admin Portal

This is a separate static website from the Flutter app. It uses the mockup's appearance language and the app's Day, Night, DBZ, and System color roles. It contains Dashboard, Users, Bug reports, Announcements, App control, Admin team, and Audit log.

## Backend setup

Use a **new Supabase project** so existing app accounts and data remain untouched.

1. Create the first Owner account in the new project's Auth settings (email/password).
2. In the new project's SQL Editor, run `supabase/migrations/202611090001_admin_portal.sql` from the repository.
3. Run `supabase/migrations/202611100001_admin_controls.sql` to add announcement and app-control storage.
4. Run `supabase/migrations/202611110002_announcements.sql` to create the `public.announcements` table used by the Announcements page.
5. In SQL Editor, bootstrap the first Owner, replacing the email:

   ```sql
   insert into public.admin_users(user_id, role)
   select id, 'owner' from auth.users
   where lower(email) = lower('owner@example.com');
   ```

6. Run `supabase/migrations/202611210002_admin_report_realtime_replies.sql` to enable live report change events and add the report reply field.
7. Run `supabase/migrations/202611210003_private_report_reply_announcements.sql`, then `supabase/migrations/202611210004_separate_report_reply_send.sql`, to deliver admin replies privately to the reporting account's in-app Announcements. The portal's **Send reply** button sends the message; **Save report** only saves status and internal notes.
8. Run `supabase/migrations/202611250001_announcement_version_retirement.sql` to enable the optional announcement **Hide at installed app version** field. Set it to the release version (for example, `3.0.3.35`) so the notice is hidden after a device installs that version.
9. Run `supabase/migrations/202611250002_report_attachment_cleanup.sql` to allow the admin portal to delete report attachments from the private Storage bucket when their report is deleted.

10. Set the new project's Project URL and **publishable key** in `config.js`. This key is designed for browser use; the database RLS policies are the security boundary. Never place a secret key in this website, the Flutter app, or GitHub.
11. Serve `docs/` locally with VS Code Live Server and open `/admin/`. The page must be served over HTTP/HTTPS; opening the HTML as `file://` will prevent its ES module imports from loading.
12. For GitHub Pages, this portal is available at `https://jomariebernales3-cell.github.io/convert2file/admin/` after the `docs/admin` files and public `config.js` are pushed to `main`. Because the URL and publishable key are public client settings, protect the data with the included RLS and RPC authorization.

## Publishing an Android release

The GitHub Actions workflow **Build Android release APK** is the source for the APK version. Before using it:

1. Apply the release migrations `202611200001_ci_publish_app_release_version.sql` and `202611210001_admin_managed_apk_download.sql` to the same Supabase project configured above and in `lib/services/supabase_config.dart`.
2. In the repository's **Settings → Secrets and variables → Actions**, add the `SUPABASE_URL` repository variable and `SUPABASE_SECRET_KEY` repository secret. Use the project's secret key only as a GitHub Actions secret. Never put it in this portal, the Flutter app, or source control.
3. In **Actions → Build Android release APK → Run workflow**, enter the four-part version, for example `3.0.2.31`. The workflow builds the APK with that exact installed version, verifies its signing certificate matches the active v3.0.2.33 key, creates a draft GitHub release, updates the admin latest version and APK download URL, then publishes the release. If the signing key changes, the workflow stops before publication.
4. Leave **enforce minimum** off to keep the current sign-in requirement. Turn it on only when you intend to require users to install this release; the minimum is changed after the APK is built.

The existing `ANDROID_KEYSTORE_BASE64` Actions secret is also required. After publishing, the website's Download button uses the URL synced to Supabase. An administrator can override it in **App control → Android APK download URL**; a later successful release workflow replaces the field with the new release asset URL.

## First admin

The Owner account is bootstrapped in SQL. To add Admin/Support accounts, create the Auth user in Supabase Dashboard first; the Owner can then assign that account's email from Admin team. The portal does not create or invite Auth users and has no service-role credential.

## Account suspension

Suspension changes `profiles.account_status`. RLS and the admin RPCs check that status, blocking access to protected online tables and portal actions. It does not delete local files, stop offline work, or revoke the Supabase Auth session on every device. Existing sessions lose access to protected database operations; the portal re-checks status when it refreshes.

## App integration still needed

The current Flutter app is still configured for the existing Supabase project, and its bug reports are local-only. The Announcements and App control pages store values in the new project, but they do not affect the installed app until Flutter is connected to this project and reads those settings. The mobile app must also submit text-only reports after clear consent and check account status at sign-in/session refresh. Existing accounts in the old project do not automatically transfer; either users register again or account migration is planned separately.
