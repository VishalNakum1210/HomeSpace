# Cartoon redesign — phase 2: photo flows

## Implemented

- Search switches to a compact results layout, keeping the same input/controller.
  Back or Close search clears the query and restores the main Photos header.
  The existing Favorites/Videos scope still applies when searching.
- Photo selection keeps search and results visible. Labeled pastel action cards
  provide Favorite/Unfavorite, Add to album and Trash; a full-width neutral Clear
  selection control exits without changing saved data. The panel sits above the
  floating dock and scroll content has extra bottom padding.
- Selected photo checkmarks and outlines use blue. Other photo/album/Trash
  selection controls reuse this visual treatment.
- Viewer uses a larger neutral canvas and a compact date/title/count header.
  Labeled Favorite, Add to album, Info and Trash actions follow reference screens
  03–04. Explicit previous/next and zoom controls remain available for accessibility.
  Trash viewing retains Restore/Delete and Info.
- Pinch/double-tap zoom, swipe paging, stable filtered sequences, hidden controls,
  confirmation/Undo and failed-save behavior are preserved.
- Photo details use a rounded sheet with tinted icon blocks, actual date/time and
  bundled filename, offline availability, albums and per-album attribution.
  No invented image dimensions, file sizes or upload status are displayed.
- The viewer stays dark; its details sheet follows the saved Light/Dark/System
  appearance setting. Sheet content scrolls on smaller screens.
- Version 0.4.1+5. No runtime dependencies, storage schema changes or migrations.

## Validation

- Full suite: **58 tests passed**, including the existing viewer, selection,
  persistence, permissions, Trash, accessibility and reduced-motion checks.
- Four additional tests cover compact search/Back, action placement and Clear,
  details metadata/appearance, and hiding/restoring viewer chrome.
- Existing tests exercise 320 × 700 and 740 × 360 with double-size text.
- Static analysis: no issues found.
- Widget-rendered previews use Nunito and MaterialIcons at 390 × 844 and 2× export.
  They are test-renderer previews rather than phone screenshots.

Generate optional previews:

```sh
flutter test test/cartoon_photo_flows_test.dart --dart-define=HOMESPACE_CAPTURE=true
```

Previews are saved under `output/previews/cartoon-phase-2-`:
`search-light.png`, `selection-light.png`, `viewer.png`, `details-light.png`,
and `details-dark.png`. Build/test/analyze logs are ignored local artifacts.

The final search-result wording and preview export also passed all four targeted
photo-flow tests after the full suite. Reviewed all five exported screens.

## Android artifact

The release APK is archived at
`output/releases/homespace-cartoon-phase-2-android.apk` (0.4.1+5).
It keeps the existing development signing configuration. Installation on the
physical phone is separate; its currently installed redesign is phase 1.

Final build: 83.9 seconds; APK size: 54,277,332 bytes.
SHA-256: `38075D590945ABF57B1869F5AF4108BDD896C9C6E1E32F18479EB2BE506F6C9B`.

## Next

Phase 3 redesigns album detail, create/edit, photo picking, members and permissions.
Phase 4 covers settings, appearance, trash and recovery. Real uploads, invitations,
server integration, device-media import and playback remain separate work.
