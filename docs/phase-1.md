# Phase 1 — Android design foundation

## Scope

This workspace contained only Git metadata when implementation began. An Android-only Flutter scaffold was created without restoring the deleted previous app.

Implemented:
- Nunito variable font bundled locally, with OFL license.
- Original code-drawn house mascot and green photo / purple collection / orange profile icons.
- Neutral surfaces with page-specific accent tokens and light/dark/system themes.
- Shared cards, badges, filters, fields, section headings, empty states, tactile buttons, and modal sheets.
- Compact 216x64 floating navigation, icon-only, with a true 48px blue circular active background.
- Accessible navigation labels and at least 48px tap targets.
- Photos, Collections, and Profile previews, with local sample filtering, early media/album sheets, and a working appearance chooser.
- Indexed tab preservation, safe-area/content spacing, Android Back handling, keyboard dismissal, and reduced motion.
- Android edge-to-edge setup and system navigation colors that follow light/dark appearance.
- Android branding title HomeSpace; no web/iOS/Windows platform scaffold.

## Deferred to later phases

Persistent storage, complete media viewer, real video playback, album creation/member management, connection/sign-in, upload queue, Trash, server integration, final launcher/splash assets, production signing, and release distribution.

Preview favorites and theme changes last for the running session. The source uses Flutter's default development signing, so the APK is a phase preview, not the final production release.

## Design rules

- Photos: green #58CC02.
- Collections: purple #A560F5.
- Profile: orange #FF9600.
- Blue circular active background: #CEEAFE in light mode, #244E70 in dark mode.
- Selected icons keep their own colors. The circle stays blue on all tabs.
- Main content stays neutral; photos are not recolored.
- Text and target sizes respect Android settings; brand wordmark scales down only when necessary.
- Button press: 80ms down / 160ms settle; navigation: 220ms; theme: 200ms. Reduced motion removes travel.

## Validation

Run:
- flutter analyze --no-pub
- flutter test --no-pub
- flutter build apk --release --no-pub

Device/render evidence and exact results are recorded after verification in README.md.
