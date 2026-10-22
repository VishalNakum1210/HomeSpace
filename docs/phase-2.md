# Phase 2 — persistent local data and repository interfaces

## Implemented

- Immutable typed models for media, albums, per-album membership roles, local profile/appearance/avatar settings, trash entries, connection status, and upload queue items.
- Stable string IDs independent of list positions and album names. A media item may belong to several albums without duplication.
- Separate library, album, profile, connection, and upload contracts. Screens subscribe to HomeRepository through HomeScope; the local implementation can be replaced for the future server.
- Serialized, pessimistic saves: a change appears as saved only after storage succeeds. A failed write leaves previous visible/saved state intact and does not block later queued changes.
- Schema-versioned JSON in the Android application documents directory, under homespace/library.json.
- Flushed pending writes, a previous valid backup, recovery from completed pending/backup files, and preservation of corrupted bytes. Unrecoverable or newer-schema data blocks loading with a retry/update message rather than resetting the library.
- Persisted theme, local profile name/avatar color, favorites, albums, membership roles, contributor attribution, and trash timestamps.
- Role rules in the local demo: owners manage names/members; contributors add media and remove their own additions; viewers browse. Owner removal/implicit ownership transfer is rejected.
- Trash/restore keeps album membership. Permanent deletion requires a trashed item and removes its metadata references from every album, favorite, and cover. Bundled sample asset files are never deleted.
- Existing Photos/Collections/Profile views now read repositories. Added local create/rename album sheets, multi-album photo assignment, and a local profile editor to make persistence reviewable.
- Bootstrap loading, read-error/retry, and save-error UI. Save errors are shown above modal sheets and do not falsely acknowledge success.
- Reproducible populated, empty, loading, offline, failed, and success fixtures. Changing the fixture never overwrites the actual saved library.
- Explicitly simulated connection/upload repositories. They make no network requests or external invitations, persist no credentials, and advance progress only through explicit fixture actions.

## Review states

Run with, for example:

    flutter run -d <android-device> --dart-define=HOMESPACE_SCENARIO=offline

Valid values: populated, empty, loading, offline, failed, success. Default: populated.
The failed fixture offers Try again. Loading is intentionally held for review.
Fixture selection is not persisted. Empty/loading/error previews do not erase stored local changes.

## Data layout

- lib/domain/models.dart — immutable domain types.
- lib/domain/repositories.dart — service contracts.
- lib/data/seed_library.dart — bundled sample catalog and family.
- lib/data/snapshot_codec.dart — schema and reference validation.
- lib/data/snapshot_store.dart — file and in-memory adapters.
- lib/data/local_home_repository.dart — serial transactions and local rules.
- lib/data/demo_remote_repositories.dart — connection and upload fixtures.
- lib/application/home_scope.dart — presentation binding and error handling.

The only new runtime dependency is Flutter's path_provider 2.1.6 (resolved with its platform packages).
Primary references:
- https://docs.flutter.dev/cookbook/persistence/reading-writing-files
- https://pub.dev/packages/path_provider

## Still in later phases

Full swipe/zoom/video viewer, complete collection/member management screens, connection/sign-in page, upload page, Trash page, real server/authentication/sharing/backup, final launcher/splash, production signing, and release-quality performance checks.

Client-side demo roles are not server authorization. No real family data is uploaded or shared.
