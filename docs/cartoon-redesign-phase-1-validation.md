# Cartoon redesign — phase 1

## Implemented

- Photos: compact branded header, welcome heading, transparent illustrated garden,
  search, All/Favorites/Videos filters and date-grouped media.
- Collections: small illustrated album header, pastel framed cover cards, shared
  badges and member initials, filters and a full-width tactile Create album button.
- Profile: branded header, greeting/house card, tactile Edit profile button and
  separate colorful settings cards. Existing settings actions remain functional.
- Existing house logo, Nunito, Smooth Clay navigation and button shape retained.
  Button text uses a dark neutral for adequate contrast on purple.
- Version 0.4.0+4. No dependency or storage schema changes.

## Checks

- All **54 tests passed**. Includes local file recovery, saved state, roles,
  viewer/selection/Trash actions, narrow/landscape and double-size text.
- Flutter analysis: **no issues found**.
- New test checks that primary Create album/Edit profile actions remain above
  the dock at 390 × 844, in both themes. Videos filtering does not alter data.
- Existing design accessibility tests cover touch targets, labels and contrast.
- Six actual Flutter widget renders reviewed at 390 × 844, exported at 2×.
  These are test-renderer images, not physical-phone screenshots.

Screenshots in `output/previews/`:

- `cartoon-phase-1-photos-light.png` / `cartoon-phase-1-photos-dark.png`
- `cartoon-phase-1-collections-light.png` / `cartoon-phase-1-collections-dark.png`
- `cartoon-phase-1-profile-light.png` / `cartoon-phase-1-profile-dark.png`

Reproduce visual exports:

```sh
flutter test test/cartoon_layout_test.dart --dart-define=HOMESPACE_CAPTURE=true
```

MaterialIcons and Nunito are loaded in the export test. All retained layers are
repainted before capture so inactive-tab raster caching does not omit header icons.

## Limits

Phase 1 covers the three main pages. Secondary screens still use their working
phase-3 presentation until redesign phases 2–4. The original flattened reference
is retained in `output/design-reference/cartoon-16-screen-reference.png`.
Decorative assets have been recreated rather than extracted as original SVGs;
real current library content replaces invented mockup photos, counts and names.
No real sharing, uploads, server integration or video playback was added.

## Android artifact

Release-mode build completed in 218 seconds. Archived APK:
`output/releases/homespace-cartoon-phase-1-android.apk` (54,260,218 bytes).
It retains the existing development signing configuration. This redesign build
has not been installed on the physical phone in this phase.

SHA-256: `6FDC050176BC96BEEC65837D67FEFC88D30C6463332AA5FF01D4A69C8C04E748`.

Logs are local ignored artifacts in `output/cartoon-phase-1-*.log` and
`output/cartoon-capture.log`. Earlier APKs remain available separately.
