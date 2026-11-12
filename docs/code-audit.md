# Frontend cleanup audit

Reviewed Dart application, domain, repository and design code, current call
sites, test consumers, and bundled illustrations. The initial analyzer reported
no unused imports or statically unreachable statements. Manual call-site checks
identified obsolete public widgets and branches that the analyzer does not flag.

Changes:

- Removed unused `SpaceBadge`, `SpacePageHeading`, `SpaceSymbol`, and the old
  `_PagePainter` used only by that obsolete heading. Current Clay navigation and
  the house logo retain their existing painters.
- Removed unused thumbnail text-overlay rendering and the `avatarAttribution`
  and `showSubtitle` switches. Shared-album attribution portraits and spoken
  Trash dates remain; a real attribution member now directly controls portraits.
- Removed the impossible category-filter fallback and a search-results count
  branch nested inside `if (!focused)`. Removed redundant `owner || canAdd`
  logic and the forwarding-only `chooseTheme` method.
- Consolidated Android system-bar styling in `design/system_ui.dart` across
  the app shell, pushed pages, Appearance, authentication and photo viewer.
  The viewer keeps its custom background and authentication its light theme.
- Consolidated newest-first photo sorting and timeline grouping. Photos and
  albums group once per build, preserving date order and tied-ID ordering,
  instead of repeatedly filtering and walking photos for every tile.
- Organized Dart imports consistently, removing the obsolete symbol import.
- Narrowed the illustration asset entry to the approved authentication image.
  The unused historical `memory-garden.png` and artwork README stay as source
  material but are excluded from the APK. Current SVGs remain bundled.

Repository APIs used by tests (single-item operations and demo fixture controls),
Flutter lifecycle overrides, recovery handling and permission checks are active
code and were retained. No persisted data schema or account behavior changed.

Verification logs are local artifacts in `output/audit-*.log`. The new timeline
test checks date-group order, stable ties, empty input and one label lookup per
photo; existing gesture, navigation-race, persistence, authentication and layout
tests cover the surrounding behavior.

Final verification (0.8.1+16): analyzer clean; all 104 tests pass; Android release
APK built successfully. All 38 Dart files are reachable through imports from
`main.dart`. APK asset inspection confirms the approved auth artwork and SVGs
are included and the historical memory garden raster is excluded. Archived
preview: `output/releases/homespace-android-0.8.1+16-preview.apk`.
