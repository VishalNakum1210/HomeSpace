# HomeSpace — Android design foundation

Phase 1 of the playful HomeSpace family photo library, built with Flutter for Android only.

## Included

- Locally bundled Nunito typography, an original house mascot, and colorful code-drawn page symbols.
- Green Photos, purple Collections, and orange Profile accents on neutral surfaces.
- Compact icon-only floating navigation with a **blue circle** behind the active icon.
- Light, dark, and device appearance modes; a working appearance chooser in Profile.
- Shared tactile buttons, cards, filters, inputs, badges, empty states, and modal sheets.
- Offline sample photo/album previews, local search and favorites, preserved tab scroll state, and Android Back handling.
- Accessible control names, 48px touch targets, larger text layouts, and reduced-motion support.

This is a design foundation preview. Changes stay in the current session. Persistent data, complete media viewing/video playback, album membership/sharing, connection/sign-in, uploads, and Trash belong to the later phases. Server features are not connected. The APK uses development signing until the release-packaging phase.

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

The verified phase preview is saved as `output/releases/homespace-phase-1-android.apk` (48.4 MiB). Seven actual Android screenshots are in `output/previews/`. See [validation results](docs/phase-1-validation.md) for the test results, APK checksum, screenshots, and device-check limitations.

## Source

- `lib/app.dart`: theme state, app shell, primary navigation, and Back behavior.
- `lib/design/`: color/typography tokens, navigation, symbols, and shared controls.
- `lib/pages/`: Photos, Collections, and Profile page previews.
- `lib/sample/`: offline sample data.
- `test/design_foundation_test.dart`: nine behavior/layout/accessibility checks.
- `docs/phase-1.md`: scope, design decisions, and deferred work.

Nunito's OFL license is included in `assets/fonts/OFL.txt` and exposed through the About sheet. Sample photo sources are listed in `assets/photos/SOURCES.md`.
