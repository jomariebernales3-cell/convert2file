# Pending release notes

For the next Android APK after the current release, **v3.0.2.30**.

## Features added

- Users can attach an optional screenshot to a problem report. Reports and screenshots remain queued offline and send after connectivity returns; admins can open screenshots from the private report portal.
- Online Maintenance replaces the home greeting and shows a maintenance icon for guests and signed-in users.
- Admin-managed app controls stay cached on the device for offline use.
- Tapping Offline AI Assistant opens Offline AI model setup when no GGUF model is imported.
- Profile tools include study counts and recent activity, profile editing, password controls, and an optional local PIN lock. Guests can reset profile details, and saved outputs can be cleared without deleting source files or study sets.
- The mobile admin portal uses a top bar and bottom tabs below 900px. Tables become cards, Audit filters and dialogs use bottom sheets, forms stack into one column, and report selection has a mobile action bar.
- Appearance offers Day, System, and Night; System is centered and the DBZ theme was removed.
- Removed Settings storage usage information and its unused database queries, along with the Study preferences section.

## Changes added today — 2026-11-20

- Added a GitHub Actions release input that sets the APK's four-part version, creates a version-tagged GitHub release, and syncs the latest version to admin app controls after the build succeeds. Minimum-version enforcement is optional and stays unchanged by default.
- Updated the website to find the newest published APK asset from GitHub Releases, including releases with versioned APK filenames or prerelease status.
- Added an admin-managed Android APK download URL. The website reads the URL from Supabase, App control can override it, and a successful GitHub release workflow syncs the newly built APK asset URL automatically.
- Updated the email confirmation page to use the same Convert2File launcher logo as the main website.
- Replaced the Android launch-screen hourglass with a looping, theme-aware DBZ arc animation in Android's system splash screen. Android 12 and newer keep that same animated screen visible while app initialization runs, then open the app directly; older Android versions use the matching native animated loader. Reduced the ring diameter and made the moving arc electric blue in both themes while keeping the DBZ logo the same size.
- Startup errors now show a retry screen after the native launch screen is dismissed.

## Admin portal updates — 2026-11-21

- Bug reports now show a live badge for new reports (a dot for one, a count through 99, then 99+), with Supabase Realtime updating the portal without manual refresh.
- Added a saved “Reply to user” field under internal admin notes in the report details dialog.
- Made the report details body scroll while keeping Save, Delete, and Close fixed in the dialog footer.
- Redesigned App Info editing with remembered category tabs, item counts, collapsed one-at-a-time editors, live row summaries, update-history search, and confirmation before removal. Existing Supabase fields, ordering, validation, and save RPC remain in use.

## Bugs fixed and behavior improved

- Retired announcements no longer reappear from old cached announcement data.
- Cached Update History appears immediately offline while the app refreshes managed release notes in the background.
- Settings > About shows the admin-selected latest release version, refreshes after returning from App Info or resuming the app, and uses cached release history offline.
- Sign-in reads the installed package version and build number, then compares them with the admin minimum-version setting.
- Sign-in reports when there is no internet connection and suggests guest mode.
- New account passwords and password resets require at least 8 characters and one special character.
