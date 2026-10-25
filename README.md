# HomeSpace — Android frontend

HomeSpace is a playful family photo library built with Flutter for Android,
with photo viewing, selection, album/member management, Trash and persistent local data.

The four-phase cartoon redesign is complete. Photos, Collections, Profile,
photo/album flows, settings and recovery follow the approved illustrated direction,
with the existing house logo, Nunito, tactile buttons and Smooth Clay dock.
The garden banner is bundled offline; supporting illustrations reuse the original
code-drawn house. See [the completed redesign plan](docs/cartoon-redesign.md),
[photo flows](docs/cartoon-redesign-phase-2.md),
[album flows](docs/cartoon-redesign-phase-3.md) and
[settings/recovery validation](docs/cartoon-redesign-phase-4.md).

Frontend phase 5 adds Home server and Upload queue pages through Profile, using
the same artwork, typography and controls. See [phase-five implementation and
validation](docs/frontend-phase-5.md).

Phase 6 adds native Android launcher/splash branding and repeatable packaging.
See [phase-six validation](docs/frontend-phase-6.md) and the
[Android signing/build guide](docs/android-release.md).

Phase 7 adds connected-phone validation and a Back-navigation fix that preserves
photo search/selection when returning from another tab. See
[Android validation and polish](docs/frontend-phase-7.md).

## Included

- Locally bundled Nunito typography, an original house mascot, and colorful code-drawn page symbols.
- Green Photos, purple Collections, and orange Profile accents on neutral surfaces.
- Compact icon-only floating navigation with a **blue circle** behind the active icon.
- Light, dark, and device appearance modes; a full-page appearance preview with explicit Done/Back behavior.
- Shared tactile buttons, cards, filters, inputs, badges, empty states, and modal sheets.
- Offline sample library, local search and favorites, preserved tab scroll state, and Android Back handling.
- Full-screen photo viewing with swipe, pinch/double-tap zoom, accessible paging/zoom controls, and photo details.
- Photo selection, batch favorites, multi-album assignment, Trash, and Undo.
- Album pages with photo picking/removal, editable name/description, cover selection, and deletion that keeps library photos.
- Local shared-album member controls with owner, contributor, and viewer roles.
- Trash page with single/batch restore, explicit permanent-delete confirmation, and empty states.
- Home-server address validation, connection preview, cancel/disconnect and retry states.
- Sample upload queue with All/Active/Finished filters, pause/resume, retry and confirmed cancellation.
- Accessible control names, 48px touch targets, larger text layouts, and reduced-motion support.
- Branded legacy/adaptive/themed Android launcher icons and light/dark native launch screens.

This is a frontend preview with bundled sample photos. Profile, appearance, favorites, albums, roles, and trash metadata persist locally across app restarts. Sharing controls change the local demo only; they send no invitations. Connection and queue screens use explicit session-only simulations. Addresses are validated but never contacted; queue progress uses labeled sample values and never advances automatically. Video playback, device-media import, authentication and real server integration remain future work. No files are uploaded. The preview APK uses development signing; owner-signed production builds require explicit release configuration.

Local saves use versioned JSON with a previous valid backup, serialized writes, and recovery without silently resetting damaged/newer data. Selection actions commit the whole batch together. The redesign keeps the existing schema and saved libraries. See [phase-three implementation](docs/phase-3.md) for current flows and [phase-two implementation](docs/phase-2.md) for the data architecture and demo-state flags.

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

The current redesigned preview is saved as
`output/releases/homespace-android-0.6.1+10-preview.apk` (version 0.6.1+10).
See [frontend phase-seven validation](docs/frontend-phase-7.md) for checks
and preview locations. The earlier functional phase-3 build and its Android
screenshots remain documented in [phase-three validation](docs/phase-3-validation.md).
Generated APKs and screenshots remain local ignored artifacts. Earlier checks
are recorded in [phase-one validation](docs/phase-1-validation.md) and
[phase-two validation](docs/phase-2-validation.md).

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
