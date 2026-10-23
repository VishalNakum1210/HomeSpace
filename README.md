# HomeSpace — Android frontend

The playful HomeSpace family photo library, built with Flutter for Android only. Phase 3 adds the photo viewer, selection actions, album management, and Trash on top of persistent local repositories.

The cartoon redesign is now in phase 1: Photos, Collections and Profile follow the
approved illustrated direction, with the existing house logo, Nunito, tactile
buttons and Smooth Clay dock. See [the four-phase redesign plan](docs/cartoon-redesign.md).
The new garden banner is bundled offline; secondary flows keep their existing
working UI until their redesign phases.
See [redesign phase-one validation](docs/cartoon-redesign-phase-1-validation.md)
for checks and previews. Its APK is
`output/releases/homespace-cartoon-phase-1-android.apk` (version 0.4.0+4).

## Included

- Locally bundled Nunito typography, an original house mascot, and colorful code-drawn page symbols.
- Green Photos, purple Collections, and orange Profile accents on neutral surfaces.
- Compact icon-only floating navigation with a **blue circle** behind the active icon.
- Light, dark, and device appearance modes; a working appearance chooser in Profile.
- Shared tactile buttons, cards, filters, inputs, badges, empty states, and modal sheets.
- Offline sample library, local search and favorites, preserved tab scroll state, and Android Back handling.
- Full-screen photo viewing with swipe, pinch/double-tap zoom, accessible paging/zoom controls, and photo details.
- Photo selection, batch favorites, multi-album assignment, Trash, and Undo.
- Album pages with photo picking/removal, editable name/description, cover selection, and deletion that keeps library photos.
- Local shared-album member controls with owner, contributor, and viewer roles.
- Trash page with single/batch restore, explicit permanent-delete confirmation, and empty states.
- Accessible control names, 48px touch targets, larger text layouts, and reduced-motion support.

This is a frontend preview with bundled sample photos. Profile, appearance, favorites, albums, roles, and trash metadata persist locally across app restarts. Sharing controls change the local demo only; they send no invitations. Video playback, device-media import, connection/authentication, upload screens, and real server integration remain in later phases. No files are uploaded. The APK uses development signing until the release-packaging phase.

Local saves use versioned JSON with a previous valid backup, serialized writes, and recovery without silently resetting damaged/newer data. Selection actions commit the whole batch together. Phase 3 keeps the existing schema and saved libraries. See [phase-three implementation](docs/phase-3.md) for current flows and [phase-two implementation](docs/phase-2.md) for the data architecture and demo-state flags.

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

The current preview is saved as `output/releases/homespace-phase-3-android.apk` (50.7 MiB). See [phase-three validation](docs/phase-3-validation.md) for tests, checksum, actual Android screenshots, and limits. Generated APKs and screenshots remain local ignored artifacts. Earlier checks are recorded in [phase-one validation](docs/phase-1-validation.md) and [phase-two validation](docs/phase-2-validation.md).

## Source

- `lib/app.dart`: app shell, persisted theme, boot states, primary navigation, and Back behavior.
- `lib/design/`: color/typography tokens, navigation, symbols, and shared controls.
- `lib/pages/`: primary pages, photo viewer, album/member flows, photo picker, Trash, and shared presentation helpers.
- `lib/domain/`: typed models and repository contracts.
- `lib/data/`: sample seed, persistence/validation, local operations, and remote-state simulations.
- `lib/application/`: repository binding and save-error handling.
- `test/`: design, real-file recovery, roles, serialized saves, app recreation, and demo-state checks.
- `docs/phase-1.md`: scope, design decisions, and deferred work.

Nunito's OFL license is included in `assets/fonts/OFL.txt` and exposed through the About sheet. Sample photo sources are listed in `assets/photos/SOURCES.md`.
