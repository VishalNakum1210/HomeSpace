# HomeSpace — Android frontend

The playful HomeSpace family photo library, built with Flutter for Android only. Phase 2 adds real local persistence and repository interfaces for the future home server.

## Included

- Locally bundled Nunito typography, an original house mascot, and colorful code-drawn page symbols.
- Green Photos, purple Collections, and orange Profile accents on neutral surfaces.
- Compact icon-only floating navigation with a **blue circle** behind the active icon.
- Light, dark, and device appearance modes; a working appearance chooser in Profile.
- Shared tactile buttons, cards, filters, inputs, badges, empty states, and modal sheets.
- Offline sample photo/album previews, local search and favorites, preserved tab scroll state, and Android Back handling.
- Accessible control names, 48px touch targets, larger text layouts, and reduced-motion support.

This is a frontend preview with bundled sample media. Profile, appearance, favorites, albums, roles, and trash metadata persist locally across app restarts. You can create/rename local albums, add photos to multiple albums, and edit your local profile. Complete media viewing/video playback and the full sharing, connection, upload, and Trash screens belong to later phases. Server features are simulated; no files are uploaded. The APK uses development signing until the release-packaging phase.

Local saves use versioned JSON with a previous valid backup, serialized writes, and recovery without silently resetting damaged/newer data. See [phase-two implementation](docs/phase-2.md) for the architecture, role rules, and demo-state flags.

## Run and verify

Requires Flutter 3.47.7 / Dart 3.13.5 or a compatible SDK and an Android SDK.

```sh
flutter pub get
flutter run -d <android-device>
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`.

The current preview is saved as `output/releases/homespace-phase-2-android.apk` (49.6 MiB). It is installed on the connected Redmi Note 11; the selected dark theme survived a full process restart and an APK update. See [phase-two validation](docs/phase-2-validation.md) for tests, checksum, actual phone screenshots, and limits. Generated APKs and screenshots remain local ignored artifacts. [Phase-one validation](docs/phase-1-validation.md) records the earlier design checks.

## Source

- `lib/app.dart`: app shell, persisted theme, boot states, primary navigation, and Back behavior.
- `lib/design/`: color/typography tokens, navigation, symbols, and shared controls.
- `lib/pages/`: Photos, Collections, and Profile page previews.
- `lib/domain/`: typed models and repository contracts.
- `lib/data/`: sample seed, persistence/validation, local operations, and remote-state simulations.
- `lib/application/`: repository binding and save-error handling.
- `test/`: design, real-file recovery, roles, serialized saves, app recreation, and demo-state checks.
- `docs/phase-1.md`: scope, design decisions, and deferred work.

Nunito's OFL license is included in `assets/fonts/OFL.txt` and exposed through the About sheet. Sample photo sources are listed in `assets/photos/SOURCES.md`.
