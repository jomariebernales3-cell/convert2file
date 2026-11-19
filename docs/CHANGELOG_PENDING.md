# Pending release notes

Use this list when preparing the next public release notes. Current app version: 1.0.27 (build 30).

## Features added

- Users can attach an optional screenshot to a problem report. Reports and screenshots remain queued offline and send after connectivity returns; admins can open screenshots from the private report portal.
- Online Maintenance replaces the home greeting and shows a wrench icon for guest and signed-in users.
- Admin-managed app controls stay cached for offline use.
- The Appearance selector now offers Day, System, and Night; System is centered and the DBZ theme was removed.
- Removed Settings storage usage statistics and their unused database queries.
- Tapping Offline AI Assistant opens the Offline AI model setup screen when no GGUF model is imported.

## Bugs fixed and behavior improved

- Cached Update History appears immediately offline while the app refreshes managed release notes in the background.
- The Settings About card shows the admin-marked current release version and uses cached release history offline.
- Sign-in reports when there is no internet connection and suggests guest mode.
- New account passwords and password resets require at least 8 characters and one special character.
- Retired announcements no longer reappear from old cached announcement data.
