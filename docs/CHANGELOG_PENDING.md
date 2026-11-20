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

- Replaced the Flutter startup loading screen with the supplied DBZ logo artwork and a continuously animated arc. The logo, arc, and background match the selected light or dark theme.
- Replaced the Android native launch-screen hourglass with the corresponding light or dark logo and matching loading ring, so the new logo appears from the first launch frame.
- The animated startup screen remains visible while Supabase, authentication, theme, Offline AI, and app-lock initialization runs. It offers a retry action if startup initialization fails.

## Bugs fixed and behavior improved

- Retired announcements no longer reappear from old cached announcement data.
- Cached Update History appears immediately offline while the app refreshes managed release notes in the background.
- Settings > About shows the admin-selected latest release version, refreshes after returning from App Info or resuming the app, and uses cached release history offline.
- Sign-in reads the installed package version and build number, then compares them with the admin minimum-version setting.
- Sign-in reports when there is no internet connection and suggests guest mode.
- New account passwords and password resets require at least 8 characters and one special character.
